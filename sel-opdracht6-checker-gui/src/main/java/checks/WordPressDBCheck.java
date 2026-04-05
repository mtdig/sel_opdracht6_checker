package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.util.List;

public class WordPressDBCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "wp_db"; }
    @Override public String getName() { return "WordPress database wpdb reachable"; }
    @Override public String getSection() { return "WordPress"; }
    @Override public String getProtocol() { return "SSH"; }
    @Override public String getPort() { return "22"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "WordPress database check");
        if (skip != null) return skip;

        try {
            String result = ctx.sshRun(String.format(
                    "mysql -u %s -p'%s' wpdb -e 'SELECT 1;' 2>/dev/null",
                    ctx.getWpUser(), ctx.getWpPass()));
            if (result.contains("1")) {
                return List.of(CheckResult.pass("Database wpdb exists and is reachable"));
            }
            return List.of(CheckResult.fail("Database wpdb not reachable",
                    "Check if wpdb exists and " + ctx.getWpUser() + " has access"));
        } catch (SshException e) {
            return List.of(CheckResult.fail("WordPress DB check failed", e.getMessage()));
        }
    }
}
