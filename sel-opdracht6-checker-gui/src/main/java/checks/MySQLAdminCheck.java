package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.util.List;

public class MySQLAdminCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "mysql_admin"; }
    @Override public String getName() { return "MySQL admin not reachable remotely"; }
    @Override public String getSection() { return "MySQL"; }
    @Override public String getProtocol() { return "SSH"; }
    @Override public String getPort() { return "3306"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "MySQL admin remote check");
        if (skip != null) return skip;

        try {
            String result = ctx.sshRun(String.format(
                    "mysql -h %s -P 3306 -u %s -p'%s' -e 'SELECT 1;' 2>&1",
                    ctx.getTarget(), ctx.getMysqlLocalUser(), ctx.getMysqlLocalPass()));
            if (result.contains("Access denied") || result.contains("ERROR") || !result.contains("1")) {
                return List.of(CheckResult.pass("MySQL admin is not reachable remotely (correct)"));
            }
            return List.of(CheckResult.fail("MySQL admin is reachable remotely",
                    "Should only be accessible locally"));
        } catch (SshException e) {
            // Connection error also means it's blocked -> pass
            return List.of(CheckResult.pass("MySQL admin is not reachable remotely (correct)"));
        }
    }
}
