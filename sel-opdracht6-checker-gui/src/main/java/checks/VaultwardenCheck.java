package checks;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public class VaultwardenCheck implements Check {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String EXPECTED_ITEM = "testsecret";
    private static final String EXPECTED_PASS = "Sup3rS3crP@55";

    @Override public String getId() { return "vaultwarden"; }
    @Override public String getName() { return "Vaultwarden reachable via HTTPS (port 4123)"; }
    @Override public String getSection() { return "Vaultwarden"; }
    @Override public String getProtocol() { return "HTTPS"; }
    @Override public String getPort() { return "4123"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> results = new ArrayList<>();
        String url = ctx.getVaultwardenUrl();

        // Reachability
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(url);
            if (resp.statusCode() < 200 || resp.statusCode() >= 400) {
                return List.of(CheckResult.fail("Vaultwarden not reachable",
                        "HTTP status: " + resp.statusCode()));
            }
            results.add(CheckResult.pass("Vaultwarden reachable via HTTPS (HTTP " + resp.statusCode() + ")"));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail("Vaultwarden not reachable", e.getMessage()));
        }

        // Isolated temp dir for bw config
        Path dataDir;
        try {
            dataDir = Files.createTempDirectory("bw-checker-");
        } catch (IOException e) {
            results.add(CheckResult.fail("bw setup failed", e.getMessage()));
            return results;
        }

        try {
            // bw config server
            String cfgResult = bw(dataDir, ctx.getVaultwardenPass(),
                    "config", "server", url);
            if (cfgResult == null) {
                results.add(CheckResult.fail("bw config server failed", "bw exited non-zero"));
                return results;
            }

            // bw login
            String session = bw(dataDir, ctx.getVaultwardenPass(),
                    "login", ctx.getVaultwardenUser(),
                    "--passwordenv", "BW_PASSWORD", "--raw", "--nointeraction");
            if (session == null || session.isBlank()) {
                results.add(CheckResult.fail("Vaultwarden login failed", "Check credentials"));
                return results;
            }
            results.add(CheckResult.pass("Vaultwarden login as " + ctx.getVaultwardenUser()));

            // bw sync
            bw(dataDir, ctx.getVaultwardenPass(), "--session", session, "sync", "--nointeraction");

            // bw get item
            String itemJson = bw(dataDir, ctx.getVaultwardenPass(),
                    "get", "item", EXPECTED_ITEM, "--session", session, "--nointeraction");
            if (itemJson == null || itemJson.isBlank()) {
                results.add(CheckResult.fail(
                        "Item '" + EXPECTED_ITEM + "' not found in Vaultwarden",
                        "Check that the item exists in the vault"));
                return results;
            }
            JsonNode item = MAPPER.readTree(itemJson);
            String password = item.path("login").path("password").asText("");
            if (EXPECTED_PASS.equals(password)) {
                results.add(CheckResult.pass(
                        "Vaultwarden '" + EXPECTED_ITEM + "' password correct (" + EXPECTED_PASS + ")"));
            } else {
                results.add(CheckResult.fail(
                        "Vaultwarden '" + EXPECTED_ITEM + "' password incorrect",
                        "Expected: " + EXPECTED_PASS + ", got: " + password));
            }

            // logout (best-effort)
            bw(dataDir, ctx.getVaultwardenPass(), "logout", "--nointeraction");

        } catch (Exception e) {
            results.add(CheckResult.fail("Vaultwarden bw check failed", e.getMessage()));
        } finally {
            deleteDir(dataDir);
        }

        return results;
    }

    /**
     * Run a bw sub-command with the required env vars.
     * Returns trimmed stdout on success, null on non-zero exit.
     */
    private static String bw(Path dataDir, String bwPassword, String... args) throws IOException, InterruptedException {
        List<String> cmd = new ArrayList<>();
        cmd.add("bw");
        cmd.addAll(List.of(args));
        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.environment().put("BITWARDENCLI_APPDATA_DIR", dataDir.toString());
        pb.environment().put("BW_PASSWORD", bwPassword);
        pb.environment().put("NODE_TLS_REJECT_UNAUTHORIZED", "0");
        pb.redirectErrorStream(true);
        Process proc = pb.start();
        String out = new String(proc.getInputStream().readAllBytes()).trim();
        int exit = proc.waitFor();
        return exit == 0 ? out : null;
    }

    private static void deleteDir(Path dir) {
        try {
            if (dir == null) return;
            try (var walk = Files.walk(dir)) {
                walk.sorted(java.util.Comparator.reverseOrder())
                    .forEach(p -> { try { Files.delete(p); } catch (IOException ignored) {} });
            }
        } catch (IOException ignored) {}
    }
}
