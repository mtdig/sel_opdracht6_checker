package domain;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

import static org.junit.jupiter.api.Assertions.*;

class CheckStatusTest {

    @Test
    void passIsTerminal() {
        assertTrue(CheckStatus.PASS.isTerminal());
    }

    @Test
    void failIsTerminal() {
        assertTrue(CheckStatus.FAIL.isTerminal());
    }

    @Test
    void skipIsTerminal() {
        assertTrue(CheckStatus.SKIP.isTerminal());
    }

    @Test
    void notRunIsNotTerminal() {
        assertFalse(CheckStatus.NOT_RUN.isTerminal());
    }

    @Test
    void runningIsNotTerminal() {
        assertFalse(CheckStatus.RUNNING.isTerminal());
    }

    @ParameterizedTest
    @EnumSource(CheckStatus.class)
    void allValuesHaveNames(CheckStatus status) {
        assertNotNull(status.name());
        assertFalse(status.name().isEmpty());
    }

    @Test
    void enumHasFiveValues() {
        assertEquals(5, CheckStatus.values().length);
    }
}
