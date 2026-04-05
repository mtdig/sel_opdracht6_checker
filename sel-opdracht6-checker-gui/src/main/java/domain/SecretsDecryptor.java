package domain;

import javax.crypto.Cipher;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.PBEKeySpec;
import javax.crypto.spec.SecretKeySpec;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * the encrypted file is embedded as a classpath resource (secrets.env.enc).
 */
public final class SecretsDecryptor {

    private static final String RESOURCE_PATH = "/secrets.env.enc";
    private static final String SALTED_PREFIX = "Salted__";
    private static final int SALT_LEN = 8;
    private static final int KEY_LEN = 256;           // bits
    private static final int IV_LEN = 16;             // bytes
    private static final int PBKDF2_ITERATIONS = 10_000;

    private SecretsDecryptor() {}

    /**
     * Ddcrypt the embedded secrets.env.enc with the given passphrase
     * and return the KEY=VALUE pairs as a map.
     *
     * @throws SecretDecryptionException if the passphrase is wrong, data is corrupted,
     *                                   or the resource cannot be read
     */
    public static Map<String, String> decrypt(String passphrase) {
        byte[] encrypted = loadResource();
        byte[] plain = decryptBytes(encrypted, passphrase);
        return parseKeyValues(new String(plain, StandardCharsets.UTF_8));
    }


    public static Map<String, String> decrypt(String passphrase, String... requiredKeys) {
        Map<String, String> map = decrypt(passphrase);
        for (String key : requiredKeys) {
            if (!map.containsKey(key) || map.get(key).isBlank()) {
                throw new SecretDecryptionException("Required secret '" + key + "' missing after decryption");
            }
        }
        return map;
    }


    private static byte[] loadResource() {
        try (InputStream is = SecretsDecryptor.class.getResourceAsStream(RESOURCE_PATH)) {
            if (is == null) {
                throw new SecretDecryptionException("Embedded resource not found: " + RESOURCE_PATH);
            }
            return is.readAllBytes();
        } catch (IOException e) {
            throw new SecretDecryptionException("Failed to read resource: " + e.getMessage(), e);
        }
    }

    static byte[] decryptBytes(byte[] data, String passphrase) {
        if (data.length < SALTED_PREFIX.length() + SALT_LEN) {
            throw new SecretDecryptionException("Encrypted data too short");
        }

        String header = new String(data, 0, SALTED_PREFIX.length(), StandardCharsets.US_ASCII);
        if (!SALTED_PREFIX.equals(header)) {
            throw new SecretDecryptionException("Missing OpenSSL 'Salted__' header");
        }

        byte[] salt = Arrays.copyOfRange(data, 8, 16);
        byte[] ciphertext = Arrays.copyOfRange(data, 16, data.length);

        try {
            PBEKeySpec keySpec = new PBEKeySpec(
                    passphrase.toCharArray(), salt, PBKDF2_ITERATIONS,
                    KEY_LEN + IV_LEN * 8);  // bits
            SecretKeyFactory skf = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256");
            byte[] derived = skf.generateSecret(keySpec).getEncoded();

            byte[] key = Arrays.copyOfRange(derived, 0, KEY_LEN / 8);
            byte[] iv = Arrays.copyOfRange(derived, KEY_LEN / 8, KEY_LEN / 8 + IV_LEN);

            Cipher cipher = Cipher.getInstance("AES/CBC/PKCS5Padding");
            cipher.init(Cipher.DECRYPT_MODE,
                    new SecretKeySpec(key, "AES"),
                    new IvParameterSpec(iv));

            return cipher.doFinal(ciphertext);

        } catch (GeneralSecurityException e) {
            throw new SecretDecryptionException("Decryption failed (wrong passphrase?): " + e.getMessage(), e);
        }
    }

    private static Map<String, String> parseKeyValues(String text) {
        Map<String, String> map = new LinkedHashMap<>();
        for (String line : text.split("\n")) {
            line = line.trim();
            if (line.isEmpty() || line.startsWith("#")) continue;
            int eq = line.indexOf('=');
            if (eq < 0) continue;
            String key = line.substring(0, eq).trim();
            String val = line.substring(eq + 1).trim();
            map.put(key, val);
        }
        return map;
    }
}
