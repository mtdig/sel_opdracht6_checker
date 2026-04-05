use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let url = format!("http://{}:3000", config.target);
    let mut results = Vec::new();

    match http_helper::get(&url).await {
        Ok(resp) => {
            if resp.status >= 400 {
                return vec![CheckResult::fail(
                    "Planka not reachable",
                    format!("HTTP status: {}", resp.status),
                )];
            }
            results.push(CheckResult::pass(format!(
                "Planka reachable (HTTP {})",
                resp.status
            )));
        }
        Err(e) => {
            return vec![CheckResult::fail("Planka not reachable", e)];
        }
    }

    // Login
    let login_url = format!("{url}/api/access-tokens");
    let payload = r#"{"emailOrUsername":"troubleshoot@selab.hogent.be","password":"shoot"}"#;

    match http_helper::post(&login_url, "application/json", payload).await {
        Ok(resp) if resp.body.contains("\"item\"") => {
            results.push(CheckResult::pass(
                "Planka login as troubleshoot@selab.hogent.be",
            ));
        }
        Ok(_) => {
            results.push(CheckResult::fail(
                "Planka login failed",
                "Check user/password",
            ));
        }
        Err(e) => {
            results.push(CheckResult::fail("Planka login failed", e));
        }
    }

    results
}
