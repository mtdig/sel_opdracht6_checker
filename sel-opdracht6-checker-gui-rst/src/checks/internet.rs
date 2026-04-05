use crate::checks::SharedSshSession;
use crate::types::*;

pub async fn run(ssh_session: &SharedSshSession) -> Vec<CheckResult> {
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

    match ssh
        .exec("ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && echo INET_OK || echo INET_FAIL")
        .await
    {
        Ok(out) if out.contains("INET_OK") => {
            vec![CheckResult::pass("VM has internet access")]
        }
        Ok(_) => {
            vec![CheckResult::fail(
                "VM has no internet access",
                "ping 8.8.8.8 from VM failed",
            )]
        }
        Err(e) => {
            vec![CheckResult::fail(
                "Internet check failed",
                e,
            )]
        }
    }
}
