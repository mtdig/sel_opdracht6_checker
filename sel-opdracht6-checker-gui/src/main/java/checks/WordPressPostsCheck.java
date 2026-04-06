package checks;

import com.google.gson.JsonArray;
import com.google.gson.JsonParser;
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
            JsonArray posts = JsonParser.parseString(resp.body()).getAsJsonArray();
            int count = posts.size();
            if (count >= 3) {
                return List.of(CheckResult.pass("At least 3 posts (" + count + " found)"));
            }
            return List.of(CheckResult.fail("Not enough posts",
                    "Only " + count + " found, at least 3 expected"));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail("WordPress posts retrieval failed", e.getMessage()));
        } catch (Exception e) {
            return List.of(CheckResult.fail("Could not parse posts response", e.getMessage()));
        }
    }
}
