package domain;


public class CheckException extends RuntimeException {

    public CheckException(String message) {
        super(message);
    }

    public CheckException(String message, Throwable cause) {
        super(message, cause);
    }
}
