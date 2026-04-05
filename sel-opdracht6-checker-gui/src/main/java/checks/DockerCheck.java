package checks;

import domain.CheckContext;
import domain.CheckResult;
import domain.SshException;

import java.util.ArrayList;
import java.util.List;

public class DockerCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "docker"; }
    @Override public String getName() { return "Docker containers, volumes & compose"; }
    @Override public String getSection() { return "Docker"; }
    @Override public String getProtocol() { return "SSH"; }
    @Override public String getPort() { return "22"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "Docker compose check");
        if (skip != null) return skip;

        List<CheckResult> results = new ArrayList<>();
        try {
            String containers = ctx.sshRun("docker ps --format '{{.Names}}' 2>/dev/null").toLowerCase();

            for (String svc : List.of("vaultwarden", "minetest", "portainer")) {
                if (containers.contains(svc)) {
                    results.add(CheckResult.pass("Container " + svc + " running"));
                } else {
                    results.add(CheckResult.fail("Container " + svc + " not running", ""));
                }
            }
            if (containers.contains("planka")) {
                results.add(CheckResult.pass("Container planka running"));
            } else {
                results.add(CheckResult.fail("Container planka not running", ""));
            }

            // Vaultwarden bind mount
            String vwMount = ctx.sshRun("docker inspect $(docker ps -q --filter name=vaultwarden) --format '{{json .Mounts}}' 2>/dev/null");
            results.add(vwMount.contains("\"Type\":\"bind\"")
                    ? CheckResult.pass("Vaultwarden: local directory (bind mount)")
                    : CheckResult.fail("Vaultwarden: no bind mount for data", ""));

            // Minetest bind mount
            String mtMount = ctx.sshRun("docker inspect $(docker ps -q --filter name=minetest) --format '{{json .Mounts}}' 2>/dev/null");
            results.add(mtMount.contains("\"Type\":\"bind\"")
                    ? CheckResult.pass("Minetest: local directory (bind mount)")
                    : CheckResult.fail("Minetest: no bind mount for data", ""));

            // Portainer volume
            String ptMount = ctx.sshRun("docker inspect $(docker ps -q --filter name=portainer) --format '{{json .Mounts}}' 2>/dev/null");
            results.add(ptMount.contains("\"Type\":\"volume\"")
                    ? CheckResult.pass("Portainer: Docker volume")
                    : CheckResult.fail("Portainer: no Docker volume for data", ""));

            // Planka compose file
            String compose = ctx.sshRun("test -f ~/docker/planka/docker-compose.yml && echo ok || test -f ~/docker/planka/compose.yml && echo ok || echo nok");
            results.add(compose.contains("ok")
                    ? CheckResult.pass("Planka compose in ~/docker/planka/")
                    : CheckResult.fail("No compose in ~/docker/planka/", "Expected docker-compose.yml or compose.yml"));

        } catch (SshException e) {
            return List.of(CheckResult.fail("Docker check failed", e.getMessage()));
        }
        return results;
    }
}
