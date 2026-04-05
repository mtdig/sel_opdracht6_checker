package checks;

import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.List;

public class WordPressLoginCheck implements Check {

    @Override public String getId() { return "wp_login"; }
    @Override public String getName() { return "WordPress login via XML-RPC"; }
    @Override public String getSection() { return "WordPress"; }
    @Override public String getProtocol() { return "HTTP"; }
    @Override public String getPort() { return "8080"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        String xml = """
                <?xml version='1.0'?>
                <methodCall>
                  <methodName>wp.getUsersBlogs</methodName>
                  <params>
                    <param><value>%s</value></param>
                    <param><value>%s</value></param>
                  </params>
                </methodCall>""".formatted(ctx.getWpUser(), ctx.getWpPass());
        try {
            HttpHelper.HttpResponse resp = HttpHelper.post(
                    ctx.getWpUrl() + "/xmlrpc.php", "text/xml", xml);
            if (resp.body().contains("blogid")) {
                return List.of(CheckResult.pass("WordPress login as " + ctx.getWpUser()));
            }
            return List.of(CheckResult.fail(
                    "WordPress login as " + ctx.getWpUser() + " failed",
                    "Check user/password or XML-RPC availability"));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail(
                    "WordPress login as " + ctx.getWpUser() + " failed",
                    e.getMessage()));
        }
    }
}
