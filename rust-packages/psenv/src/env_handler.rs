use anyhow::{Context, Result};
use clap::ValueEnum;
use log::{debug, info};
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;

use crate::PsenvError;

#[derive(Debug, Clone, ValueEnum)]
pub enum Strategy {
    #[value(name = "update")]
    Update,
    #[value(name = "overwrite")]
    Overwrite,
    #[value(name = "error")]
    Error,
}

pub struct EnvHandler;

impl EnvHandler {
    pub fn new() -> Self {
        EnvHandler
    }

    pub fn handle_env_file(
        &self,
        output_path: &str,
        values: &HashMap<String, String>,
        strategy: Strategy,
    ) -> Result<()> {
        debug!("Handling .env file: {} with strategy: {:?}", output_path, strategy);

        let output_exists = Path::new(output_path).exists();

        match strategy {
            Strategy::Error if output_exists => {
                return Err(PsenvError::FileExists(
                    format!("Output file already exists: {}", output_path)
                ).into());
            }
            Strategy::Overwrite => {
                self.write_env_file(output_path, values)?;
            }
            Strategy::Update if output_exists => {
                self.update_env_file(output_path, values)?;
            }
            _ => {
                // For update when file doesn't exist, just create it
                self.write_env_file(output_path, values)?;
            }
        }

        info!("Successfully processed .env file: {}", output_path);
        Ok(())
    }

    fn write_env_file(&self, path: &str, values: &HashMap<String, String>) -> Result<()> {
        debug!("Writing new .env file: {}", path);

        let mut content = String::new();
        let mut sorted_keys: Vec<&String> = values.keys().collect();
        sorted_keys.sort();

        for key in sorted_keys {
            if let Some(value) = values.get(key) {
                content.push_str(&format!("{}={}\n", key, value));
            }
        }

        fs::write(path, content)
            .with_context(|| format!("Failed to write .env file: {}", path))?;

        info!("Created new .env file with {} variables", values.len());
        Ok(())
    }


    fn update_env_file(&self, path: &str, new_values: &HashMap<String, String>) -> Result<()> {
        debug!("Updating existing .env file: {}", path);

        let existing_content = fs::read_to_string(path)
            .with_context(|| format!("Failed to read existing .env file: {}", path))?;

        let (updated_content, updated_count, added_count) = self.update_preserve_format(&existing_content, new_values)?;

        fs::write(path, updated_content)
            .with_context(|| format!("Failed to write .env file: {}", path))?;

        info!("Updated .env file: updated {} variables, added {} variables", updated_count, added_count);
        Ok(())
    }



    fn update_preserve_format(&self, content: &str, new_values: &HashMap<String, String>) -> Result<(String, usize, usize)> {
        use regex::Regex;
        let env_key_regex = Regex::new(r"^#?\s*([A-Z_][A-Z0-9_]*)\s*=.*$").unwrap();

        let mut existing_keys = HashSet::new();
        let mut result = String::new();
        let mut updated_count = 0;

        // Process existing content line by line, replacing values where needed
        for line in content.lines() {
            if let Some(captures) = env_key_regex.captures(line) {
                if let Some(key_match) = captures.get(1) {
                    let key = key_match.as_str();
                    existing_keys.insert(key.to_string());

                    if let Some(new_value) = new_values.get(key) {
                        // Replace with new value
                        result.push_str(&format!("{}={}\n", key, new_value));
                        updated_count += 1;
                        debug!("Updated existing variable: {}", key);
                        continue;
                    }
                }
            }
            // Keep original line if no replacement needed
            result.push_str(line);
            result.push('\n');
        }

        // Add new keys that don't exist
        let mut added_count = 0;
        let mut new_keys: Vec<&String> = new_values.keys().collect();
        new_keys.sort();

        for key in new_keys {
            if !existing_keys.contains(key) {
                if let Some(value) = new_values.get(key) {
                    result.push_str(&format!("{}={}\n", key, value));
                    added_count += 1;
                    debug!("Added new variable: {}", key);
                }
            }
        }

        Ok((result, updated_count, added_count))
    }
}

impl Default for EnvHandler {
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
    fn test_write_env_file() {
        let handler = EnvHandler::new();
        let temp_file = NamedTempFile::new().unwrap();

        let mut values = HashMap::new();
        values.insert("KEY1".to_string(), "value1".to_string());
        values.insert("KEY2".to_string(), "value2".to_string());

        handler.write_env_file(temp_file.path().to_str().unwrap(), &values).unwrap();

        let content = fs::read_to_string(temp_file.path()).unwrap();
        assert!(content.contains("KEY1=value1"));
        assert!(content.contains("KEY2=value2"));
    }


    #[test]
    fn test_update_env_file() {
        let handler = EnvHandler::new();
        let temp_file = NamedTempFile::new().unwrap();

        // Create initial .env file with comments
        let initial_content = "# Configuration\nEXISTING_KEY=existing_value\nANOTHER_KEY=another_value\n# End\n";
        fs::write(temp_file.path(), initial_content).unwrap();

        let mut new_values = HashMap::new();
        new_values.insert("NEW_KEY".to_string(), "new_value".to_string());
        new_values.insert("EXISTING_KEY".to_string(), "updated_value".to_string());

        handler.update_env_file(temp_file.path().to_str().unwrap(), &new_values).unwrap();

        let content = fs::read_to_string(temp_file.path()).unwrap();

        // Should preserve comments and structure
        assert!(content.contains("# Configuration"));
        assert!(content.contains("# End"));

        // Should update existing values while preserving structure
        assert!(content.contains("EXISTING_KEY=updated_value"));
        assert!(content.contains("ANOTHER_KEY=another_value"));

        // Should add new key at the end
        assert!(content.contains("NEW_KEY=new_value"));
    }
}