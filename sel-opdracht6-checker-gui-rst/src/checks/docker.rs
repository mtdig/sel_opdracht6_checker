use crate::checks::SharedSshSession;
use crate::types::*;

/// Combined Docker check: containers + mounts + compose
pub async fn run(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let expected_containers = &config.app.docker.expected_containers;
    let shared_compose_path = &config.app.docker.shared_compose_path;
    let planka_compose_path = &config.app.docker.planka_compose_path;
    let ssh = {
        let guard = ssh_session.lock().await;
        match guard.as_ref() {
            Some(s) => s.clone(),
            None => {
                return vec![CheckResult::skip(
                    "Docker check",
                    "SSH connection not available",
                )]
            }
        }
    };

    let mut results = Vec::new();

    // 1. Check expected containers are running
    match ssh.exec("docker ps --format '{{.Names}}' 2>/dev/null").await {
        Ok(out) => {
            let running: Vec<&str> = out.lines().map(|l| l.trim()).collect();
            for name in expected_containers {
                if running.iter().any(|r| r.contains(name)) {
                    results.push(CheckResult::pass(format!("Container '{name}' is running")));
                } else {
                    results.push(CheckResult::fail(
                        format!("Container '{name}' not running"),
                        format!("Running: {}", running.join(", ")),
                    ));
                }
            }
        }
        Err(e) => {
            results.push(CheckResult::fail("Could not list Docker containers", e));
        }
    }

    // 2. Check mounts (bind vs volume)
    match ssh
        .exec("docker inspect --format '{{.Name}} {{range .Mounts}}{{.Type}}:{{.Source}}:{{.Destination}} {{end}}' $(docker ps -q) 2>/dev/null")
        .await
    {
        Ok(out) => {
            for line in out.lines() {
                let line = line.trim();
                if line.is_empty() {
                    continue;
                }
                let parts: Vec<&str> = line.splitn(2, ' ').collect();
                let name = parts[0].trim_start_matches('/');
                let mounts_str = parts.get(1).unwrap_or(&"");

                for mount in mounts_str.split_whitespace() {
                    let segs: Vec<&str> = mount.splitn(3, ':').collect();
                    if segs.len() >= 2 {
                        let mount_type = segs[0];
                        let dest = segs.get(2).unwrap_or(&"?");
                        results.push(CheckResult::pass(format!(
                            "{name}: {mount_type} mount -> {dest}"
                        )));
                    }
                }
            }
        }
        Err(e) => {
            results.push(CheckResult::fail("Could not inspect Docker mounts", e));
        }
    }

    // 3. Check shared compose file (vaultwarden, minetest, portainer)
    let shared_cmd = format!(
        "test -f {shared_compose_path}/docker-compose.yml && echo COMPOSE_OK || test -f {shared_compose_path}/compose.yml && echo COMPOSE_OK || echo COMPOSE_MISSING"
    );
    match ssh.exec(&shared_cmd).await {
        Ok(out) if out.contains("COMPOSE_OK") => {
            results.push(CheckResult::pass(format!("Shared compose in {shared_compose_path}/")));
        }
        Ok(_) => {
            results.push(CheckResult::fail(
                format!("No compose in {shared_compose_path}/"),
                "Expected docker-compose.yml or compose.yml",
            ));
        }
        Err(e) => {
            results.push(CheckResult::fail("Could not check for shared compose file", e));
        }
    }

    // 4. Check planka compose file
    let planka_cmd = format!(
        "test -f {planka_compose_path}/docker-compose.yml && echo COMPOSE_OK || test -f {planka_compose_path}/compose.yml && echo COMPOSE_OK || echo COMPOSE_MISSING"
    );
    match ssh.exec(&planka_cmd).await {
        Ok(out) if out.contains("COMPOSE_OK") => {
            results.push(CheckResult::pass(format!("Planka compose in {planka_compose_path}/")));
        }
        Ok(_) => {
            results.push(CheckResult::fail(
                format!("No compose in {planka_compose_path}/"),
                "Expected docker-compose.yml or compose.yml",
            ));
        }
        Err(e) => {
            results.push(CheckResult::fail("Could not check for Planka compose file", e));
        }
    }

    results
}
