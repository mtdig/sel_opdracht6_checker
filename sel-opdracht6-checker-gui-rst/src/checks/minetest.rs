use crate::checks::SharedSshSession;
use crate::types::*;

/// Check that minetest container runs and port 30000 is exposed
pub async fn run(_config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let ssh = {
        let guard = ssh_session.lock().await;
        match guard.as_ref() {
            Some(s) => s.clone(),
            None => {
                return vec![CheckResult::skip(
                    "Minetest check",
                    "SSH connection not available",
                )]
            }
        }
    };

    let mut results = Vec::new();

    // Check container running
    match ssh.exec("docker ps --format '{{.Names}}' 2>/dev/null").await {
        Ok(out) => {
            if out.lines().any(|l| l.contains("minetest")) {
                results.push(CheckResult::pass("Minetest container is running"));
            } else {
                return vec![CheckResult::fail(
                    "Minetest container not running",
                    format!("Running containers: {}", out.trim()),
                )];
            }
        }
        Err(e) => {
            return vec![CheckResult::fail("Could not list Docker containers", e)];
        }
    }

    // Check port 30000 via ss
    match ssh.exec("ss -uln | grep 30000").await {
        Ok(ss_out) if !ss_out.trim().is_empty() => {
            results.push(CheckResult::pass("Minetest UDP port 30000 is listening"));
        }
        _ => {
            results.push(CheckResult::fail(
                "Minetest port 30000 not listening",
                "UDP port 30000 not found in ss -uln output",
            ));
        }
    }

    results
}
