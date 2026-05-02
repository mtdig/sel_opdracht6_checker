use crate::checks::http_helper;
use crate::types::*;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::process::Command;

async fn bw(
    args: &[&str],
    data_dir: &str,
    bw_pass: Option<&str>,
    session: Option<&str>,
) -> Result<String, String> {
    let mut cmd = Command::new("bw");
    cmd.args(args)
        .env("BITWARDENCLI_APPDATA_DIR", data_dir)
        .env("NODE_TLS_REJECT_UNAUTHORIZED", "0");
    if let Some(p) = bw_pass {
        cmd.env("BW_PASSWORD", p);
    }
    if let Some(s) = session {
        cmd.args(["--session", s]);
    }
    let out = cmd.output().await.map_err(|e| format!("bw exec failed: {e}"))?;
    let stdout = String::from_utf8_lossy(&out.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).trim().to_string();
    if out.status.success() {
        Ok(stdout)
    } else {
        Err(if stderr.is_empty() { stdout } else { stderr })
    }
}

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let port = config.app.vaultwarden.port;
    let url = format!("https://{}:{port}", config.target);
    let mut results = Vec::new();

    // Reachability
    let get_cmd = format!("GET {url}");
    match http_helper::get(&url).await {
        Ok(resp) if resp.status >= 200 && resp.status < 400 => {
            let out = format!("HTTP {}", resp.status);
            results.push(CheckResult::pass(format!(
                "Vaultwarden reachable via HTTPS (HTTP {})",
                resp.status
            )).with_cmd(&get_cmd, &out));
        }
        Ok(resp) => {
            let out = format!("HTTP {}", resp.status);
            return vec![CheckResult::fail(
                "Vaultwarden not reachable",
                format!("HTTP status: {}", resp.status),
            ).with_cmd(&get_cmd, &out)];
        }
        Err(e) => {
            return vec![CheckResult::fail("Vaultwarden not reachable", &e).with_cmd(&get_cmd, &e)];
        }
    }

    let user = config.secrets.vaultwarden_user.clone();
    let pass = config.secrets.vaultwarden_pass.clone();
    let expected_item = config.app.vaultwarden.expected_item.clone();
    let expected_pass = config.app.vaultwarden.expected_pass.clone();

    // Temp dir for bw config isolation
    let ts = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().subsec_nanos();
    let data_dir_path = std::env::temp_dir().join(format!("bw-checker-{ts}"));
    if let Err(e) = std::fs::create_dir_all(&data_dir_path) {
        results.push(CheckResult::fail("Vaultwarden check setup failed", e.to_string()));
        return results;
    }
    let data_dir_str = data_dir_path.to_string_lossy().to_string();

    // Configure server
    let cfg_cmd = format!("bw config server {url}");
    if let Err(e) = bw(&["config", "server", &url], &data_dir_str, None, None).await {
        results.push(CheckResult::fail("bw config server failed", &e).with_cmd(&cfg_cmd, &e));
        return results;
    }

    // Login
    let login_cmd = format!("bw login {user} --passwordenv BW_PASSWORD --raw --nointeraction");
    let session = match bw(
        &["login", &user, "--passwordenv", "BW_PASSWORD", "--raw", "--nointeraction"],
        &data_dir_str,
        Some(&pass),
        None,
    ).await {
        Ok(s) if !s.is_empty() => {
            results.push(CheckResult::pass(format!("Vaultwarden login as {user}"))
                .with_cmd(&login_cmd, "session key obtained"));
            s
        }
        Ok(_) | Err(_) => {
            results.push(CheckResult::fail(
                "Vaultwarden login failed",
                "Check credentials",
            ).with_cmd(&login_cmd, "no session key returned"));
            return results;
        }
    };

    // Sync vault
    let _ = bw(&["sync", "--nointeraction"], &data_dir_str, None, Some(&session)).await;

    // Get item
    let get_item_cmd = format!("bw get item {expected_item} --nointeraction");
    let item_out = match bw(
        &["get", "item", &expected_item, "--nointeraction"],
        &data_dir_str,
        None,
        Some(&session),
    ).await {
        Ok(json) => json,
        Err(e) => {
            results.push(CheckResult::fail(
                format!("Item '{expected_item}' not found in Vaultwarden"),
                "Check that the item exists in the vault",
            ).with_cmd(&get_item_cmd, &e));
            let _ = bw(&["logout", "--nointeraction"], &data_dir_str, None, None).await;
            return results;
        }
    };

    // Logout (best effort)
    let _ = bw(&["logout", "--nointeraction"], &data_dir_str, None, None).await;

    let secret_password = serde_json::from_str::<serde_json::Value>(&item_out)
        .ok()
        .and_then(|v| v["login"]["password"].as_str().map(|s| s.to_string()))
        .unwrap_or_default();

    if secret_password.is_empty() {
        results.push(CheckResult::fail(
            format!("Password for '{expected_item}' not found in Vaultwarden"),
            "Check that the item has a login password set",
        ).with_cmd(&get_item_cmd, &item_out[..item_out.len().min(300)]));
    } else if secret_password == expected_pass {
        results.push(CheckResult::pass(format!(
            "Vaultwarden '{expected_item}' password correct ({expected_pass})"
        )).with_cmd(&get_item_cmd, &format!("password={secret_password}")));
    } else {
        results.push(CheckResult::fail(
            format!("Vaultwarden '{expected_item}' password incorrect"),
            format!("Expected: {expected_pass}, got: {secret_password}"),
        ).with_cmd(&get_item_cmd, &format!("password={secret_password}")));
    }

    results
}

