use rand::distr::{Alphanumeric, SampleString};
use scrypt::{scrypt, Params};

pub fn hash_password(password: &str) -> String {
    let mut rng = rand::rng();
    let salt = Alphanumeric.sample_string(&mut rng, 16);
    let params = Params::new(15, 8, 1).unwrap(); // 2^15 = 32768, r=8, p=1

    let mut output = [0u8; 64];
    scrypt(password.as_bytes(), salt.as_bytes(), &params, &mut output)
        .expect("scrypt computation failed");

    let hex_hash = hex::encode(output);
    format!("scrypt:32768:8:1${}${}", salt, hex_hash)
}

pub fn verify_password(arg1: &str, arg2: &str) -> bool {
    let a = arg1.trim();
    let b = arg2.trim();

    if a == b {
        tracing::info!("[AUTH] Password matched plain text");
        return true;
    }

    // Determine which argument is the stored hash
    let (stored_hash, password) = if a.starts_with("scrypt:") || a.starts_with("pbkdf2:") {
        (a, b)
    } else if b.starts_with("scrypt:") || b.starts_with("pbkdf2:") {
        (b, a)
    } else {
        (a, b)
    };

    if stored_hash.starts_with("scrypt:") {
        let parts: Vec<&str> = stored_hash.split('$').collect();
        if parts.len() != 3 {
            tracing::warn!("[AUTH] scrypt parts.len() != 3 (got {})", parts.len());
            return false;
        }
        let param_parts: Vec<&str> = parts[0].split(':').collect();
        if param_parts.len() != 4 || param_parts[0] != "scrypt" {
            tracing::warn!("[AUTH] scrypt param_parts invalid: {:?}", param_parts);
            return false;
        }
        let n: u64 = param_parts[1].parse().unwrap_or(32768);
        let r: u32 = param_parts[2].parse().unwrap_or(8);
        let p: u32 = param_parts[3].parse().unwrap_or(1);
        let log_n = (n as f64).log2().round() as u8;

        let params = match Params::new(log_n, r, p) {
            Ok(p) => p,
            Err(e) => {
                tracing::warn!("[AUTH] scrypt Params::new failed: {:?}", e);
                return false;
            }
        };
        let salt = parts[1].as_bytes();
        let expected_hash = parts[2];

        let mut output = [0u8; 64];
        if let Err(e) = scrypt(password.as_bytes(), salt, &params, &mut output) {
            tracing::warn!("[AUTH] scrypt execution failed: {:?}", e);
            return false;
        }
        let calculated = hex::encode(output);
        let matched = calculated.eq_ignore_ascii_case(expected_hash);
        if !matched {
            tracing::warn!("[AUTH] scrypt hash mismatch: calc={}... vs exp={}...", &calculated[..8], &expected_hash[..8]);
        }
        return matched;
    }

    // Fallback for pbkdf2
    if stored_hash.starts_with("pbkdf2:sha256:") {
        let parts: Vec<&str> = stored_hash.split('$').collect();
        if parts.len() != 3 {
            return false;
        }
        let header_parts: Vec<&str> = parts[0].split(':').collect();
        if header_parts.len() != 3 {
            return false;
        }
        let iterations: u32 = header_parts[2].parse().unwrap_or(260000);
        let salt = parts[1].as_bytes();
        let expected_hash = parts[2];

        let mut output = [0u8; 32];
        let _ = pbkdf2::pbkdf2::<hmac::Hmac<sha2::Sha256>>(
            password.as_bytes(),
            salt,
            iterations,
            &mut output,
        );
        let calculated = hex::encode(output);
        return calculated.eq_ignore_ascii_case(expected_hash);
    }

    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_auth_hash_and_verify() {
        let hash = hash_password("admin");
        assert!(verify_password(&hash, "admin"));
        assert!(!verify_password(&hash, "wrong"));
    }

    #[test]
    fn test_verify_known_scrypt() {
        let hash = "scrypt:32768:8:1$hrFLrZNVp6I6lrNW$f343f564502166b0f73bcbdfc9220a7f7eb53862d3e58eeec18a0858b72b9ae4f866ad3b6169517f30e5b8ad7af39dc49fe5620b97feee2eaa6016b561234249";
        assert!(verify_password(hash, "admin"));
    }
}
