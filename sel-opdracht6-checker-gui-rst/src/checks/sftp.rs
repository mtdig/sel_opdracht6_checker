use crate::checks::{http_helper, SharedSshSession};
use crate::types::*;

pub async fn run(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let ssh = {
        let guard = ssh_session.lock().await;
        match guard.as_ref() {
            Some(s) => s.clone(),
            None => {
                return vec![CheckResult::skip(
                    "SFTP upload",
                    "SSH connection not available",
                )]
            }
        }
    };

    let mut results = Vec::new();
    let remote_path = &config.app.sftp.remote_path;
    let check_filename = &config.app.sftp.check_filename;
    let user = &config.secrets.ssh_user;
    let local_user = &config.local_user;

    let html = format!(
        r#"<!DOCTYPE html>
<html>
    <head><title>Opdracht 6</title></head>
    <body>
        <h1>SELab Opdracht 6</h1>
        <p>Submitted by: {local_user}</p>
    </body>
</html>"#
    );

    // Upload via SSH cat (SFTP subsystem can be tricky with russh)
    let upload_cmd = format!(
        "cat > {remote_path} << 'HTMLEOF'\n{html}\nHTMLEOF"
    );
    match ssh.exec(&upload_cmd).await {
        Ok(out) => {
            results.push(CheckResult::pass(format!(
                "SFTP upload to {remote_path} as {user}"
            )).with_cmd(&upload_cmd, &out));
        }
        Err(e) => {
            return vec![CheckResult::fail(
                format!("SFTP upload to {remote_path}"),
                format!("Upload failed: {e}"),
            ).with_cmd(&upload_cmd, "")];
        }
    }

    // chmod 644
    let _ = ssh.exec(&format!("chmod 644 {remote_path}")).await;

    // Roundtrip via HTTPS
    let check_url = format!("https://{}/{check_filename}", config.target);
    match http_helper::get(&check_url).await {
        Ok(resp) if resp.status >= 200 && resp.status < 400 => {
            results.push(CheckResult::pass(format!(
                "{check_filename} reachable via HTTPS (HTTP {})",
                resp.status
            )));

            if resp.body.contains(local_user.as_str()) {
                results.push(CheckResult::pass(format!(
                    "Roundtrip OK: '{local_user}' found in page"
                )));
            } else {
                results.push(CheckResult::fail(
                    format!("Roundtrip: '{local_user}' not found in page"),
                    "Expected your username in page content",
                ));
            }
        }
        Ok(resp) => {
            results.push(CheckResult::fail(
                format!("{check_filename} not reachable via HTTPS"),
                format!("HTTP status: {}", resp.status),
            ));
        }
        Err(e) => {
            results.push(CheckResult::fail(
                format!("{check_filename} not reachable via HTTPS"),
                e,
            ));
        }
    }

    results
}
