use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let port = config.app.planka.port;
    let url = format!("http://{}:{port}", config.target);
    let mut results = Vec::new();

    let get_cmd = format!("GET {url}");
    match http_helper::get(&url).await {
        Ok(resp) => {
            let out = format!("HTTP {}\n{}", resp.status, &resp.body[..resp.body.len().min(500)]);
            if resp.status >= 400 {
                return vec![CheckResult::fail(
                    "Planka not reachable",
                    format!("HTTP status: {}", resp.status),
                ).with_cmd(&get_cmd, &out)];
            }
            results.push(CheckResult::pass(format!(
                "Planka reachable (HTTP {})",
                resp.status
            )).with_cmd(&get_cmd, &out));
        }
        Err(e) => {
            return vec![CheckResult::fail("Planka not reachable", &e).with_cmd(&get_cmd, &e)];
        }
    }

    // Login
    let test_user = &config.secrets.planka_user;
    let test_pass = &config.secrets.planka_pass;
    let login_url = format!("{url}/api/access-tokens");
    let post_cmd = format!("POST {login_url} (as {test_user})");
    let payload = format!(
        r#"{{"emailOrUsername":"{test_user}","password":"{test_pass}"}}"#
    );

    match http_helper::post(&login_url, "application/json", &payload).await {
        Ok(resp) if resp.body.contains("\"item\"") => {
            let out = format!("HTTP {}\n{}", resp.status, &resp.body[..resp.body.len().min(500)]);
            results.push(CheckResult::pass(
                format!("Planka login as {test_user}"),
            ).with_cmd(&post_cmd, &out));
        }
        Ok(resp) => {
            let out = format!("HTTP {}\n{}", resp.status, &resp.body[..resp.body.len().min(500)]);
            results.push(CheckResult::fail(
                "Planka login failed",
                "Check user/password",
            ).with_cmd(&post_cmd, &out));
        }
        Err(e) => {
            results.push(CheckResult::fail("Planka login failed", &e).with_cmd(&post_cmd, &e));
        }
    }

    results
}
