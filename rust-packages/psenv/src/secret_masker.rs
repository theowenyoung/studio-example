use regex::Regex;
use std::collections::HashSet;

pub struct SecretMasker {
    sensitive_patterns: Vec<Regex>,
    sensitive_keywords: HashSet<String>,
}

impl SecretMasker {
    pub fn new() -> Self {
        let mut sensitive_keywords = HashSet::new();

        // Common sensitive keywords
        sensitive_keywords.insert("password".to_lowercase());
        sensitive_keywords.insert("passwd".to_lowercase());
        sensitive_keywords.insert("pwd".to_lowercase());
        sensitive_keywords.insert("secret".to_lowercase());
        sensitive_keywords.insert("key".to_lowercase());
        sensitive_keywords.insert("token".to_lowercase());
        sensitive_keywords.insert("auth".to_lowercase());
        sensitive_keywords.insert("credential".to_lowercase());
        sensitive_keywords.insert("cred".to_lowercase());
        sensitive_keywords.insert("private".to_lowercase());
        sensitive_keywords.insert("secure".to_lowercase());
        sensitive_keywords.insert("salt".to_lowercase());
        sensitive_keywords.insert("hash".to_lowercase());
        sensitive_keywords.insert("signature".to_lowercase());
        sensitive_keywords.insert("cert".to_lowercase());
        sensitive_keywords.insert("certificate".to_lowercase());

        let sensitive_patterns = vec![
            // Patterns for common sensitive environment variable formats
            Regex::new(r"(?i).*(password|passwd|pwd|secret|key|token|auth|credential|cred|private|secure|salt|hash|signature|cert|certificate).*").unwrap(),
            // Specific patterns for common formats
            Regex::new(r"(?i).*_(password|passwd|pwd|secret|key|token|auth|credential|cred|private|secure|salt|hash|signature|cert|certificate)(_.*)?").unwrap(),
            Regex::new(r"(?i)(password|passwd|pwd|secret|key|token|auth|credential|cred|private|secure|salt|hash|signature|cert|certificate)_.*").unwrap(),
        ];

        SecretMasker {
            sensitive_patterns,
            sensitive_keywords,
        }
    }

    pub fn is_sensitive_key(&self, key: &str) -> bool {
        let key_lower = key.to_lowercase();

        // Check if any keyword appears in the key
        for keyword in &self.sensitive_keywords {
            if key_lower.contains(keyword) {
                return true;
            }
        }

        // Check against regex patterns
        for pattern in &self.sensitive_patterns {
            if pattern.is_match(&key_lower) {
                return true;
            }
        }

        false
    }

    pub fn mask_value(&self, value: &str) -> String {
        let char_count = value.chars().count();
        format!("****** ({} chars, hidden)", char_count)
    }

    pub fn format_output(&self, key: &str, value: &str, show_secrets: bool) -> String {
        if show_secrets || !self.is_sensitive_key(key) {
            format!("{}={}", key, value)
        } else {
            let masked_value = self.mask_value(value);
            format!("{}={}", key, masked_value)
        }
    }
}

impl Default for SecretMasker {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sensitive_key_detection() {
        let masker = SecretMasker::new();

        // Should detect as sensitive
        assert!(masker.is_sensitive_key("DATABASE_PASSWORD"));
        assert!(masker.is_sensitive_key("API_KEY"));
        assert!(masker.is_sensitive_key("SECRET_TOKEN"));
        assert!(masker.is_sensitive_key("AUTH_SECRET"));
        assert!(masker.is_sensitive_key("COMMON_POSTGRES_PASSWORD"));
        assert!(masker.is_sensitive_key("JWT_SECRET"));
        assert!(masker.is_sensitive_key("PRIVATE_KEY"));
        assert!(masker.is_sensitive_key("CERT_FILE"));
        assert!(masker.is_sensitive_key("HASH_SALT"));

        // Should NOT detect as sensitive
        assert!(!masker.is_sensitive_key("DATABASE_HOST"));
        assert!(!masker.is_sensitive_key("DEBUG"));
        assert!(!masker.is_sensitive_key("PORT"));
        assert!(!masker.is_sensitive_key("NODE_ENV"));
        assert!(!masker.is_sensitive_key("LOG_LEVEL"));
    }

    #[test]
    fn test_mask_value() {
        let masker = SecretMasker::new();

        assert_eq!(
            masker.mask_value("mysecretpassword"),
            "****** (16 chars, hidden)"
        );
        assert_eq!(
            masker.mask_value("short"),
            "****** (5 chars, hidden)"
        );
        assert_eq!(
            masker.mask_value(""),
            "****** (0 chars, hidden)"
        );
    }

    #[test]
    fn test_format_output() {
        let masker = SecretMasker::new();

        // Non-sensitive key - should show value
        assert_eq!(
            masker.format_output("DEBUG", "true", false),
            "DEBUG=true"
        );

        // Sensitive key with show_secrets=false - should mask
        assert_eq!(
            masker.format_output("API_KEY", "secret123", false),
            "API_KEY=****** (9 chars, hidden)"
        );

        // Sensitive key with show_secrets=true - should show value
        assert_eq!(
            masker.format_output("API_KEY", "secret123", true),
            "API_KEY=secret123"
        );
    }
}