use anyhow::{Context, Result};
use clap::Parser;
use log::{debug, error, info, warn};
use std::collections::HashMap;

mod aws_client;
mod env_handler;
pub mod secret_masker;
mod template_parser;
mod template_renderer;

use aws_client::AwsClient;
use env_handler::{EnvHandler, Strategy};
use secret_masker::SecretMasker;
use template_parser::{EnvEntry, TemplateParser};
use template_renderer::TemplateRenderer;

#[derive(Parser)]
#[command(name = "psenv")]
#[command(about = "AWS Parameter Store to .env tool")]
#[command(version)]
struct Cli {
    #[arg(short, long)]
    #[arg(help = "Template file path (e.g., .env.example)")]
    template: String,

    #[arg(short, long)]
    #[arg(help = "Parameter Store prefix (must start with /)")]
    prefix: String,

    #[arg(short, long, default_value = ".env")]
    #[arg(help = "Output file (default: .env)")]
    output: String,

    #[arg(short, long, default_value = "overwrite")]
    #[arg(help = "Processing strategy")]
    strategy: Strategy,

    #[arg(short, long)]
    #[arg(help = "Skip these keys (comma-separated)")]
    ignore_keys: Option<String>,

    #[arg(long, default_value = "true")]
    #[arg(help = "All keys must exist, otherwise error")]
    require_all: bool,

    #[arg(short, long)]
    #[arg(help = "AWS region")]
    region: Option<String>,

    #[arg(long)]
    #[arg(help = "AWS profile")]
    profile: Option<String>,

    #[arg(long, default_value = "false")]
    #[arg(help = "Preview mode")]
    dry_run: bool,

    #[arg(short, long, default_value = "false")]
    #[arg(help = "Quiet mode")]
    quiet: bool,

    #[arg(short, long, default_value = "false")]
    #[arg(help = "Verbose logging")]
    verbose: bool,

    #[arg(long, default_value = "false")]
    #[arg(help = "Show secrets in plaintext (default: mask sensitive values)")]
    show_secrets: bool,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    // Initialize logging
    let log_level = if cli.verbose {
        "debug"
    } else if cli.quiet {
        "error"
    } else {
        "info"
    };

    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or(log_level)).init();

    if let Err(e) = run(cli).await {
        error!("Error: {}", e);
        let exit_code = match e.downcast_ref::<PsenvError>() {
            Some(PsenvError::InvalidArguments(_)) => 1,
            Some(PsenvError::RequiredParameterMissing(_)) => 3,
            Some(PsenvError::FileExists(_)) => 4,
            _ => 1,
        };
        std::process::exit(exit_code);
    }
}

