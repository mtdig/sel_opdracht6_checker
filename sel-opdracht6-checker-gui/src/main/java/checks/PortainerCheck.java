package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.List;

public class PortainerCheck implements Check {

    @Override public String getId() { return "portainer"; }
    @Override public String getName() { return "Portainer reachable via HTTPS (port 9443)"; }
    @Override public String getSection() { return "Portainer"; }
    @Override public String getProtocol() { return "HTTPS"; }
    @Override public String getPort() { return "9443"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(ctx.getPortainerUrl());
            if (resp.statusCode() >= 200 && resp.statusCode() < 400) {
                return List.of(CheckResult.pass("Portainer reachable via HTTPS (HTTP " + resp.statusCode() + ")"));
            }
            return List.of(CheckResult.fail("Portainer not reachable",
                    "HTTP status: " + resp.statusCode()));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail("Portainer not reachable", e.getMessage()));
        }
    }
}
