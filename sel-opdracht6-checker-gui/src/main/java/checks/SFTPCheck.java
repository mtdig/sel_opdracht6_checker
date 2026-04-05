package checks;

import domain.CheckContext;
import domain.CheckException;
import domain.CheckResult;
import org.apache.sshd.sftp.client.SftpClient;
import org.apache.sshd.sftp.client.SftpClientFactory;

import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

public class SFTPCheck extends AbstractSSHDependentCheck {

    @Override public String getId() { return "sftp"; }
    @Override public String getName() { return "SFTP upload + HTTPS roundtrip"; }
    @Override public String getSection() { return "SFTP"; }
    @Override public String getProtocol() { return "SFTP"; }
    @Override public String getPort() { return "22"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> skip = requireSsh(ctx, "SFTP upload");
        if (skip != null) return skip;

        List<CheckResult> results = new ArrayList<>();
        String remotePath = "/var/www/html/opdracht6.html";
        String checkUrl = ctx.getApacheUrl() + "/opdracht6.html";

        String html = """
                <!DOCTYPE html>
                <html>
                    <head><title>Opdracht 6</title></head>
                    <body>
                        <h1>SELab Opdracht 6</h1>
                        <p>Submitted by: %s</p>
                    </body>
                </html>""".formatted(ctx.getLocalUser());

        try {
            SftpClient sftp = SftpClientFactory.instance().createSftpClient(ctx.getSshSession());
            try (OutputStream os = sftp.write(remotePath)) {
                os.write(html.getBytes(StandardCharsets.UTF_8));
            }
            sftp.close();
            results.add(CheckResult.pass("SFTP upload to " + remotePath + " as " + ctx.getSshUser()));

            // chmod 644
            ctx.sshRun("chmod 644 " + remotePath);

            // Fetch via HTTPS
            HttpHelper.HttpResponse resp = HttpHelper.get(checkUrl);
            if (resp.statusCode() >= 200 && resp.statusCode() < 400) {
                results.add(CheckResult.pass("opdracht6.html reachable via HTTPS (HTTP " + resp.statusCode() + ")"));
                if (resp.body().contains(ctx.getLocalUser())) {
                    results.add(CheckResult.pass("Roundtrip OK: '" + ctx.getLocalUser() + "' found in page"));
                } else {
                    results.add(CheckResult.fail(
                            "Roundtrip: '" + ctx.getLocalUser() + "' not found in page",
                            "Expected your username in page content"));
                }
            } else {
                results.add(CheckResult.fail("opdracht6.html not reachable via HTTPS",
                        "HTTP status: " + resp.statusCode()));
            }
        } catch (CheckException | java.io.IOException e) {
            results.add(CheckResult.fail("SFTP upload to " + remotePath, e.getMessage()));
        }
        return results;
    }
}
