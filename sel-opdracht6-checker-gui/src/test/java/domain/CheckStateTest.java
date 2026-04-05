package domain;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class CheckStateTest {

    private CheckState state;

    @BeforeEach
    void setUp() {
        Check stubCheck = new Check() {
            @Override public String getId() { return "test"; }
            @Override public String getName() { return "Test Check"; }
            @Override public String getSection() { return "Testing"; }
            @Override public String getProtocol() { return "TCP"; }
            @Override public String getPort() { return "1234"; }
            @Override public List<CheckResult> run(CheckContext ctx) { return List.of(); }
        };
        state = new CheckState(stubCheck);
    }

    @Test
    void initialStatusIsNotRun() {
        assertEquals(CheckStatus.NOT_RUN, state.getStatus());
    }

    @Test
    void initialDurationIsZero() {
        assertEquals(Duration.ZERO, state.getDuration());
    }

    @Test
    void initialResultsAreEmpty() {
        assertTrue(state.getResults().isEmpty());
    }

    @Test
    void delegatesIdToCheck() {
        assertEquals("test", state.getId());
    }

    @Test
    void delegatesNameToCheck() {
        assertEquals("Test Check", state.getName());
    }

    @Test
    void delegatesSectionToCheck() {
        assertEquals("Testing", state.getSection());
    }

    @Test
    void delegatesProtocolToCheck() {
        assertEquals("TCP", state.getProtocol());
    }

    @Test
    void delegatesPortToCheck() {
        assertEquals("1234", state.getPort());
    }

    @Test
    void setStatusUpdatesStatus() {
        state.setStatus(CheckStatus.RUNNING);
        assertEquals(CheckStatus.RUNNING, state.getStatus());
    }

    @Test
    void setDurationUpdatesDuration() {
        state.setDuration(Duration.ofMillis(500));
        assertEquals(Duration.ofMillis(500), state.getDuration());
    }

    @Test
    void setResultsReplacesResults() {
        state.setResults(List.of(CheckResult.pass("a"), CheckResult.pass("b")));
        assertEquals(2, state.getResults().size());
    }

    @Test
    void resultsAreDefensiveCopy() {
        state.setResults(List.of(CheckResult.pass("a")));
        assertThrows(UnsupportedOperationException.class, () ->
                state.getResults().add(CheckResult.pass("b")));
    }


    @Test
    void deriveOverallStatus_emptyResults_returnsNotRun() {
        assertEquals(CheckStatus.NOT_RUN, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_allPass_returnsPass() {
        state.setResults(List.of(
                CheckResult.pass("a"),
                CheckResult.pass("b")));
        assertEquals(CheckStatus.PASS, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_oneFail_returnsFail() {
        state.setResults(List.of(
                CheckResult.pass("a"),
                CheckResult.fail("b", "detail")));
        assertEquals(CheckStatus.FAIL, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_allSkip_returnsSkip() {
        state.setResults(List.of(
                CheckResult.skip("a", "reason"),
                CheckResult.skip("b", "reason")));
        assertEquals(CheckStatus.SKIP, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_mixPassAndSkip_returnsPass() {
        state.setResults(List.of(
                CheckResult.pass("a"),
                CheckResult.skip("b", "reason")));
        assertEquals(CheckStatus.PASS, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_failTakesPrecedenceOverSkip() {
        state.setResults(List.of(
                CheckResult.skip("a", "reason"),
                CheckResult.fail("b", "detail")));
        assertEquals(CheckStatus.FAIL, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_singlePass() {
        state.setResults(List.of(CheckResult.pass("only one")));
        assertEquals(CheckStatus.PASS, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_singleFail() {
        state.setResults(List.of(CheckResult.fail("only one", "detail")));
        assertEquals(CheckStatus.FAIL, state.deriveOverallStatus());
    }

    @Test
    void deriveOverallStatus_singleSkip() {
        state.setResults(List.of(CheckResult.skip("only one", "reason")));
        assertEquals(CheckStatus.SKIP, state.deriveOverallStatus());
    }
}
