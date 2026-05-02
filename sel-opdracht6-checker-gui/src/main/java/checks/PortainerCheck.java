package checks;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import domain.Check;
import domain.CheckContext;
import domain.CheckResult;
import domain.HttpRequestException;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.StreamSupport;

public class PortainerCheck implements Check {

    private static final ObjectMapper MAPPER = new ObjectMapper();

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
            JsonNode loginJson = MAPPER.readTree(loginResp.body());
            token = loginJson.path("jwt").asText("");
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
            JsonNode epJson = MAPPER.readTree(epResp.body());
            if (!epJson.isArray() || epJson.isEmpty()) {
                results.add(CheckResult.fail("Portainer endpoint not found", "No endpoints available"));
                return results;
            }
            endpointId = epJson.get(0).path("Id").asInt(-1);
            if (endpointId < 0) {
                results.add(CheckResult.fail("Portainer endpoint not found", "Could not read endpoint Id"));
                return results;
            }
        } catch (Exception e) {
            results.add(CheckResult.fail("Portainer endpoint lookup failed", e.getMessage()));
            return results;
        }

        // Container list
        try {
            HttpHelper.HttpResponse cResp = HttpHelper.getWithAuth(
                    url + "/api/endpoints/" + endpointId + "/docker/containers/json?all=true", token);
            JsonNode containers = MAPPER.readTree(cResp.body());
            int count = containers.isArray() ? containers.size() : 0;
            if (count > 0) {
                String names = StreamSupport.stream(containers.spliterator(), false)
                        .map(c -> c.path("Names").isArray() && c.path("Names").size() > 0
                                ? c.path("Names").get(0).asText("").replaceFirst("^/", "")
                                : "?")
                        .collect(java.util.stream.Collectors.joining(", "));
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
