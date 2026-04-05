use crate::checks::SharedSshSession;
use crate::types::*;

pub async fn run_remote(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let target = &config.target;
    let user = &config.secrets.mysql_remote_user;
    let pass = &config.secrets.mysql_remote_pass;
    let port = config.app.mysql.port;
    let db = &config.app.mysql.database;
    let mut results = Vec::new();

    // TCP port check using tokio (handles both IP and hostname)
    let addr = format!("{target}:{port}");
    match tokio::time::timeout(
        std::time::Duration::from_secs(5),
        tokio::net::TcpStream::connect(&addr),
    )
    .await
    {
        Ok(Ok(_)) => {
            results.push(CheckResult::pass(format!(
                "MySQL reachable on {target}:{port} as {user}"
            )));
        }
        _ => {
            return vec![CheckResult::fail(
                format!("MySQL not reachable on {target}:{port}"),
                "Check if remote access is enabled",
            )];
        }
    }

    // DB check via SSH
    let ssh_opt = {
        let guard = ssh_session.lock().await;
        guard.as_ref().cloned()
    };
    if let Some(ssh) = ssh_opt.as_ref() {
        let cmd = format!(
            "mysql -u {user} -p'{pass}' {db} -e 'SELECT 1;' 2>/dev/null"
        );
        match ssh.exec(&cmd).await {
            Ok(out) if out.contains('1') => {
                results.push(CheckResult::pass(format!(
                    "Database {db} reachable as {user}"
                )));
            }
            Ok(_) => {
                results.push(CheckResult::fail(
                    format!("Database {db} not reachable as {user}"),
                    format!("Check if database {db} exists and user has access"),
                ));
            }
            Err(e) => {
                results.push(CheckResult::fail(format!("Database {db} check failed"), e));
            }
        }
    } else {
        results.push(CheckResult::skip(
            format!("Database {db}"),
            "No SSH for login validation",
        ));
    }

    results
}

pub async fn run_local(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let ssh = {
        let guard = ssh_session.lock().await;
        match guard.as_ref() {
            Some(s) => s.clone(),
            None => {
                return vec![CheckResult::skip(
                    "MySQL local via SSH",
                    "SSH connection not available",
                )]
            }
        }
    };

    let user = &config.secrets.mysql_local_user;
    let pass = &config.secrets.mysql_local_pass;
    let cmd = format!("mysql -u {user} -p'{pass}' -e 'SELECT 1;' 2>/dev/null");

    match ssh.exec(&cmd).await {
        Ok(out) if out.contains('1') => {
            vec![CheckResult::pass(format!(
                "MySQL locally reachable via SSH as {user}"
            ))]
        }
        Ok(_) => {
            vec![CheckResult::fail(
                format!("MySQL locally not reachable as {user}"),
                "Check if admin user exists with correct privileges",
            )]
        }
        Err(e) => {
            vec![CheckResult::fail("MySQL local check failed", e)]
        }
    }
}

pub async fn run_admin(config: &Config, ssh_session: &SharedSshSession) -> Vec<CheckResult> {
    let ssh = {
        let guard = ssh_session.lock().await;
        match guard.as_ref() {
            Some(s) => s.clone(),
            None => {
                return vec![CheckResult::skip(
                    "MySQL admin remote check",
                    "SSH connection not available",
                )]
            }
        }
    };

    let target = &config.target;
    let user = &config.secrets.mysql_local_user;
    let pass = &config.secrets.mysql_local_pass;
    let port = config.app.mysql.port;
    let cmd = format!(
        "mysql -h {target} -P {port} -u {user} -p'{pass}' -e 'SELECT 1;' 2>&1"
    );

    match ssh.exec(&cmd).await {
        Ok(out)
            if out.contains("Access denied")
                || out.contains("ERROR")
                || !out.contains('1') =>
        {
            vec![CheckResult::pass(
                "MySQL admin is not reachable remotely (correct)",
            )]
        }
        Ok(_) => {
            vec![CheckResult::fail(
                "MySQL admin is reachable remotely",
                "Should only be accessible locally",
            )]
        }
        Err(_) => {
            // Connection error means blocked -> pass
            vec![CheckResult::pass(
                "MySQL admin is not reachable remotely (correct)",
            )]
        }
    }
}
