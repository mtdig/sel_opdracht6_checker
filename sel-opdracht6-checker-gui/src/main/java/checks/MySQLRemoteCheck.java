package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.net.InetSocketAddress;
import java.net.Socket;
import java.util.ArrayList;
import java.util.List;

public class MySQLRemoteCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "mysql_remote"; }
    @Override public String getName() { return "MySQL remote login on port 3306"; }
    @Override public String getSection() { return "MySQL"; }
    @Override public String getProtocol() { return "TCP"; }
    @Override public String getPort() { return "3306"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> results = new ArrayList<>();

        // TCP port check (no SSH needed for this part)
        try (Socket sock = new Socket()) {
            sock.connect(new InetSocketAddress(ctx.getTarget(), 3306), 5000);
            results.add(CheckResult.pass("MySQL reachable on " + ctx.getTarget() + ":3306 as " + ctx.getMysqlRemoteUser()));
        } catch (java.io.IOException e) {
            return List.of(CheckResult.fail(
                    "MySQL not reachable on " + ctx.getTarget() + ":3306",
                    "Check if remote access is enabled"));
        }

        // Database check via SSH
        if (ctx.isSshOk()) {
            try {
                String result = ctx.sshRun(String.format(
                        "mysql -u %s -p'%s' appdb -e 'SELECT 1;' 2>/dev/null",
                        ctx.getMysqlRemoteUser(), ctx.getMysqlRemotePass()));
                if (result.contains("1")) {
                    results.add(CheckResult.pass("Database appdb reachable as " + ctx.getMysqlRemoteUser()));
                } else {
                    results.add(CheckResult.fail(
                            "Database appdb not reachable as " + ctx.getMysqlRemoteUser(),
                            "Check if database appdb exists and user has access"));
                }
            } catch (SshException e) {
                results.add(CheckResult.fail("Database appdb check failed", e.getMessage()));
            }
        } else {
            results.add(CheckResult.skip("Database appdb", "No SSH for login validation"));
        }
        return results;
    }
}
