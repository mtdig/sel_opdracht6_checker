use crate::checks::{SharedSshSession, SshSession};
use crate::types::*;
use russh::*;
use std::sync::Arc;

/// russh client handler — accepts any host key (like StrictHostKeyChecking=no).
pub struct SshHandler;

#[async_trait::async_trait]
impl client::Handler for SshHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &ssh_key::PublicKey,
    ) -> Result<bool, Self::Error> {
        // Accept any host key (equivalent to StrictHostKeyChecking=no)
        Ok(true)
    }
}

pub async fn run(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let user = &config.secrets.ssh_user;
    let pass = &config.secrets.ssh_pass;
    let target = &config.target;

    let ssh_config = client::Config {
        inactivity_timeout: Some(std::time::Duration::from_secs(15)),
        ..Default::default()
    };

    // Connect
    let mut session = match tokio::time::timeout(
        std::time::Duration::from_secs(10),
        client::connect(Arc::new(ssh_config), (target.as_str(), 22), SshHandler),
    )
    .await
    {
        Ok(Ok(session)) => session,
        Ok(Err(e)) => {
            return vec![CheckResult::fail(
                format!("SSH connection as {user} on port 22"),
                format!("Connection failed: {e}"),
            )];
        }
        Err(_) => {
            return vec![CheckResult::fail(
                format!("SSH connection as {user} on port 22"),
                "Connection timed out",
            )];
        }
    };

    // Authenticate
    let auth_ok = match session
        .authenticate_password(user.as_str(), pass.as_str())
        .await
    {
        Ok(ok) => ok,
        Err(e) => {
            return vec![CheckResult::fail(
                format!("SSH connection as {user} on port 22"),
                format!("Auth failed: {e}"),
            )];
        }
    };

    if !auth_ok {
        return vec![CheckResult::fail(
            format!("SSH connection as {user} on port 22"),
            format!("Cannot log in with {user}"),
        )];
    }

    // Store the session for other checks
    let ssh = Arc::new(SshSession { session });

    // Verify with "echo ok"
    match ssh.exec("echo ok").await {
        Ok(out) if out.contains("ok") => {
            // Store session
            *ssh_session.lock().await = Some(ssh);
            vec![CheckResult::pass(format!(
                "SSH connection as {user} on port 22"
            ))]
        }
        Ok(_) => {
            vec![CheckResult::fail(
                format!("SSH connection as {user} on port 22"),
                "Could not verify SSH session",
            )]
        }
        Err(e) => {
            vec![CheckResult::fail(
                format!("SSH connection as {user} on port 22"),
                format!("echo ok failed: {e}"),
            )]
        }
    }
}