async fn run(cli: Cli) -> Result<()> {
    // Validate prefix
    if !cli.prefix.starts_with('/') {
        return Err(PsenvError::InvalidArguments("Prefix must start with '/'".to_string()).into());
    }

    debug!("Starting psenv with template: {}, prefix: {}, output: {}",
           cli.template, cli.prefix, cli.output);

    // Parse ignore keys
    let ignore_keys: Vec<String> = cli.ignore_keys
        .as_deref()
        .unwrap_or("")
        .split(',')
        .filter(|s| !s.trim().is_empty())
        .map(|s| s.trim().to_string())
        .collect();

    debug!("Ignore keys: {:?}", ignore_keys);

    // Parse template file to get entries with values
    let parser = TemplateParser::new();
    let entries = parser.parse_template(&cli.template)
        .with_context(|| format!("Failed to parse template file: {}", cli.template))?;

    info!("Found {} entries in template", entries.len());

    // Filter out ignored keys
    let filtered_entries: Vec<EnvEntry> = entries.into_iter()
        .filter(|entry| !ignore_keys.contains(&entry.key))
        .collect();

    info!("Processing {} entries after filtering", filtered_entries.len());

    // Initialize AWS client
    let aws_client = AwsClient::new(cli.region.as_deref(), cli.profile.as_deref()).await
        .with_context(|| "Failed to initialize AWS client")?;

    // Initialize template renderer
    let renderer = TemplateRenderer::new();

    // === PHASE 1: Resolve Raw Variables (Source Variables) ===
    info!("Phase 1: Resolving raw variables...");
    let mut context: HashMap<String, String> = HashMap::new();
    let mut missing_keys = Vec::new();

    for entry in &filtered_entries {
        // Check if this is a raw variable (no template syntax)
        if !renderer.contains_variables(&entry.raw_value) {
            debug!("Processing raw variable: {}", entry.key);

            // Priority: 1. AWS Parameter Store -> 2. Shell Env -> 3. .env.example literal
            // AWS Parameter Store is the primary source - that's the whole point of psenv!
            let param_path = format!("{}{}", cli.prefix, entry.key);
            let value = match aws_client.get_parameter(&param_path).await {
                Ok(Some(aws_val)) => {
                    debug!("  ✓ Found in AWS Parameter Store");
                    aws_val
                }
                Ok(None) => {
                    // Not in AWS, try shell environment
                    if let Ok(env_val) = std::env::var(&entry.key) {
                        debug!("  ✓ Found in shell environment");
                        env_val
                    } else if !entry.raw_value.is_empty() {
                        // Use literal from .env.example
                        debug!("  ✓ Using literal default from template");
                        entry.raw_value.clone()
                    } else {
                        debug!("  ✗ Not found in any source");
                        missing_keys.push(entry.key.clone());
                        continue;
                    }
                }
                Err(e) => {
                    warn!("Failed to fetch {}: {}. Trying shell env or literal default.", param_path, e);
                    if let Ok(env_val) = std::env::var(&entry.key) {
                        debug!("  ✓ Fallback to shell environment");
                        env_val
                    } else if !entry.raw_value.is_empty() {
                        entry.raw_value.clone()
                    } else {
                        missing_keys.push(entry.key.clone());
                        continue;
                    }
                }
            };

            context.insert(entry.key.clone(), value);
        }
    }

    info!("Phase 1 complete: {} raw variables resolved", context.len());

    // === PHASE 2: Render Computed Variables (Template Variables) ===
    // Use iterative rendering to handle dependencies between computed variables
    info!("Phase 2: Rendering computed variables...");
    let mut unrendered: Vec<&EnvEntry> = filtered_entries.iter()
        .filter(|e| renderer.contains_variables(&e.raw_value))
        .collect();

    let max_iterations = 10;
    let mut iteration = 0;

    while !unrendered.is_empty() && iteration < max_iterations {
        iteration += 1;
        debug!("Render iteration {}: {} variables remaining", iteration, unrendered.len());

        let mut newly_rendered = Vec::new();

        for (idx, entry) in unrendered.iter().enumerate() {
            match renderer.render(&entry.raw_value, &context) {
                Ok(rendered) => {
                    debug!("  ✓ {} = {}", entry.key, rendered);
                    context.insert(entry.key.clone(), rendered);
                    newly_rendered.push(idx);
                }
                Err(_) => {
                    // Can't render yet, might depend on other variables
                    debug!("  ⏸ {} (waiting for dependencies)", entry.key);
                }
            }
        }

        // Remove successfully rendered entries
        if newly_rendered.is_empty() {
            // No progress made, remaining variables have unresolvable dependencies
            break;
        }

        // Remove in reverse order to maintain indices
        for &idx in newly_rendered.iter().rev() {
            unrendered.remove(idx);
        }
    }

    // Check for any remaining unrendered variables
    let mut render_errors = Vec::new();
    for entry in unrendered {
        match renderer.render(&entry.raw_value, &context) {
            Err(e) => {
                error!("  ✗ Failed to render {}: {}", entry.key, e);
                render_errors.push(format!("{}: {}", entry.key, e));
            }
            Ok(_) => {
                // Shouldn't happen, but just in case
                warn!("  ⚠ Variable {} was renderable but not rendered in iterations", entry.key);
            }
        }
    }

    info!("Phase 2 complete: {} total variables in context (rendered in {} iterations)",
          context.len(), iteration);

    // Check for errors
    if cli.require_all {
        if !missing_keys.is_empty() {
            return Err(PsenvError::RequiredParameterMissing(
                format!("Missing required raw variables: {}", missing_keys.join(", "))
            ).into());
        }
        if !render_errors.is_empty() {
            return Err(PsenvError::RequiredParameterMissing(
                format!("Failed to render computed variables:\n{}", render_errors.join("\n"))
            ).into());
        }
    } else {
        if !missing_keys.is_empty() {
            warn!("Missing raw variables: {}", missing_keys.join(", "));
        }
        if !render_errors.is_empty() {
            warn!("Failed to render some computed variables:\n{}", render_errors.join("\n"));
        }
    }

    // Handle .env file generation
    let env_handler = EnvHandler::new();

    if cli.dry_run {
        info!("Dry run mode - would write to: {}", cli.output);
        let masker = SecretMasker::new();
        let mut sorted_keys: Vec<&String> = context.keys().collect();
        sorted_keys.sort();

        for key in sorted_keys {
            if let Some(value) = context.get(key) {
                println!("{}", masker.format_output(key, value, cli.show_secrets));
            }
        }
    } else {
        env_handler.handle_env_file(&cli.output, &context, cli.strategy)
            .with_context(|| format!("Failed to handle .env file: {}", cli.output))?;

        info!("Successfully updated {}", cli.output);
    }

    Ok(())
}

#[derive(Debug, thiserror::Error)]
enum PsenvError {
    #[error("Invalid arguments: {0}")]
    InvalidArguments(String),

    #[error("Required parameter missing: {0}")]
    RequiredParameterMissing(String),

    #[error("File exists: {0}")]
    FileExists(String),
}