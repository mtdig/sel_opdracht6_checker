use crate::checks::http_helper;
use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let url = format!("https://{}", config.target);
    let mut results = Vec::new();

    match http_helper::get(&url).await {
        Ok(resp) => {
            if resp.status >= 400 {
                return vec![CheckResult::fail(
                    format!("Apache not reachable via HTTPS on {url}"),
                    format!("HTTP status: {}", resp.status),
                )];
            }
            results.push(CheckResult::pass(format!(
                "Apache reachable via HTTPS (HTTP {})",
                resp.status
            )));

            let expected =
                "Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!";
            if resp.body.contains(expected) {
                results.push(CheckResult::pass("index.html contains expected text"));
            } else {
                results.push(CheckResult::fail(
                    "index.html does not contain expected text",
                    format!("Expected: '{expected}'"),
                ));
            }
        }
        Err(e) => {
            return vec![CheckResult::fail(
                format!("Apache not reachable via HTTPS on {url}"),
                e,
            )];
        }
    }

    results
}
