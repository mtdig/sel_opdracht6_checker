package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.util.List;

public class MinetestCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "minetest"; }
    @Override public String getName() { return "Minetest UDP port 30000 open"; }
    @Override public String getSection() { return "Minetest"; }
    @Override public String getProtocol() { return "UDP"; }
    @Override public String getPort() { return "30000"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "Minetest check");
        if (skip != null) return skip;

        try {
            String out = ctx.sshRun("docker ps --filter name=minetest --format '{{.Ports}}' 2>/dev/null");
            if (out.contains(String.valueOf(ctx.getMinetestPort()))) {
                return List.of(CheckResult.pass("Minetest container running on UDP port " + ctx.getMinetestPort()));
            }
            // Fallback: check if container is running at all
            String names = ctx.sshRun("docker ps --format '{{.Names}}' 2>/dev/null");
            if (names.toLowerCase().contains("minetest")) {
                return List.of(CheckResult.pass("Minetest container running (port not confirmed)"));
            }
            return List.of(CheckResult.fail(
                    "Minetest container not found on UDP port " + ctx.getMinetestPort(),
                    "Check if the Minetest container is running"));
        } catch (SshException e) {
            return List.of(CheckResult.fail("Minetest check failed", e.getMessage()));
        }
    }
}
