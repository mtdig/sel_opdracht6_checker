use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let port = config.app.planka.port;
    let url = format!("http://{}:{port}", config.target);
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
    let test_user = &config.app.planka.test_user;
    let test_pass = &config.app.planka.test_pass;
    let login_url = format!("{url}/api/access-tokens");
    let payload = format!(
        r#"{{"emailOrUsername":"{test_user}","password":"{test_pass}"}}"#
    );

    match http_helper::post(&login_url, "application/json", &payload).await {
        Ok(resp) if resp.body.contains("\"item\"") => {
            results.push(CheckResult::pass(
                format!("Planka login as {test_user}"),
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
