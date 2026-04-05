package domain;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class CheckResultTest {

    @Test
    void passFactoryCreatesPassResult() {
        CheckResult r = CheckResult.pass("All good");
        assertEquals(CheckStatus.PASS, r.status());
        assertEquals("All good", r.message());
        assertEquals("", r.detail());
    }

    @Test
    void failFactoryCreatesFailResult() {
        CheckResult r = CheckResult.fail("Broken", "details here");
        assertEquals(CheckStatus.FAIL, r.status());
        assertEquals("Broken", r.message());
        assertEquals("details here", r.detail());
    }

    @Test
    void skipFactoryCreatesSkipResult() {
        CheckResult r = CheckResult.skip("Skipped check", "no SSH");
        assertEquals(CheckStatus.SKIP, r.status());
        assertEquals("Skipped check", r.message());
        assertEquals("no SSH", r.detail());
    }

    @Test
    void recordEquality() {
        CheckResult a = CheckResult.pass("ok");
        CheckResult b = CheckResult.pass("ok");
        assertEquals(a, b);
        assertEquals(a.hashCode(), b.hashCode());
    }

    @Test
    void recordInequalityDifferentStatus() {
        CheckResult pass = CheckResult.pass("msg");
        CheckResult fail = CheckResult.fail("msg", "");
        assertNotEquals(pass, fail);
    }

    @Test
    void recordInequalityDifferentMessage() {
        CheckResult a = CheckResult.pass("one");
        CheckResult b = CheckResult.pass("two");
        assertNotEquals(a, b);
    }

    @Test
    void toStringContainsFields() {
        CheckResult r = CheckResult.fail("err", "detail");
        String s = r.toString();
        assertTrue(s.contains("FAIL"));
        assertTrue(s.contains("err"));
        assertTrue(s.contains("detail"));
    }
}
