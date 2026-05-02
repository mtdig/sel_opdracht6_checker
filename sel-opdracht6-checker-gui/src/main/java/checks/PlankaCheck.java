package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckException;
import domain.CheckResult;

import java.util.ArrayList;
import java.util.List;

public class PlankaCheck implements Check {

    @Override public String getId() { return "planka"; }
    @Override public String getName() { return "Planka reachable + login (port 3000)"; }
    @Override public String getSection() { return "Planka"; }
    @Override public String getProtocol() { return "HTTP"; }
    @Override public String getPort() { return "3000"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> results = new ArrayList<>();
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(ctx.getPlankaUrl());
            if (resp.statusCode() < 200 || resp.statusCode() >= 400) {
                return List.of(CheckResult.fail("Planka not reachable",
                        "HTTP status: " + resp.statusCode()));
            }
            results.add(CheckResult.pass("Planka reachable (HTTP " + resp.statusCode() + ")"));

            // Login
            String plankaUser = ctx.getPlankaUser();
            String payload = "{\"emailOrUsername\":\"" + plankaUser + "\",\"password\":\"" + ctx.getPlankaPass() + "\"}";
            HttpHelper.HttpResponse loginResp = HttpHelper.post(
                    ctx.getPlankaUrl() + "/api/access-tokens", "application/json", payload);
            if (loginResp.body().contains("\"item\"")) {
                results.add(CheckResult.pass("Planka login as " + plankaUser));
            } else {
                results.add(CheckResult.fail("Planka login failed", "Check user/password"));
            }
        } catch (CheckException e) {
            results.add(CheckResult.fail("Planka check failed", e.getMessage()));
        }
        return results;
    }
}
