package domain;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class ExceptionHierarchyTest {


    @Test
    void checkExceptionIsRuntimeException() {
        assertInstanceOf(RuntimeException.class, new CheckException("msg"));
    }

    @Test
    void checkExceptionMessagePreserved() {
        CheckException e = new CheckException("boom");
        assertEquals("boom", e.getMessage());
    }

    @Test
    void checkExceptionCausePreserved() {
        Throwable cause = new IllegalStateException("root");
        CheckException e = new CheckException("wrapped", cause);
        assertSame(cause, e.getCause());
    }


    @Test
    void sshExceptionExtendsCheckException() {
        assertInstanceOf(CheckException.class, new SshException("msg"));
    }

    @Test
    void sshExceptionIsRuntimeException() {
        assertInstanceOf(RuntimeException.class, new SshException("msg"));
    }

    @Test
    void sshExceptionMessagePreserved() {
        assertEquals("conn fail", new SshException("conn fail").getMessage());
    }

    @Test
    void sshExceptionCausePreserved() {
        Throwable cause = new java.io.IOException("timeout");
        SshException e = new SshException("ssh fail", cause);
        assertSame(cause, e.getCause());
        assertEquals("ssh fail", e.getMessage());
    }


    @Test
    void httpRequestExceptionExtendsCheckException() {
        assertInstanceOf(CheckException.class, new HttpRequestException("msg"));
    }

    @Test
    void httpRequestExceptionIsRuntimeException() {
        assertInstanceOf(RuntimeException.class, new HttpRequestException("msg"));
    }

    @Test
    void httpRequestExceptionMessagePreserved() {
        assertEquals("404", new HttpRequestException("404").getMessage());
    }

    @Test
    void httpRequestExceptionCausePreserved() {
        Throwable cause = new java.net.ConnectException("refused");
        HttpRequestException e = new HttpRequestException("http fail", cause);
        assertSame(cause, e.getCause());
    }


    @Test
    void secretDecryptionExceptionIsRuntimeException() {
        assertInstanceOf(RuntimeException.class, new SecretDecryptionException("msg"));
    }

    @Test
    void secretDecryptionExceptionIsNotCheckException() {
        // SecretDecryptionException extends RuntimeException directly, not CheckException
        Object ex = new SecretDecryptionException("msg");
        assertFalse(ex instanceof CheckException);
    }

    @Test
    void secretDecryptionExceptionMessagePreserved() {
        assertEquals("bad key", new SecretDecryptionException("bad key").getMessage());
    }

    @Test
    void secretDecryptionExceptionCausePreserved() {
        Throwable cause = new javax.crypto.BadPaddingException("padding");
        SecretDecryptionException e = new SecretDecryptionException("decrypt fail", cause);
        assertSame(cause, e.getCause());
    }


    @Test
    void sshExceptionCatchableAsCheckException() {
        try {
            throw new SshException("test");
        } catch (CheckException e) {
            assertEquals("test", e.getMessage());
        }
    }

    @Test
    void httpRequestExceptionCatchableAsCheckException() {
        try {
            throw new HttpRequestException("test");
        } catch (CheckException e) {
            assertEquals("test", e.getMessage());
        }
    }
}
