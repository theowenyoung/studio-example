// Demo module to show secret masking functionality
use crate::secret_masker::SecretMasker;
use std::collections::HashMap;

pub fn demo_secret_masking() {
    let masker = SecretMasker::new();

    // Simulate some retrieved values
    let mut demo_values = HashMap::new();
    demo_values.insert("DATABASE_PASSWORD".to_string(), "super_secret_db_pass123".to_string());
    demo_values.insert("API_KEY".to_string(), "sk_live_1234567890abcdef".to_string());
    demo_values.insert("JWT_SECRET".to_string(), "jwt_super_secret_key_for_signing".to_string());
    demo_values.insert("DEBUG".to_string(), "false".to_string());
    demo_values.insert("PORT".to_string(), "3000".to_string());
    demo_values.insert("REDIS_HOST".to_string(), "localhost".to_string());

    println!("\n=== Demo: Secret Masking (default behavior) ===");
    let mut sorted_keys: Vec<&String> = demo_values.keys().collect();
    sorted_keys.sort();

    for key in &sorted_keys {
        if let Some(value) = demo_values.get(*key) {
            println!("{}", masker.format_output(key, value, false));
        }
    }

    println!("\n=== Demo: Show Secrets (--show-secrets flag) ===");
    for key in sorted_keys {
        if let Some(value) = demo_values.get(key) {
            println!("{}", masker.format_output(key, value, true));
        }
    }
}