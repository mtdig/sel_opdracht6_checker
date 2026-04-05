use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let url = format!("https://{}:9443", config.target);

    match http_helper::get(&url).await {
        Ok(resp) if resp.status >= 200 && resp.status < 400 => {
            vec![CheckResult::pass(format!(
                "Portainer reachable via HTTPS (HTTP {})",
                resp.status
            ))]
        }
        Ok(resp) => {
            vec![CheckResult::fail(
                "Portainer not reachable",
                format!("HTTP status: {}", resp.status),
            )]
        }
        Err(e) => {
            vec![CheckResult::fail("Portainer not reachable", e)]
        }
    }
}
