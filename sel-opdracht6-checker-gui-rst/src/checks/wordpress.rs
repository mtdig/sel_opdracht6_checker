use crate::checks::http_helper;
use crate::checks::SharedSshSession;
use crate::types::*;

pub async fn run_reachable(config: &Config) -> Vec<CheckResult> {
    let port = config.app.wordpress.port;
    let url = format!("http://{}:{port}", config.target);
    match http_helper::get(&url).await {
        Ok(resp) if resp.status < 400 => {
            vec![CheckResult::pass(format!(
                "WordPress reachable (HTTP {})",
                resp.status
            ))]
        }
        Ok(resp) => {
            vec![CheckResult::fail(
                "WordPress HTTP error",
                format!("HTTP status: {}", resp.status),
            )]
        }
        Err(e) => vec![CheckResult::fail(format!("WordPress not reachable on port {port}"), e)],
    }
}


pub async fn run_posts(config: &Config) -> Vec<CheckResult> {
    let port = config.app.wordpress.port;
    let min_posts = config.app.wordpress.min_posts;

    // using ?rest_route= parameter (works even without pretty permalinks)
    let url = format!("http://{}:{port}/?rest_route=/wp/v2/posts", config.target);
    match http_helper::get(&url).await {
        Ok(resp) if resp.status < 400 => {
            // Parse as JSON array and count
            match serde_json::from_str::<serde_json::Value>(&resp.body) {
                Ok(serde_json::Value::Array(arr)) => {
                    let count = arr.len();
                    if count >= min_posts {
                        vec![CheckResult::pass(format!(
                            "WordPress has {count} posts (>= {min_posts})"
                        ))]
                    } else {
                        vec![CheckResult::fail(
                            "Not enough WordPress posts",
                            format!("Found {count}, need >= {min_posts}"),
                        )]
                    }
                }
                _ => vec![CheckResult::fail(
                    "Could not parse posts response",
                    "Expected JSON array",
                )],
            }
        }
        Ok(resp) => vec![CheckResult::fail(
            "WordPress REST API error",
            format!("HTTP status: {}", resp.status),
        )],
        Err(e) => vec![CheckResult::fail("WordPress REST API not reachable", e)],
    }
}

// WordPress login via XML-RPC -- this should be disabled, but let's go :-)
pub async fn run_login(config: &Config) -> Vec<CheckResult> {
    let port = config.app.wordpress.port;
    let url = format!("http://{}:{port}/xmlrpc.php", config.target);
    let payload = format!(
        r#"<?xml version="1.0"?>
<methodCall>
  <methodName>wp.getUsersBlogs</methodName>
  <params>
    <param><value><string>{}</string></value></param>
    <param><value><string>{}</string></value></param>
  </params>
</methodCall>"#,
        config.secrets.wp_user, config.secrets.wp_pass
    );

    match http_helper::post(&url, "text/xml", &payload).await {
        Ok(resp) if resp.body.contains("blogid") => {
            vec![CheckResult::pass(format!(
                "WordPress login as {}", config.secrets.wp_user
            ))]
        }
        Ok(resp) if resp.body.contains("faultCode") => {
            vec![CheckResult::fail(
                format!("WordPress login as {} failed", config.secrets.wp_user),
                "Check user/password or XML-RPC availability",
            )]
        }
        Ok(resp) => vec![CheckResult::fail(
            format!("WordPress login as {} failed", config.secrets.wp_user),
            format!("HTTP {}: {}", resp.status, &resp.body[..resp.body.len().min(200)]),
        )],
        Err(e) => vec![CheckResult::fail("WordPress XML-RPC not reachable", e)],
    }
}


pub async fn run_db(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let ssh = {
        let guard = ssh_session.lock().await;
        match guard.as_ref() {
            Some(s) => s.clone(),
            None => {
                return vec![CheckResult::skip(
                    "WordPress DB check",
                    "SSH connection not available",
                )]
            }
        }
    };

    let wpdb = &config.app.wordpress.database;
    let cmd = format!(
        "mysql -u {} -p'{}' {wpdb} -e 'SELECT 1;' 2>/dev/null",
        config.secrets.wp_user, config.secrets.wp_pass
    );
    match ssh.exec(&cmd).await {
        Ok(out) => {
            let trimmed = out.trim();
            if trimmed.contains('1') {
                vec![CheckResult::pass(format!("WordPress database {wpdb} reachable via SSH"))
                    .with_cmd(&cmd, &out)]
            } else {
                vec![CheckResult::fail(
                    "WordPress DB query unexpected output",
                    trimmed,
                ).with_cmd(&cmd, &out)]
            }
        }
        Err(e) => vec![CheckResult::fail("WordPress DB check failed", &e).with_cmd(&cmd, "")],
    }
}
