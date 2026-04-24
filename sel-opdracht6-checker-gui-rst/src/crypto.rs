use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, KeyIvInit};
use hmac::Hmac;
use sha2::Sha256;
use std::collections::HashMap;

type Aes256CbcDec = cbc::Decryptor<aes::Aes256>;

const SALTED_PREFIX: &[u8] = b"Salted__";
const SALT_LEN: usize = 8;
const KEY_LEN: usize = 32; // 256 bits
const IV_LEN: usize = 16;
const PBKDF2_ITERATIONS: u32 = 10_000;

// embedded encrypted secrets file (copied at build time).
// makes it easier to pass to my fellow students: a single binary and single secret
const ENCRYPTED_SECRETS: &[u8] = include_bytes!("../secrets.env.enc");

#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("Encrypted data too short")]
    DataTooShort,
    #[error("Missing OpenSSL 'Salted__' header")]
    BadHeader,
    #[error("Decryption failed (wrong passphrase?)")]
    DecryptionFailed,
    #[error("Required secret '{0}' missing after decryption")]
    MissingKey(String),
}

pub fn decrypt_secrets(passphrase: &str) -> Result<HashMap<String, String>, CryptoError> {
    let plain = decrypt_bytes(ENCRYPTED_SECRETS, passphrase)?;
    let text = String::from_utf8_lossy(&plain);
    let map = parse_key_values(&text);

    for key in &[
        "SSH_USER",
        "SSH_PASS",
        "MYSQL_REMOTE_USER",
        "MYSQL_REMOTE_PASS",
        "MYSQL_LOCAL_USER",
        "MYSQL_LOCAL_PASS",
        "WP_USER",
        "WP_PASS",
    ] {
        if !map.contains_key(*key) || map[*key].is_empty() {
            return Err(CryptoError::MissingKey(key.to_string()));
        }
    }
    Ok(map)
}


// This needs a closer look, as I don't understand completely: https://docs.rs/pbkdf2/latest/pbkdf2/
// ai generated
/// Decrypt OpenSSL enc -aes-256-cbc -pbkdf2 format.
///
/// Format: "Salted__" (8 bytes) + salt (8 bytes) + ciphertext
/// Key derivation: PBKDF2-HMAC-SHA256, 10000 iterations
/// Output: 48 bytes → first 32 = AES key, next 16 = IV
fn decrypt_bytes(data: &[u8], passphrase: &str) -> Result<Vec<u8>, CryptoError> {
    if data.len() < SALTED_PREFIX.len() + SALT_LEN + 16 {
        return Err(CryptoError::DataTooShort);
    }

    if &data[..SALTED_PREFIX.len()] != SALTED_PREFIX {
        return Err(CryptoError::BadHeader);
    }

    let salt = &data[8..16];
    let ciphertext = &data[16..];

    // Derive key + IV using PBKDF2
    let mut derived = [0u8; KEY_LEN + IV_LEN]; // 48 bytes
    pbkdf2::pbkdf2::<Hmac<Sha256>>(
        passphrase.as_bytes(),
        salt,
        PBKDF2_ITERATIONS,
        &mut derived,
    )
    .map_err(|_| CryptoError::DecryptionFailed)?;

    let key = &derived[..KEY_LEN];
    let iv = &derived[KEY_LEN..KEY_LEN + IV_LEN];

    // Decrypt AES-256-CBC with PKCS7 padding
    let mut buf = ciphertext.to_vec();
    let plaintext = Aes256CbcDec::new(key.into(), iv.into())
        .decrypt_padded_mut::<Pkcs7>(&mut buf)
        .map_err(|_| CryptoError::DecryptionFailed)?;

    dbg!("Decryption successful, plaintext: {}", String::from_utf8_lossy(plaintext));

    Ok(plaintext.to_vec())
}


// could chain this
fn parse_key_values(text: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(eq) = trimmed.find('=') {
            let key = trimmed[..eq].trim().to_string();
            let val = trimmed[eq + 1..].trim().to_string();
            map.insert(key, val);
        }
    }
    map
}
