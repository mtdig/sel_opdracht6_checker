use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let url = format!("https://{}", config.target);
    let cmd = format!("GET {url}");
    let mut results = Vec::new();

    match http_helper::get(&url).await {
        Ok(resp) => {
            let out = format!("HTTP {}\n{}", resp.status, &resp.body[..resp.body.len().min(500)]);
            if resp.status >= 400 {
                return vec![CheckResult::fail(
                    format!("Apache not reachable via HTTPS on {url}"),
                    format!("HTTP status: {}", resp.status),
                ).with_cmd(&cmd, &out)];
            }
            results.push(CheckResult::pass(format!(
                "Apache reachable via HTTPS (HTTP {})",
                resp.status
            )).with_cmd(&cmd, &out));

            let expected = &config.app.apache.expected_text;
            if resp.body.contains(expected.as_str()) {
                results.push(CheckResult::pass("index.html contains expected text").with_cmd(&cmd, &out));
            } else {
                results.push(CheckResult::fail(
                    "index.html does not contain expected text",
                    format!("Expected: '{expected}'"),
                ).with_cmd(&cmd, &out));
            }
        }
        Err(e) => {
            return vec![CheckResult::fail(
                format!("Apache not reachable via HTTPS on {url}"),
                &e,
            ).with_cmd(&cmd, &e)];
        }
    }

    results
}
