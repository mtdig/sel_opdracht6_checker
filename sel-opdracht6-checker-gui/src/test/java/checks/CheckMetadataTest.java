package checks;

import domain.Check;
import domain.CheckRegistry;
import domain.CheckResult;
import domain.CheckStatus;
import domain.CheckContext;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.MethodSource;

import java.util.List;
import java.util.Map;
import java.util.stream.Stream;

import static org.junit.jupiter.api.Assertions.*;


class CheckMetadataTest {

    static Stream<Check> allChecks() {
        return CheckRegistry.allChecks().stream();
    }

    @ParameterizedTest
    @MethodSource("allChecks")
    void idIsLowerCaseWithUnderscores(Check check) {
        assertTrue(check.getId().matches("[a-z][a-z0-9_]*"),
                check.getId() + " should be lowercase with underscores");
    }

    @ParameterizedTest
    @MethodSource("allChecks")
    void nameIsNotEmpty(Check check) {
        assertFalse(check.getName().isBlank());
    }

    @ParameterizedTest
    @MethodSource("allChecks")
    void sectionIsNotEmpty(Check check) {
        assertFalse(check.getSection().isBlank());
    }

    @ParameterizedTest
    @MethodSource("allChecks")
    void protocolIsKnownValue(Check check) {
        List<String> known = List.of("ICMP", "TCP/SSH", "HTTPS", "HTTP", "TCP", "UDP", "SFTP", "SSH");
        assertTrue(known.contains(check.getProtocol()),
                check.getId() + " has unknown protocol: " + check.getProtocol());
    }

    @ParameterizedTest
    @MethodSource("allChecks")
    void portIsNonBlank(Check check) {
        assertFalse(check.getPort().isBlank());
    }

    @ParameterizedTest
    @MethodSource("allChecks")
    void dependenciesAreNotNull(Check check) {
        assertNotNull(check.getDependencies());
    }

    @ParameterizedTest
    @MethodSource("allChecks")
    void dependenciesContainOnlyKnownIds(Check check) {
        java.util.Set<String> knownIds = new java.util.HashSet<>();
        CheckRegistry.allChecks().forEach(c -> knownIds.add(c.getId()));

        for (String dep : check.getDependencies()) {
            assertTrue(knownIds.contains(dep),
                    check.getId() + " depends on unknown check: " + dep);
        }
    }


    static Stream<Check> sshDependentChecks() {
        return CheckRegistry.allChecks().stream()
                .filter(c -> c.getDependencies().contains("ssh"))
                // mysql_remote tries TCP socket first, FAILs before the SSH guard
                .filter(c -> !c.getId().equals("mysql_remote"));
    }

    @ParameterizedTest
    @MethodSource("sshDependentChecks")
    void sshDependentChecksSkipWhenNoSsh(Check check) {
        CheckContext ctx = new CheckContext("host", "user", Map.of(
                "SSH_USER", "u", "SSH_PASS", "p",
                "MYSQL_REMOTE_USER", "u", "MYSQL_REMOTE_PASS", "p",
                "MYSQL_LOCAL_USER", "u", "MYSQL_LOCAL_PASS", "p",
                "WP_USER", "u", "WP_PASS", "p"
        ));
        List<CheckResult> results = check.run(ctx);
        assertFalse(results.isEmpty());
        assertEquals(CheckStatus.SKIP, results.get(0).status(),
                check.getId() + " should skip when SSH not available");
    }


    @Test
    void pingCheckIsIcmp() {
        Check ping = findCheck("ping");
        assertEquals("ICMP", ping.getProtocol());
        assertEquals("-", ping.getPort());
        assertEquals("Network", ping.getSection());
    }

    @Test
    void sshCheckIsTcpSsh() {
        Check ssh = findCheck("ssh");
        assertEquals("TCP/SSH", ssh.getProtocol());
        assertEquals("22", ssh.getPort());
        assertEquals("SSH", ssh.getSection());
    }

    @Test
    void apacheCheckIsHttps443() {
        Check apache = findCheck("apache");
        assertEquals("HTTPS", apache.getProtocol());
        assertEquals("443", apache.getPort());
        assertEquals("Apache", apache.getSection());
    }

    @Test
    void portainerCheckIsHttps9443() {
        Check portainer = findCheck("portainer");
        assertEquals("HTTPS", portainer.getProtocol());
        assertEquals("9443", portainer.getPort());
    }

    @Test
    void vaultwardenCheckIsHttps4123() {
        Check vaultwarden = findCheck("vaultwarden");
        assertEquals("HTTPS", vaultwarden.getProtocol());
        assertEquals("4123", vaultwarden.getPort());
    }

    @Test
    void plankaCheckIsHttp3000() {
        Check planka = findCheck("planka");
        assertEquals("HTTP", planka.getProtocol());
        assertEquals("3000", planka.getPort());
    }

    @Test
    void wpReachableCheckIsHttp8080() {
        Check wp = findCheck("wp_reachable");
        assertEquals("HTTP", wp.getProtocol());
        assertEquals("8080", wp.getPort());
    }

    @Test
    void minetestCheckIsUdp30000() {
        Check mt = findCheck("minetest");
        assertEquals("UDP", mt.getProtocol());
        assertEquals("30000", mt.getPort());
    }

    @Test
    void mysqlRemoteIsTcp3306() {
        Check mysql = findCheck("mysql_remote");
        assertEquals("TCP", mysql.getProtocol());
        assertEquals("3306", mysql.getPort());
    }

    private Check findCheck(String id) {
        return CheckRegistry.allChecks().stream()
                .filter(c -> c.getId().equals(id))
                .findFirst()
                .orElseThrow(() -> new AssertionError("Check not found: " + id));
    }
}
