package domain;


public class SecretDecryptionException extends RuntimeException {

    public SecretDecryptionException(String message) {
        super(message);
    }

    public SecretDecryptionException(String message, Throwable cause) {
        super(message, cause);
    }
}
