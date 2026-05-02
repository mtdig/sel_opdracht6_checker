package checks;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;
import java.util.stream.StreamSupport;

public class PortainerCheck implements Check {

    @Override public String getId() { return "portainer"; }
    @Override public String getName() { return "Portainer reachable via HTTPS (port 9443)"; }
    @Override public String getSection() { return "Portainer"; }
    @Override public String getProtocol() { return "HTTPS"; }
    @Override public String getPort() { return "9443"; }

    @Override
    public List<CheckResult> run(CheckContext ctx) {
        List<CheckResult> results = new ArrayList<>();
        String url = ctx.getPortainerUrl();

        // Reachability
        try {
            HttpHelper.HttpResponse resp = HttpHelper.get(url);
            if (resp.statusCode() < 200 || resp.statusCode() >= 400) {
                return List.of(CheckResult.fail("Portainer not reachable",
                        "HTTP status: " + resp.statusCode()));
            }
            results.add(CheckResult.pass("Portainer reachable via HTTPS (HTTP " + resp.statusCode() + ")"));
        } catch (HttpRequestException e) {
            return List.of(CheckResult.fail("Portainer not reachable", e.getMessage()));
        }

        // Login
        String loginPayload = "{\"username\":\"" + ctx.getPortainerUser() +
                "\",\"password\":\"" + ctx.getPortainerPass() + "\"}";
        String token;
        try {
            HttpHelper.HttpResponse loginResp = HttpHelper.post(
                    url + "/api/auth", "application/json", loginPayload);
            JsonObject loginJson = JsonParser.parseString(loginResp.body()).getAsJsonObject();
            token = loginJson.has("jwt") ? loginJson.get("jwt").getAsString() : "";
            if (token.isEmpty()) {
                results.add(CheckResult.fail("Portainer login failed", "No JWT returned — check credentials"));
                return results;
            }
            results.add(CheckResult.pass("Portainer login as " + ctx.getPortainerUser()));
        } catch (Exception e) {
            results.add(CheckResult.fail("Portainer login failed", e.getMessage()));
            return results;
        }

        // Resolve endpoint ID dynamically
        int endpointId;
        try {
            HttpHelper.HttpResponse epResp = HttpHelper.getWithAuth(url + "/api/endpoints", token);
            JsonArray epJson = JsonParser.parseString(epResp.body()).getAsJsonArray();
            if (epJson.isEmpty()) {
                results.add(CheckResult.fail("Portainer endpoint not found", "No endpoints available"));
                return results;
            }
            endpointId = epJson.get(0).getAsJsonObject().get("Id").getAsInt();
        } catch (Exception e) {
            results.add(CheckResult.fail("Portainer endpoint lookup failed", e.getMessage()));
            return results;
        }

        // Container list
        try {
            HttpHelper.HttpResponse cResp = HttpHelper.getWithAuth(
                    url + "/api/endpoints/" + endpointId + "/docker/containers/json?all=true", token);
            JsonArray containers = JsonParser.parseString(cResp.body()).getAsJsonArray();
            int count = containers.size();
            if (count > 0) {
                String names = StreamSupport.stream(containers.spliterator(), false)
                        .map(c -> {
                            JsonArray nameArr = c.getAsJsonObject().getAsJsonArray("Names");
                            if (nameArr != null && nameArr.size() > 0) {
                                return nameArr.get(0).getAsString().replaceFirst("^/", "");
                            }
                            return "?";
                        })
                        .collect(Collectors.joining(", "));
                results.add(CheckResult.pass("Portainer sees " + count + " container(s): " + names));
            } else {
                results.add(CheckResult.fail("Portainer sees no containers",
                        "Check Docker endpoint configuration"));
            }
        } catch (Exception e) {
            results.add(CheckResult.fail("Portainer container list failed", e.getMessage()));
        }

        return results;
    }
}
