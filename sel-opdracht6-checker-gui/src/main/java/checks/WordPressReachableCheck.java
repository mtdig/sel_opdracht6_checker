package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.List;

public class WordPressReachableCheck implements Check {

    @Override public String getId() { return "wp_reachable"; }
    @Override public String getName() { return "WordPress reachable on port 8080"; }
    @Override public String getSection() { return "WordPress"; }
    @Override public String getProtocol() { return "HTTP"; }
    @Override public String getPort() { return "8080"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(ctx.getWpUrl());
            if (resp.statusCode() >= 200 && resp.statusCode() < 400) {
                return List.of(CheckResult.pass(
                        "WordPress reachable on " + ctx.getWpUrl() + " (HTTP " + resp.statusCode() + ")"));
            }
            return List.of(CheckResult.fail(
                    "WordPress not reachable on " + ctx.getWpUrl(),
                    "HTTP status: " + resp.statusCode()));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail(
                    "WordPress not reachable on " + ctx.getWpUrl(),
                    e.getMessage()));
        }
    }
}
