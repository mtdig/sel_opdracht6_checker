package domain;

import org.apache.sshd.client.SshClient;
import org.apache.sshd.client.channel.ClientChannelEvent;
import org.apache.sshd.client.channel.ChannelExec;
import org.apache.sshd.client.session.ClientSession;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.EnumSet;
import java.util.Map;


public class CheckContext {

    private final String target;
    private final String localUser;
    private final Map<String, String> secrets;

    private SshClient sshClient;
    private ClientSession sshSession;
    private boolean sshOk = false;

    public CheckContext(String target, String localUser, Map<String, String> secrets) {
        this.target = target;
        this.localUser = localUser;
        this.secrets = Map.copyOf(secrets);
    }

    public String getTarget() {
        return target;
    }

    public String getLocalUser() {
        return localUser;
    }

    public String getSecret(String key) {
        return secrets.getOrDefault(key, "");
    }

    public String getSshUser() {
        return getSecret("SSH_USER");
    }

    public String getSshPass() {
        return getSecret("SSH_PASS");
    }

    public String getMysqlRemoteUser() {
        return getSecret("MYSQL_REMOTE_USER");
    }

    public String getMysqlRemotePass() {
        return getSecret("MYSQL_REMOTE_PASS");
    }

    public String getMysqlLocalUser() {
        return getSecret("MYSQL_LOCAL_USER");
    }

    public String getMysqlLocalPass() {
        return getSecret("MYSQL_LOCAL_PASS");
    }

    public String getWpUser() {
        return getSecret("WP_USER");
    }

    public String getWpPass() {
        return getSecret("WP_PASS");
    }

    public String getApacheUrl() {
        return "https://" + target;
    }

    public String getWpUrl() {
        return "http://" + target + ":8080";
    }

    public String getPortainerUrl() {
        return "https://" + target + ":9443";
    }

    public String getVaultwardenUrl() {
        return "https://" + target + ":4123";
    }

    public String getPlankaUrl() {
        return "http://" + target + ":3000";
    }

    public int getMinetestPort() {
        return 30000;
    }


    public boolean isSshOk() {
        return sshOk;
    }

    public ClientSession getSshSession() {
        return sshSession;
    }


    public void establishSsh() {
        try {
            sshClient = SshClient.setUpDefaultClient();
            sshClient.start();
            sshSession = sshClient.connect(getSshUser(), target, 22)
                    .verify(Duration.ofSeconds(10))
                    .getSession();
            sshSession.addPasswordIdentity(getSshPass());
            sshSession.auth().verify(Duration.ofSeconds(10));
            sshOk = true;
        } catch (Exception e) {
            throw new SshException("SSH connection failed: " + e.getMessage(), e);
        }
    }


    public String sshRun(String command) {
        if (sshSession == null) throw new SshException("No SSH session");
        try (ChannelExec channel = sshSession.createExecChannel(command)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            ByteArrayOutputStream err = new ByteArrayOutputStream();
            channel.setOut(out);
            channel.setErr(err);
            channel.open().verify(Duration.ofSeconds(10));
            channel.waitFor(EnumSet.of(ClientChannelEvent.CLOSED), Duration.ofSeconds(30));
            return out.toString(StandardCharsets.UTF_8).trim();
        } catch (Exception e) {
            throw new SshException("SSH command failed: " + e.getMessage(), e);
        }
    }


    public void close() {
        try {
            if (sshSession != null) sshSession.close();
        } catch (java.io.IOException ignored) {
            // session close may fail if connection already dropped
        }
        if (sshClient != null) sshClient.stop();
    }
}
