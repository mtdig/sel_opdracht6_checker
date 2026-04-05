package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.util.List;

public class InternetCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "internet"; }
    @Override public String getName() { return "Internet access from VM (ping 8.8.8.8)"; }
    @Override public String getSection() { return "Network"; }
    @Override public String getProtocol() { return "ICMP"; }
    @Override public String getPort() { return "-"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "Internet check");
        if (skip != null) return skip;

        // shell ping, because Java's built-in ICMP handling is a nightmare and requires admin privileges on the host OS, which we don't have.
        // should work on linux, windows and macos
        try {
            String result = ctx.sshRun("ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && echo ok || echo nok");
            if (result.contains("ok")) {
                return List.of(CheckResult.pass("VM has internet access"));
            }
            return List.of(CheckResult.fail("VM has no internet access",
                    "ping 8.8.8.8 from VM failed"));
        } catch (SshException e) {
            return List.of(CheckResult.fail("Internet check failed", e.getMessage()));
        }
    }
}
