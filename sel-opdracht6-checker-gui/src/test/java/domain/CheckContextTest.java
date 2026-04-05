package domain;

import org.junit.jupiter.api.Test;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class CheckContextTest {

    private CheckContext ctx(String target, Map<String, String> secrets) {
        return new CheckContext(target, "localuser", secrets);
    }

    @Test
    void targetIsStored() {
        CheckContext ctx = ctx("10.0.0.1", Map.of());
        assertEquals("10.0.0.1", ctx.getTarget());
    }

    @Test
    void localUserIsStored() {
        CheckContext ctx = new CheckContext("host", "jeroen", Map.of());
        assertEquals("jeroen", ctx.getLocalUser());
    }

    @Test
    void secretsAreCopied() {
        Map<String, String> original = new java.util.HashMap<>();
        original.put("KEY", "val");
        CheckContext ctx = new CheckContext("host", "user", original);
        original.put("KEY", "modified");
        assertEquals("val", ctx.getSecret("KEY"));
    }

    @Test
    void getSecretReturnsEmptyStringForMissing() {
        CheckContext ctx = ctx("host", Map.of());
        assertEquals("", ctx.getSecret("NONEXISTENT"));
    }

    @Test
    void sshUserFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("SSH_USER", "admin"));
        assertEquals("admin", ctx.getSshUser());
    }

    @Test
    void sshPassFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("SSH_PASS", "secret"));
        assertEquals("secret", ctx.getSshPass());
    }

    @Test
    void mysqlRemoteUserFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("MYSQL_REMOTE_USER", "dbuser"));
        assertEquals("dbuser", ctx.getMysqlRemoteUser());
    }

    @Test
    void mysqlRemotePassFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("MYSQL_REMOTE_PASS", "dbpass"));
        assertEquals("dbpass", ctx.getMysqlRemotePass());
    }

    @Test
    void mysqlLocalUserFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("MYSQL_LOCAL_USER", "root"));
        assertEquals("root", ctx.getMysqlLocalUser());
    }

    @Test
    void mysqlLocalPassFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("MYSQL_LOCAL_PASS", "rootpass"));
        assertEquals("rootpass", ctx.getMysqlLocalPass());
    }

    @Test
    void wpUserFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("WP_USER", "wpuser"));
        assertEquals("wpuser", ctx.getWpUser());
    }

    @Test
    void wpPassFromSecrets() {
        CheckContext ctx = ctx("host", Map.of("WP_PASS", "wppass"));
        assertEquals("wppass", ctx.getWpPass());
    }


    @Test
    void apacheUrlIsHttps() {
        CheckContext ctx = ctx("192.168.1.10", Map.of());
        assertEquals("https://192.168.1.10", ctx.getApacheUrl());
    }

    @Test
    void wpUrlIsHttpPort8080() {
        CheckContext ctx = ctx("myhost", Map.of());
        assertEquals("http://myhost:8080", ctx.getWpUrl());
    }

    @Test
    void portainerUrlIsHttpsPort9443() {
        CheckContext ctx = ctx("myhost", Map.of());
        assertEquals("https://myhost:9443", ctx.getPortainerUrl());
    }

    @Test
    void vaultwardenUrlIsHttpsPort4123() {
        CheckContext ctx = ctx("myhost", Map.of());
        assertEquals("https://myhost:4123", ctx.getVaultwardenUrl());
    }

    @Test
    void plankaUrlIsHttpPort3000() {
        CheckContext ctx = ctx("myhost", Map.of());
        assertEquals("http://myhost:3000", ctx.getPlankaUrl());
    }

    @Test
    void minetestPortIs30000() {
        CheckContext ctx = ctx("host", Map.of());
        assertEquals(30000, ctx.getMinetestPort());
    }


    @Test
    void sshNotOkByDefault() {
        CheckContext ctx = ctx("host", Map.of());
        assertFalse(ctx.isSshOk());
    }

    @Test
    void sshSessionIsNullByDefault() {
        CheckContext ctx = ctx("host", Map.of());
        assertNull(ctx.getSshSession());
    }

    @Test
    void sshRunWithoutSessionThrowsSshException() {
        CheckContext ctx = ctx("host", Map.of());
        SshException ex = assertThrows(SshException.class, () -> ctx.sshRun("echo hi"));
        assertTrue(ex.getMessage().contains("No SSH session"));
    }

    @Test
    void closeWithoutSessionDoesNotThrow() {
        CheckContext ctx = ctx("host", Map.of());
        assertDoesNotThrow(ctx::close);
    }


    @Test
    void allSecretGettersReturnEmptyWhenNoSecrets() {
        CheckContext ctx = ctx("host", Map.of());
        assertEquals("", ctx.getSshUser());
        assertEquals("", ctx.getSshPass());
        assertEquals("", ctx.getMysqlRemoteUser());
        assertEquals("", ctx.getMysqlRemotePass());
        assertEquals("", ctx.getMysqlLocalUser());
        assertEquals("", ctx.getMysqlLocalPass());
        assertEquals("", ctx.getWpUser());
        assertEquals("", ctx.getWpPass());
    }
}
