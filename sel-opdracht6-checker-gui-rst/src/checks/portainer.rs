use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let port = config.app.portainer.port;
    let url = format!("https://{}:{port}", config.target);
    let mut results = Vec::new();

    // Reachability
    let get_cmd = format!("GET {url}");
    match http_helper::get(&url).await {
        Ok(resp) if resp.status >= 200 && resp.status < 400 => {
            let out = format!("HTTP {}", resp.status);
            results.push(CheckResult::pass(format!(
                "Portainer reachable via HTTPS (HTTP {})",
                resp.status
            )).with_cmd(&get_cmd, &out));
        }
        Ok(resp) => {
            let out = format!("HTTP {}", resp.status);
            return vec![CheckResult::fail(
                "Portainer not reachable",
                format!("HTTP status: {}", resp.status),
            ).with_cmd(&get_cmd, &out)];
        }
        Err(e) => {
            return vec![CheckResult::fail("Portainer not reachable", &e).with_cmd(&get_cmd, &e)];
        }
    }

    // Login
    let user = &config.secrets.portainer_user;
    let pass = &config.secrets.portainer_pass;
    let login_url = format!("{url}/api/auth");
    let login_cmd = format!("POST {login_url} (as {user})");
    let payload = format!("{{\"username\":\"{user}\",\"password\":\"{pass}\"}}");
    let token = match http_helper::post(&login_url, "application/json", &payload).await {
        Ok(resp) => {
            let out = format!("HTTP {}", resp.status);
            match serde_json::from_str::<serde_json::Value>(&resp.body)
                .ok()
                .and_then(|v| v["jwt"].as_str().map(|s| s.to_string()))
            {
                Some(token) => {
                    results.push(CheckResult::pass(format!("Portainer login as {user}"))
                        .with_cmd(&login_cmd, &out));
                    token
                }
                None => {
                    results.push(CheckResult::fail(
                        "Portainer login failed",
                        "No JWT in response — check credentials",
                    ).with_cmd(&login_cmd, &out));
                    return results;
                }
            }
        }
        Err(e) => {
            results.push(CheckResult::fail("Portainer login failed", &e).with_cmd(&login_cmd, &e));
            return results;
        }
    };

    // Resolve first endpoint ID dynamically
    let endpoints_url = format!("{url}/api/endpoints");
    let ep_cmd = format!("GET {endpoints_url}");
    let endpoint_id = match http_helper::get_with_auth(&endpoints_url, &token).await {
        Ok(resp) => {
            match serde_json::from_str::<serde_json::Value>(&resp.body)
                .ok()
                .and_then(|v| v.as_array()?.first()?.get("Id")?.as_u64())
            {
                Some(id) => id,
                None => {
                    results.push(CheckResult::fail(
                        "Portainer endpoint not found",
                        "No endpoints available",
                    ).with_cmd(&ep_cmd, &resp.body[..resp.body.len().min(300)]));
                    return results;
                }
            }
        }
        Err(e) => {
            results.push(CheckResult::fail("Portainer endpoints request failed", &e)
                .with_cmd(&ep_cmd, &e));
            return results;
        }
    };

    // Container list
    let containers_url = format!("{url}/api/endpoints/{endpoint_id}/docker/containers/json?all=true");
    let ct_cmd = format!("GET {containers_url}");
    match http_helper::get_with_auth(&containers_url, &token).await {
        Ok(resp) => {
            let json: serde_json::Value = serde_json::from_str(&resp.body).unwrap_or_default();
            let containers = json.as_array().map(|a| a.as_slice()).unwrap_or_default();
            let count = containers.len();
            let names: Vec<String> = containers.iter()
                .filter_map(|c| c["Names"].as_array()?.first()?.as_str())
                .map(|n| n.trim_start_matches('/').to_string())
                .collect();
            let names_str = names.join(", ");
            let out = format!("containers={count}: {names_str}");
            if count > 0 {
                results.push(CheckResult::pass(format!(
                    "Portainer sees {count} container(s): {names_str}"
                )).with_cmd(&ct_cmd, &out));
            } else {
                results.push(CheckResult::fail(
                    "Portainer sees no containers",
                    "Check Docker endpoint configuration",
                ).with_cmd(&ct_cmd, &out));
            }
        }
        Err(e) => {
            results.push(CheckResult::fail("Portainer container list failed", &e)
                .with_cmd(&ct_cmd, &e));
        }
    }

    results
}

