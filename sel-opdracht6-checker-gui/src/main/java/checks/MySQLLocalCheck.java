package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.util.List;

public class MySQLLocalCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "mysql_local"; }
    @Override public String getName() { return "MySQL local via SSH"; }
    @Override public String getSection() { return "MySQL"; }
    @Override public String getProtocol() { return "SSH"; }
    @Override public String getPort() { return "22"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "MySQL local via SSH");
        if (skip != null) return skip;

        try {
            String result = ctx.sshRun(String.format(
                    "mysql -u %s -p'%s' -e 'SELECT 1;' 2>/dev/null",
                    ctx.getMysqlLocalUser(), ctx.getMysqlLocalPass()));
            if (result.contains("1")) {
                return List.of(CheckResult.pass("MySQL locally reachable via SSH as " + ctx.getMysqlLocalUser()));
            }
            return List.of(CheckResult.fail(
                    "MySQL locally not reachable as " + ctx.getMysqlLocalUser(),
                    "Check if admin user exists with correct privileges"));
        } catch (SshException e) {
            return List.of(CheckResult.fail("MySQL local check failed", e.getMessage()));
        }
    }
}
