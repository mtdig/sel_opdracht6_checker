package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.ArrayList;
import java.util.List;

public class ApacheCheck implements Check {

    @Override public String getId() { return "apache"; }
    @Override public String getName() { return "Apache HTTPS + index.html content"; }
    @Override public String getSection() { return "Apache"; }
    @Override public String getProtocol() { return "HTTPS"; }
    @Override public String getPort() { return "443"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> results = new ArrayList<>();
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(ctx.getApacheUrl());
            if (resp.statusCode() < 200 || resp.statusCode() >= 400) {
                return List.of(CheckResult.fail(
                        "Apache not reachable via HTTPS on " + ctx.getApacheUrl(),
                        "HTTP status: " + resp.statusCode()));
            }
            results.add(CheckResult.pass("Apache reachable via HTTPS (HTTP " + resp.statusCode() + ")"));

            String expected = "Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!";
            if (resp.body().contains(expected)) {
                results.add(CheckResult.pass("index.html contains expected text"));
            } else {
                results.add(CheckResult.fail("index.html does not contain expected text",
                        "Expected: '" + expected + "'"));
            }
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail(
                    "Apache not reachable via HTTPS on " + ctx.getApacheUrl(),
                    e.getMessage()));
        }
        return results;
    }
}
