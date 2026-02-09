use anyhow::{anyhow, Result};
use log::debug;
use regex::Regex;
use std::collections::HashMap;

pub struct TemplateRenderer {
    var_regex: Regex,
}

impl TemplateRenderer {
    pub fn new() -> Self {
        // Matches ${VAR}, ${VAR:-default}, ${VAR:-}
        // Capture groups: 1=VAR, 2=:-default (optional), 3=default value (optional)
        let var_regex = Regex::new(r"\$\{([a-zA-Z_][a-zA-Z0-9_]*)(:-([^}]*))?\}").unwrap();

        TemplateRenderer { var_regex }
    }

    /// Renders a template string by replacing ${VAR} and ${VAR:-default} with context values
    ///
    /// # Arguments
    /// * `template` - The template string (e.g., "postgresql://${USER}:${PASS}@${HOST:-localhost}")
    /// * `context` - HashMap of variable names to values
    ///
    /// # Returns
    /// * Ok(rendered_string) - Successfully rendered template
    /// * Err - If a required variable is missing (strict mode: ${VAR} without default)
    pub fn render(&self, template: &str, context: &HashMap<String, String>) -> Result<String> {
        let mut last_index = 0;
        let mut rendered = String::new();

        for captures in self.var_regex.captures_iter(template) {
            let full_match = captures.get(0).unwrap();
            let var_name = captures.get(1).unwrap().as_str();
            let has_default = captures.get(2).is_some();
            let default_value = captures.get(3).map(|m| m.as_str()).unwrap_or("");

            // Add the text before this match
            rendered.push_str(&template[last_index..full_match.start()]);

            // Resolve the variable
            // Priority: 1. Context (from .env.example) -> 2. Shell environment -> 3. Default value
            let resolved_value = if let Some(value) = context.get(var_name) {
                debug!("Resolved ${{{}}}: '{}' (from context)", var_name, value);
                value.clone()
            } else if let Ok(env_value) = std::env::var(var_name) {
                debug!("Resolved ${{{}}}: '{}' (from shell environment)", var_name, env_value);
                env_value
            } else if has_default {
                debug!("Resolved ${{{}}}: '{}' (using default)", var_name, default_value);
                default_value.to_string()
            } else {
                // Strict mode: variable not found and no default
                return Err(anyhow!(
                    "Required variable '{}' not found in context, shell environment, or default. \
                     Use ${{{}:-default}} syntax to provide a default value.",
                    var_name, var_name
                ));
            };

            rendered.push_str(&resolved_value);
            last_index = full_match.end();
        }

        // Add remaining text after last match
        rendered.push_str(&template[last_index..]);

        Ok(rendered)
    }

    /// Checks if a string contains template variables
    pub fn contains_variables(&self, s: &str) -> bool {
        self.var_regex.is_match(s)
    }
}

impl Default for TemplateRenderer {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_context() -> HashMap<String, String> {
        let mut ctx = HashMap::new();
        ctx.insert("USER".to_string(), "app_user".to_string());
        ctx.insert("PASS".to_string(), "secret123".to_string());
        ctx.insert("PORT".to_string(), "5432".to_string());
        ctx
    }

    #[test]
    fn test_simple_substitution() {
        let renderer = TemplateRenderer::new();
        let context = make_context();

        let template = "postgresql://${USER}:${PASS}@localhost:${PORT}";
        let result = renderer.render(template, &context).unwrap();

        assert_eq!(result, "postgresql://app_user:secret123@localhost:5432");
    }

    #[test]
    fn test_default_value_not_used() {
        let renderer = TemplateRenderer::new();
        let mut context = HashMap::new();
        context.insert("HOST".to_string(), "postgres".to_string());

        let template = "${HOST:-localhost}";
        let result = renderer.render(template, &context).unwrap();

        assert_eq!(result, "postgres");
    }

    #[test]
    fn test_default_value_used() {
        let renderer = TemplateRenderer::new();
        let context = HashMap::new();

        let template = "${HOST:-localhost}";
        let result = renderer.render(template, &context).unwrap();

        assert_eq!(result, "localhost");
    }

    #[test]
    fn test_empty_default_value() {
        let renderer = TemplateRenderer::new();
        let context = HashMap::new();

        let template = "prefix${SUFFIX:-}";
        let result = renderer.render(template, &context).unwrap();

        assert_eq!(result, "prefix");
    }

    #[test]
    fn test_strict_mode_fails() {
        let renderer = TemplateRenderer::new();
        let context = HashMap::new();

        let template = "${MISSING_VAR}";
        let result = renderer.render(template, &context);

        assert!(result.is_err());
        assert!(result.unwrap_err().to_string().contains("MISSING_VAR"));
    }

    #[test]
    fn test_complex_template() {
        let renderer = TemplateRenderer::new();
        let mut context = HashMap::new();
        context.insert("PG_USER".to_string(), "app_user".to_string());
        context.insert("PG_PASS".to_string(), "secret".to_string());
        context.insert("PG_PORT".to_string(), "5432".to_string());
        context.insert("PG_DB".to_string(), "mydb".to_string());

        let template = "postgresql://${PG_USER}:${PG_PASS}@${PG_HOST:-localhost}:${PG_PORT}/${PG_DB}${PG_SUFFIX:-}";
        let result = renderer.render(template, &context).unwrap();

        assert_eq!(result, "postgresql://app_user:secret@localhost:5432/mydb");
    }

    #[test]
    fn test_contains_variables() {
        let renderer = TemplateRenderer::new();

        assert!(renderer.contains_variables("${VAR}"));
        assert!(renderer.contains_variables("${VAR:-default}"));
        assert!(renderer.contains_variables("prefix${VAR}suffix"));
        assert!(!renderer.contains_variables("no variables here"));
        assert!(!renderer.contains_variables(""));
    }

    #[test]
    fn test_no_variables() {
        let renderer = TemplateRenderer::new();
        let context = HashMap::new();

        let template = "plain text with no variables";
        let result = renderer.render(template, &context).unwrap();

        assert_eq!(result, "plain text with no variables");
    }
}
