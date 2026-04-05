package domain;

import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.*;

class SecretsDecryptorTest {


    @Test
    void decryptBytes_dataTooShort_throwsException() {
        byte[] tooShort = "short".getBytes(StandardCharsets.US_ASCII);
        assertThrows(SecretDecryptionException.class,
                () -> SecretsDecryptor.decryptBytes(tooShort, "pass"));
    }

    @Test
    void decryptBytes_missingSaltedHeader_throwsException() {
        // 16+ bytes but no "Salted__" prefix
        byte[] noHeader = "NotSalted_______extra_padding_data".getBytes(StandardCharsets.US_ASCII);
        SecretDecryptionException ex = assertThrows(SecretDecryptionException.class,
                () -> SecretsDecryptor.decryptBytes(noHeader, "pass"));
        assertTrue(ex.getMessage().contains("Salted__"));
    }

    @Test
    void decryptBytes_wrongPassphrase_throwsException() {
        // Valid "Salted__" header + 8 bytes salt + some junk ciphertext
        byte[] data = new byte[48];
        System.arraycopy("Salted__".getBytes(StandardCharsets.US_ASCII), 0, data, 0, 8);
        // salt bytes 8-15 (zeros are fine)
        // ciphertext bytes 16-47 (random junk)
        for (int i = 16; i < 48; i++) data[i] = (byte) (i * 7);

        assertThrows(SecretDecryptionException.class,
                () -> SecretsDecryptor.decryptBytes(data, "wrong"));
    }

    @Test
    void decryptBytes_dataTooShortMessage() {
        byte[] data = new byte[5];
        SecretDecryptionException ex = assertThrows(SecretDecryptionException.class,
                () -> SecretsDecryptor.decryptBytes(data, "pass"));
        assertTrue(ex.getMessage().contains("too short"));
    }

    @Test
    void decryptBytes_wrongPassphraseContainsHelpfulMessage() {
        byte[] data = new byte[48];
        System.arraycopy("Salted__".getBytes(StandardCharsets.US_ASCII), 0, data, 0, 8);
        for (int i = 16; i < 48; i++) data[i] = (byte) i;

        SecretDecryptionException ex = assertThrows(SecretDecryptionException.class,
                () -> SecretsDecryptor.decryptBytes(data, "wrong"));
        assertTrue(ex.getMessage().contains("wrong passphrase") || ex.getMessage().contains("Decryption failed"));
    }
}
