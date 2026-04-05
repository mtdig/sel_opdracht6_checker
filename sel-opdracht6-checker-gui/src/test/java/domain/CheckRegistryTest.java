package domain;

import org.junit.jupiter.api.Test;

import java.util.HashSet;
import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.*;

class CheckRegistryTest {

    @Test
    void allChecksReturns17Checks() {
        assertEquals(17, CheckRegistry.allChecks().size());
    }

    @Test
    void allIdsAreUnique() {
        List<Check> checks = CheckRegistry.allChecks();
        Set<String> ids = new HashSet<>();
        for (Check c : checks) {
            assertTrue(ids.add(c.getId()), "Duplicate ID: " + c.getId());
        }
    }

    @Test
    void allChecksHaveNonBlankId() {
        for (Check c : CheckRegistry.allChecks()) {
            assertNotNull(c.getId());
            assertFalse(c.getId().isBlank(), "Blank ID found");
        }
    }

    @Test
    void allChecksHaveNonBlankName() {
        for (Check c : CheckRegistry.allChecks()) {
            assertNotNull(c.getName());
            assertFalse(c.getName().isBlank(), "Blank name for " + c.getId());
        }
    }

    @Test
    void allChecksHaveNonBlankSection() {
        for (Check c : CheckRegistry.allChecks()) {
            assertNotNull(c.getSection());
            assertFalse(c.getSection().isBlank(), "Blank section for " + c.getId());
        }
    }

    @Test
    void allChecksHaveNonBlankProtocol() {
        for (Check c : CheckRegistry.allChecks()) {
            assertNotNull(c.getProtocol());
            assertFalse(c.getProtocol().isBlank(), "Blank protocol for " + c.getId());
        }
    }

    @Test
    void allChecksHaveNonBlankPort() {
        for (Check c : CheckRegistry.allChecks()) {
            assertNotNull(c.getPort());
            assertFalse(c.getPort().isBlank(), "Blank port for " + c.getId());
        }
    }

    @Test
    void sshDependentChecksDeclareSshDependency() {
        List<String> sshDependents = List.of(
                "internet", "sftp", "mysql_remote", "mysql_local",
                "mysql_admin", "wp_db", "minetest", "docker");
        List<Check> checks = CheckRegistry.allChecks();
        for (Check c : checks) {
            if (sshDependents.contains(c.getId())) {
                assertTrue(c.getDependencies().contains("ssh"),
                        c.getId() + " should depend on ssh");
            }
        }
    }

    @Test
    void independentChecksHaveNoDependencies() {
        List<String> independent = List.of(
                "ping", "ssh", "apache", "wp_reachable", "wp_posts",
                "wp_login", "portainer", "vaultwarden", "planka");
        List<Check> checks = CheckRegistry.allChecks();
        for (Check c : checks) {
            if (independent.contains(c.getId())) {
                assertTrue(c.getDependencies().isEmpty(),
                        c.getId() + " should have no dependencies");
            }
        }
    }

    @Test
    void knownCheckIdsPresent() {
        Set<String> ids = new HashSet<>();
        CheckRegistry.allChecks().forEach(c -> ids.add(c.getId()));

        for (String expected : List.of("ping", "ssh", "apache", "wp_reachable",
                "wp_posts", "wp_login", "portainer", "vaultwarden", "planka",
                "internet", "sftp", "mysql_remote", "mysql_local",
                "mysql_admin", "wp_db", "minetest", "docker")) {
            assertTrue(ids.contains(expected), "Missing check: " + expected);
        }
    }

    @Test
    void allChecksReturnImmutableList() {
        List<Check> checks = CheckRegistry.allChecks();
        assertThrows(UnsupportedOperationException.class, () ->
                checks.add(null));
    }
}
