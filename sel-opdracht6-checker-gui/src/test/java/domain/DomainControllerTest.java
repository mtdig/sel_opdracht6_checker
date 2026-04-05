package domain;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.*;

class DomainControllerTest {

    private DomainController dc;

    @BeforeEach
    void setUp() {
        dc = new DomainController();
    }


    @Test
    void initiallyNotConfigured() {
        assertFalse(dc.isConfigured());
    }

    @Test
    void checkStatesMatchRegistrySize() {
        assertEquals(17, dc.getCheckStates().size());
    }

    @Test
    void checkStatesAreUnmodifiable() {
        assertThrows(UnsupportedOperationException.class, () ->
                dc.getCheckStates().add(null));
    }

    @Test
    void allCheckStatesInitiallyNotRun() {
        for (CheckState cs : dc.getCheckStates()) {
            assertEquals(CheckStatus.NOT_RUN, cs.getStatus());
        }
    }


    @Test
    void configureMarksAsConfigured() {
        dc.configure("host", "user", Map.of());
        assertTrue(dc.isConfigured());
    }


    @Test
    void getCheckStateByIdReturnsCorrect() {
        CheckState cs = dc.getCheckState("ping");
        assertNotNull(cs);
        assertEquals("ping", cs.getId());
    }

    @Test
    void getCheckStateByIdReturnsNullForUnknown() {
        assertNull(dc.getCheckState("nonexistent"));
    }

    @Test
    void getSectionsReturnsDistinctSections() {
        List<String> sections = dc.getSections();
        assertFalse(sections.isEmpty());
        // No duplicates
        assertEquals(sections.size(), sections.stream().distinct().count());
    }

    @Test
    void getSectionsPreservesDefinitionOrder() {
        List<String> sections = dc.getSections();
        // First check is ping (Network), then ssh (SSH), then apache (Apache)
        assertEquals("Network", sections.get(0));
        assertEquals("SSH", sections.get(1));
        assertEquals("Apache", sections.get(2));
    }

    @Test
    void getChecksBySectionReturnsOnlyThatSection() {
        List<CheckState> wpChecks = dc.getChecksBySection("WordPress");
        assertFalse(wpChecks.isEmpty());
        for (CheckState cs : wpChecks) {
            assertEquals("WordPress", cs.getSection());
        }
    }

    @Test
    void getChecksBySectionEmptyForUnknown() {
        assertTrue(dc.getChecksBySection("FakeSection").isEmpty());
    }


    @Test
    void initialCountsAreZero() {
        assertEquals(0, dc.countPassed());
        assertEquals(0, dc.countFailed());
        assertEquals(0, dc.countSkipped());
        assertEquals(0, dc.countTotal());
    }

    @Test
    void countsReflectResults() {
        CheckState cs1 = dc.getCheckState("ping");
        cs1.setResults(List.of(CheckResult.pass("ok"), CheckResult.pass("ok2")));

        CheckState cs2 = dc.getCheckState("ssh");
        cs2.setResults(List.of(CheckResult.fail("nope", "detail")));

        CheckState cs3 = dc.getCheckState("apache");
        cs3.setResults(List.of(CheckResult.skip("skip", "reason")));

        assertEquals(2, dc.countPassed());
        assertEquals(1, dc.countFailed());
        assertEquals(1, dc.countSkipped());
        assertEquals(4, dc.countTotal());
    }


    @Test
    void resetAllClearsEverything() {
        CheckState cs = dc.getCheckState("ping");
        cs.setStatus(CheckStatus.PASS);
        cs.setDuration(Duration.ofMillis(100));
        cs.setResults(List.of(CheckResult.pass("ok")));

        dc.resetAll();

        assertEquals(CheckStatus.NOT_RUN, cs.getStatus());
        assertEquals(Duration.ZERO, cs.getDuration());
        assertTrue(cs.getResults().isEmpty());
        assertEquals(Duration.ZERO, dc.getTotalDuration());
    }


    @Test
    void runAllThrowsWhenNotConfigured() {
        assertThrows(CheckException.class, dc::runAll);
    }

    @Test
    void runSingleThrowsWhenNotConfigured() {
        CheckState cs = dc.getCheckState("ping");
        assertThrows(CheckException.class, () -> dc.runSingle(cs));
    }


    @Test
    void setOnCheckStateChangedIsStored() {
        dc.setOnCheckStateChanged(cs -> {});
        assertNotNull(dc.getOnCheckStateChanged());
    }

    @Test
    void setOnSingleDoneIsStored() {
        dc.setOnSingleDone(cs -> {});
        assertNotNull(dc.getOnSingleDone());
    }

    @Test
    void onCheckStateChangedDefaultNull() {
        assertNull(dc.getOnCheckStateChanged());
    }

    @Test
    void onSingleDoneDefaultNull() {
        assertNull(dc.getOnSingleDone());
    }


    @Test
    void runSingleExecutesCheckAndNotifiesCallbacks() throws InterruptedException {
        // Create a controller with a custom check
        DomainController testDc = new DomainController();
        testDc.configure("localhost", "user", Map.of());

        // Track callbacks
        List<CheckStatus> statusChanges = Collections.synchronizedList(new ArrayList<>());
        CountDownLatch doneLatch = new CountDownLatch(1);
        AtomicReference<CheckState> doneState = new AtomicReference<>();

        testDc.setOnCheckStateChanged(cs ->
                statusChanges.add(cs.getStatus()));
        testDc.setOnSingleDone(cs -> {
            doneState.set(cs);
            doneLatch.countDown();
        });

        // Run ping check (will fail since localhost won't respond as expected but it will complete)
        CheckState pingState = testDc.getCheckState("ping");
        testDc.runSingle(pingState);

        // Wait for completion
        assertTrue(doneLatch.await(15, TimeUnit.SECONDS), "runSingle should complete within 15s");
        assertNotNull(doneState.get());
        assertTrue(doneState.get().getStatus().isTerminal());
        assertFalse(doneState.get().getResults().isEmpty());
    }


    @Test
    void totalDurationInitiallyZero() {
        assertEquals(Duration.ZERO, dc.getTotalDuration());
    }
}
