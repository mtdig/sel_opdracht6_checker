package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.util.List;

public class SSHCheck implements Check {

    @Override public String getId() { return "ssh"; }
    @Override public String getName() { return "SSH connection on port 22"; }
    @Override public String getSection() { return "SSH"; }
    @Override public String getProtocol() { return "TCP/SSH"; }
    @Override public String getPort() { return "22"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        try {
            ctx.establishSsh();
            String out = ctx.sshRun("echo ok");
            if (out.contains("ok")) {
                return List.of(CheckResult.pass(
                        "SSH connection as " + ctx.getSshUser() + " on port 22"));
            }
            return List.of(CheckResult.fail(
                    "SSH connection as " + ctx.getSshUser() + " on port 22",
                    "Could not verify SSH session"));
        } catch (SshException e) {
            return List.of(CheckResult.fail(
                    "SSH connection as " + ctx.getSshUser() + " on port 22",
                    "Cannot log in with " + ctx.getSshUser() + ": " + e.getMessage()));
        }
    }
}
