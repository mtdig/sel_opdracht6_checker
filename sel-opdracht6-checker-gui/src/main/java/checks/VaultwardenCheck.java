package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.List;

public class VaultwardenCheck implements Check {

    @Override public String getId() { return "vaultwarden"; }
    @Override public String getName() { return "Vaultwarden reachable via HTTPS (port 4123)"; }
    @Override public String getSection() { return "Vaultwarden"; }
    @Override public String getProtocol() { return "HTTPS"; }
    @Override public String getPort() { return "4123"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(ctx.getVaultwardenUrl());
            if (resp.statusCode() >= 200 && resp.statusCode() < 400) {
                return List.of(CheckResult.pass("Vaultwarden reachable via HTTPS (HTTP " + resp.statusCode() + ")"));
            }
            return List.of(CheckResult.fail("Vaultwarden not reachable",
                    "HTTP status: " + resp.statusCode()));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail("Vaultwarden not reachable", e.getMessage()));
        }
    }
}
