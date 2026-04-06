pub mod http_helper;
pub mod ping;
pub mod ssh;
pub mod apache;
pub mod sftp;
pub mod docker;
pub mod internet;
pub mod mysql;
pub mod portainer;
pub mod vaultwarden;
pub mod planka;
pub mod wordpress;
pub mod minetest;

use crate::types::*;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::Mutex as TokioMutex;

/// Shared SSH session handle used by SSH-dependent checks.
/// The outer Option is None until the SSH check completes.
/// Once set, multiple checks can share the Arc<SshSession> concurrently
/// because `russh::client::Handle` supports multiplexed channels.
pub type SharedSshSession = Arc<TokioMutex<Option<Arc<SshSession>>>>;

/// A live SSH session with helper methods.
pub struct SshSession {
    session: russh::client::Handle<ssh::SshHandler>,
}

impl SshSession {
    /// Execute a command and return stdout as a string.
    pub async fn exec(&self, command: &str) -> Result<String, String> {
        let mut channel = self
            .session
            .channel_open_session()
            .await
            .map_err(|e| format!("Channel open failed: {e}"))?;
        channel
            .exec(true, command)
            .await
            .map_err(|e| format!("Exec failed: {e}"))?;

        let mut stdout = Vec::new();
        loop {
            tokio::select! {
                msg = channel.wait() => {
                    match msg {
                        Some(russh::ChannelMsg::Data { data }) => {
                            stdout.extend_from_slice(&data);
                        }
                        Some(russh::ChannelMsg::Eof) | None => break,
                        _ => {}
                    }
                }
                _ = tokio::time::sleep(std::time::Duration::from_secs(30)) => {
                    return Err("Command timed out".into());
                }
            }
        }

        Ok(String::from_utf8_lossy(&stdout).trim().to_string())
    }
}

/// Run a single check by ID.
pub async fn run_check(
    check_id: CheckId,
    config: &Config,
    ssh_session: &SharedSshSession,
) -> Vec<CheckResult> {
    match check_id {
        CheckId::Ping => ping::run(config).await,
        CheckId::Ssh => ssh::run(config, ssh_session).await,
        CheckId::Apache => apache::run(config).await,
        CheckId::Sftp => sftp::run(config, ssh_session).await,
        CheckId::Docker => docker::run(config, ssh_session).await,
        CheckId::Internet => internet::run(config, ssh_session).await,
        CheckId::MysqlRemote => mysql::run_remote(config, ssh_session).await,
        CheckId::MysqlLocal => mysql::run_local(config, ssh_session).await,
        CheckId::MysqlAdmin => mysql::run_admin(config, ssh_session).await,
        CheckId::Portainer => portainer::run(config).await,
        CheckId::Vaultwarden => vaultwarden::run(config).await,
        CheckId::Planka => planka::run(config).await,
        CheckId::WpReachable => wordpress::run_reachable(config).await,
        CheckId::WpPosts => wordpress::run_posts(config).await,
        CheckId::WpLogin => wordpress::run_login(config).await,
        CheckId::WpDb => wordpress::run_db(config, ssh_session).await,
        CheckId::Minetest => minetest::run(config, ssh_session).await,
    }
}

/// Run all checks with dependency-aware scheduling.
/// Non-SSH-dependent checks run in parallel immediately.
/// SSH check runs first, then SSH-dependent checks run in parallel.
pub fn run_all(
    config: Config,
    states: SharedStates,
    ssh_session: SharedSshSession,
    rt: tokio::runtime::Handle,
) {
    let config = Arc::new(config);

    rt.spawn(async move {
        let total_start = Instant::now();
        let defs = all_checks();

        // Phase 1: Run non-SSH-dependent checks in parallel + SSH check
        let mut handles = Vec::new();

        for def in &defs {
            if def.depends_on_ssh {
                continue; // Phase 2
            }

            let id = def.id;
            let cfg = config.clone();
            let ssh = ssh_session.clone();
            let st = states.clone();

            // Mark as running
            {
                let mut guard = st.lock().unwrap();
                if let Some(s) = guard.iter_mut().find(|s| s.def.id == id) {
                    s.status = CheckStatus::Running;
                    s.results.clear();
                }
            }

            let handle = tokio::spawn(async move {
                let start = Instant::now();
                let results = run_check(id, &cfg, &ssh).await;
                let elapsed = start.elapsed();

                let mut guard = st.lock().unwrap();
                if let Some(s) = guard.iter_mut().find(|s| s.def.id == id) {
                    s.results = results;
                    s.duration = elapsed;
                    s.status = s.derive_overall_status();
                }
            });

            handles.push(handle);
        }

        // Wait for all phase 1 checks (including SSH)
        for h in handles {
            let _ = h.await;
        }

        // Phase 2: Run SSH-dependent checks in parallel
        let mut handles2 = Vec::new();

        for def in &defs {
            if !def.depends_on_ssh {
                continue;
            }

            let id = def.id;
            let cfg = config.clone();
            let ssh = ssh_session.clone();
            let st = states.clone();

            {
                let mut guard = st.lock().unwrap();
                if let Some(s) = guard.iter_mut().find(|s| s.def.id == id) {
                    s.status = CheckStatus::Running;
                    s.results.clear();
                }
            }

            let handle = tokio::spawn(async move {
                let start = Instant::now();
                let results = run_check(id, &cfg, &ssh).await;
                let elapsed = start.elapsed();

                let mut guard = st.lock().unwrap();
                if let Some(s) = guard.iter_mut().find(|s| s.def.id == id) {
                    s.results = results;
                    s.duration = elapsed;
                    s.status = s.derive_overall_status();
                }
            });

            handles2.push(handle);
        }

        for h in handles2 {
            let _ = h.await;
        }

        // Record total duration
        let _total_elapsed = total_start.elapsed();
    });
}

/// Run a single check on a background task.
pub fn run_single(
    check_id: CheckId,
    config: Config,
    states: SharedStates,
    ssh_session: SharedSshSession,
    rt: tokio::runtime::Handle,
) {
    let config = Arc::new(config);

    // Mark as running
    {
        let mut guard = states.lock().unwrap();
        if let Some(s) = guard.iter_mut().find(|s| s.def.id == check_id) {
            s.status = CheckStatus::Running;
            s.results.clear();
            s.duration = std::time::Duration::ZERO;
        }
    }

    rt.spawn(async move {
        let start = Instant::now();
        let results = run_check(check_id, &config, &ssh_session).await;
        let elapsed = start.elapsed();

        let mut guard = states.lock().unwrap();
        if let Some(s) = guard.iter_mut().find(|s| s.def.id == check_id) {
            s.results = results;
            s.duration = elapsed;
            s.status = s.derive_overall_status();
        }
    });
}
