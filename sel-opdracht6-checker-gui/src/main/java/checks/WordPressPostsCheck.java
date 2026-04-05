package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.List;

public class WordPressPostsCheck implements Check {

    @Override public String getId() { return "wp_posts"; }
    @Override public String getName() { return "WordPress at least 3 posts via REST API"; }
    @Override public String getSection() { return "WordPress"; }
    @Override public String getProtocol() { return "HTTP"; }
    @Override public String getPort() { return "8080"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(ctx.getWpUrl() + "/?rest_route=/wp/v2/posts");
            String body = resp.body();
            // Quick count of top-level JSON array items
            long count = body.chars().filter(c -> c == '{').count();
            // More reliable: split on },{
            if (body.startsWith("[")) {
                String[] items = body.split("\\},\\{");
                count = items.length;
            }
            if (count > 2) {
                return List.of(CheckResult.pass("At least 3 posts (" + count + " found)"));
            }
            return List.of(CheckResult.fail("Not enough posts",
                    "Only " + count + " found, at least 3 expected"));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail("WordPress posts retrieval failed", e.getMessage()));
        }
    }
}
