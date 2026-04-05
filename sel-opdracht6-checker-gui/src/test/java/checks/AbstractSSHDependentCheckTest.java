package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.CheckStatus;
import org.junit.jupiter.api.Test;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class AbstractSSHDependentCheckTest {


    private static class TestSSHDependentCheck extends AbstractSSHDependentCheck {
        @Override public String getId() { return "test_ssh_dep"; }
        @Override public String getName() { return "Test SSH Check"; }
        @Override public String getSection() { return "Test"; }
        @Override public String getProtocol() { return "SSH"; }
        @Override public String getPort() { return "22"; }

        @Override
        public List<CheckResult> run(CheckContext ctx) {
            List<CheckResult> skip = requireSsh(ctx, "Test");
            if (skip != null) return skip;
            return List.of(CheckResult.pass("SSH available"));
        }
    }

    private final TestSSHDependentCheck check = new TestSSHDependentCheck();

    @Test
    void dependenciesContainSsh() {
        assertEquals(List.of("ssh"), check.getDependencies());
    }

    @Test
    void requireSshReturnsSkipWhenSshNotOk() {
        CheckContext ctx = new CheckContext("host", "user", Map.of());
        // SSH is not established, so isSshOk() returns false
        List<CheckResult> results = check.run(ctx);
        assertEquals(1, results.size());
        assertEquals(CheckStatus.SKIP, results.get(0).status());
        assertTrue(results.get(0).detail().contains("SSH connection not available"));
    }

    @Test
    void requireSshSkipMessageContainsCheckName() {
        CheckContext ctx = new CheckContext("host", "user", Map.of());
        List<CheckResult> results = check.run(ctx);
        assertTrue(results.get(0).message().contains("Test"));
    }

    @Test
    void implementsCheckInterface() {
        assertInstanceOf(Check.class, check);
    }
}
