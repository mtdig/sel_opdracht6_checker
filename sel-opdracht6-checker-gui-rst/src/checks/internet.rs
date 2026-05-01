use crate::checks::SharedSshSession;
use crate::types::*;


pub async fn run(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let ping_target = &config.app.general.internet_ping_target;
    let ssh = {
        let guard = ssh_session.lock().await;
        match guard.as_ref() {
            Some(s) => s.clone(),
            None => {
                return vec![CheckResult::skip(
                    "Internet check",
                    "SSH connection not available",
                )]
            }
        }
    };

    let cmd = format!(
        "ping -c 1 -W 3 {ping_target} >/dev/null 2>&1 && echo INET_OK || echo INET_FAIL"
    );
    match ssh.exec(&cmd).await {
        Ok(out) if out.contains("INET_OK") => {
            vec![CheckResult::pass("VM has internet access").with_cmd(&cmd, &out)]
        }
        Ok(out) => {
            vec![CheckResult::fail(
                "VM has no internet access",
                format!("ping {ping_target} from VM failed"),
            ).with_cmd(&cmd, &out)]
        }
        Err(e) => {
            vec![CheckResult::fail(
                "Internet check failed",
                &e,
            ).with_cmd(&cmd, "")]
        }
    }
}
