use anyhow::{Context, Result};
use log::debug;
use regex::Regex;
use std::collections::HashMap;
use std::fs;

#[derive(Debug, Clone)]
pub struct EnvEntry {
    pub key: String,
    pub raw_value: String,
}

pub struct TemplateParser {
    env_key_regex: Regex,
}

impl TemplateParser {
    pub fn new() -> Self {
        // Regex to match environment variable keys in .env files
        // Matches lines like: KEY=value, KEY= (empty value), # KEY=value (commented)
        let env_key_regex = Regex::new(r"^#?\s*([A-Z_][A-Z0-9_]*)\s*=(.*)$").unwrap();

        TemplateParser { env_key_regex }
    }

    pub fn parse_template(&self, template_path: &str) -> Result<Vec<EnvEntry>> {
        debug!("Parsing template file: {}", template_path);

        let content = fs::read_to_string(template_path)
            .with_context(|| format!("Failed to read template file: {}", template_path))?;

        let mut entries = HashMap::new();

        for (line_num, line) in content.lines().enumerate() {
            let trimmed = line.trim();

            // Skip empty lines and comments that don't contain env vars
            if trimmed.is_empty() || (trimmed.starts_with('#') && !trimmed.contains('=')) {
                continue;
            }

            if let Some(captures) = self.env_key_regex.captures(trimmed) {
                if let Some(key_match) = captures.get(1) {
                    let key = key_match.as_str().to_string();
                    let raw_value = captures.get(2)
                        .map(|m| m.as_str().trim().to_string())
                        .unwrap_or_default();

                    debug!("Found key '{}' = '{}' on line {}", key, raw_value, line_num + 1);
                    entries.insert(key.clone(), EnvEntry {
                        key,
                        raw_value,
                    });
                }
            }
        }

        let mut result: Vec<EnvEntry> = entries.into_values().collect();
        result.sort_by(|a, b| a.key.cmp(&b.key));

        debug!("Parsed {} unique entries from template", result.len());

        Ok(result)
    }
}

impl Default for TemplateParser {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::NamedTempFile;

    #[test]
    fn test_parse_template() {
        let parser = TemplateParser::new();

        let template_content = r#"
# Database configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=myapp

# API Keys
API_KEY=
SECRET_KEY=supersecret

# Comments and empty lines

# This is just a comment
ANOTHER_KEY=value
"#;

        let temp_file = NamedTempFile::new().unwrap();
        fs::write(temp_file.path(), template_content).unwrap();

        let entries = parser.parse_template(temp_file.path().to_str().unwrap()).unwrap();

        assert_eq!(entries.len(), 6);

        let keys: Vec<String> = entries.iter().map(|e| e.key.clone()).collect();
        let expected_keys = vec![
            "ANOTHER_KEY",
            "API_KEY",
            "DB_HOST",
            "DB_NAME",
            "DB_PORT",
            "SECRET_KEY",
        ];

        assert_eq!(keys, expected_keys);

        // Check values are preserved
        let db_host = entries.iter().find(|e| e.key == "DB_HOST").unwrap();
        assert_eq!(db_host.raw_value, "localhost");

        let api_key = entries.iter().find(|e| e.key == "API_KEY").unwrap();
        assert_eq!(api_key.raw_value, "");
    }

    #[test]
    fn test_parse_template_with_commented_vars() {
        let parser = TemplateParser::new();

        let template_content = r#"
DB_HOST=localhost
# DB_PORT=5432
#API_KEY=commented_out
"#;

        let temp_file = NamedTempFile::new().unwrap();
        fs::write(temp_file.path(), template_content).unwrap();

        let entries = parser.parse_template(temp_file.path().to_str().unwrap()).unwrap();

        let keys: Vec<String> = entries.iter().map(|e| e.key.clone()).collect();
        let expected_keys = vec!["API_KEY", "DB_HOST", "DB_PORT"];

        assert_eq!(keys, expected_keys);
    }

    #[test]
    fn test_parse_template_with_variable_substitution() {
        let parser = TemplateParser::new();

        let template_content = r#"
PG_HOST=${CTX_PG_HOST:-localhost}
PG_PORT=5432
DATABASE_URL=postgresql://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}
"#;

        let temp_file = NamedTempFile::new().unwrap();
        fs::write(temp_file.path(), template_content).unwrap();

        let entries = parser.parse_template(temp_file.path().to_str().unwrap()).unwrap();

        assert_eq!(entries.len(), 3);

        let pg_host = entries.iter().find(|e| e.key == "PG_HOST").unwrap();
        assert_eq!(pg_host.raw_value, "${CTX_PG_HOST:-localhost}");

        let db_url = entries.iter().find(|e| e.key == "DATABASE_URL").unwrap();
        assert_eq!(db_url.raw_value, "postgresql://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${PG_DB}");
    }
}