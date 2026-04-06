use crate::types::*;

pub async fn run(config: &Config) -> Vec<CheckResult> {
    let target = &config.target;

    // using system ping command — cross-platform: ping is everywhere (except maybe docker slims, etc..)
    // linux requires root for raw sockets, but `ping` binary is usually setuid root, so that works without extra permissions
    let (cmd, args) = if cfg!(windows) {
        ("ping", vec!["-n", "1", "-w", "5000", target.as_str()]) // -c means something else on windows
    } else {
        ("ping", vec!["-c", "1", "-W", "5", target.as_str()])
    };

    match tokio::process::Command::new(cmd)
        .args(&args)
        .output()
        .await
    {
        Ok(output) if output.status.success() => {
            vec![CheckResult::pass(format!(
                "VM is reachable at {target} (ping)"
            ))]
        }
        Ok(_) => {
            vec![CheckResult::fail(
                format!("VM is not reachable at {target}"),
                "Ping failed - 0 packets received",
            )]
        }
        Err(e) => {
            vec![CheckResult::fail(
                format!("VM is not reachable at {target}"),
                format!("Ping error: {e}"),
            )]
        }
    }
}
