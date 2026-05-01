use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let port = config.app.portainer.port;
    let url = format!("https://{}:{port}", config.target);

    let cmd = format!("GET {url}");
    match http_helper::get(&url).await {
        Ok(resp) if resp.status >= 200 && resp.status < 400 => {
            let out = format!("HTTP {}\n{}", resp.status, &resp.body[..resp.body.len().min(500)]);
            vec![CheckResult::pass(format!(
                "Portainer reachable via HTTPS (HTTP {})",
                resp.status
            )).with_cmd(&cmd, &out)]
        }
        Ok(resp) => {
            let out = format!("HTTP {}\n{}", resp.status, &resp.body[..resp.body.len().min(500)]);
            vec![CheckResult::fail(
                "Portainer not reachable",
                format!("HTTP status: {}", resp.status),
            ).with_cmd(&cmd, &out)]
        }
        Err(e) => {
            vec![CheckResult::fail("Portainer not reachable", &e).with_cmd(&cmd, &e)]
        }
    }
}
