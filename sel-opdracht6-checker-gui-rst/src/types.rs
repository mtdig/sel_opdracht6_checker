use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CheckStatus {
    NotRun,
    Running,
    Pass,
    Fail,
    Skip,
}

impl CheckStatus {
    pub fn label(&self) -> &'static str {
        match self {
            CheckStatus::NotRun => "NOT RUN",
            CheckStatus::Running => "RUNNING",
            CheckStatus::Pass => "PASS",
            CheckStatus::Fail => "FAIL",
            CheckStatus::Skip => "SKIP",
        }
    }

    pub fn is_terminal(&self) -> bool {
        matches!(self, CheckStatus::Pass | CheckStatus::Fail | CheckStatus::Skip)
    }
}

#[derive(Debug, Clone)]
pub struct CheckResult {
    pub status: CheckStatus,
    pub message: String,
    pub detail: String,
}

impl CheckResult {
    pub fn pass(msg: impl Into<String>) -> Self {
        Self {
            status: CheckStatus::Pass,
            message: msg.into(),
            detail: String::new(),
        }
    }

    pub fn fail(msg: impl Into<String>, detail: impl Into<String>) -> Self {
        Self {
            status: CheckStatus::Fail,
            message: msg.into(),
            detail: detail.into(),
        }
    }

    pub fn skip(msg: impl Into<String>, reason: impl Into<String>) -> Self {
        Self {
            status: CheckStatus::Skip,
            message: msg.into(),
            detail: reason.into(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Section {
    Network,
    Ssh,
    Apache,
    Sftp,
    Mysql,
    Portainer,
    Vaultwarden,
    Planka,
    WordPress,
    Docker,
    Minetest,
}

impl Section {
    pub fn label(&self) -> &'static str {
        match self {
            Section::Network => "Network",
            Section::Ssh => "SSH",
            Section::Apache => "Apache",
            Section::Sftp => "SFTP",
            Section::Mysql => "MySQL",
            Section::Portainer => "Portainer",
            Section::Vaultwarden => "Vaultwarden",
            Section::Planka => "Planka",
            Section::WordPress => "WordPress",
            Section::Docker => "Docker",
            Section::Minetest => "Minetest",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CheckId {
    Ping,
    Ssh,
    Apache,
    Sftp,
    Docker,
    Internet,
    MysqlRemote,
    MysqlLocal,
    MysqlAdmin,
    Portainer,
    Vaultwarden,
    Planka,
    WpReachable,
    WpPosts,
    WpLogin,
    WpDb,
    Minetest,
}

#[derive(Debug, Clone)]
pub struct CheckDef {
    pub id: CheckId,
    pub name: &'static str,
    pub section: Section,
    pub protocol: &'static str,
    pub port: &'static str,
    pub depends_on_ssh: bool,
}

pub fn all_checks() -> Vec<CheckDef> {
    vec![
        // No SSH dependency — can run in parallel immediately
        CheckDef { id: CheckId::Ping, name: "VM reachable via ICMP ping", section: Section::Network, protocol: "ICMP", port: "-", depends_on_ssh: false },
        CheckDef { id: CheckId::Ssh, name: "SSH connection on port 22", section: Section::Ssh, protocol: "TCP/SSH", port: "22", depends_on_ssh: false },
        CheckDef { id: CheckId::Apache, name: "Apache HTTPS + index.html content", section: Section::Apache, protocol: "HTTPS", port: "443", depends_on_ssh: false },
        CheckDef { id: CheckId::WpReachable, name: "WordPress reachable on port 8080", section: Section::WordPress, protocol: "HTTP", port: "8080", depends_on_ssh: false },
        CheckDef { id: CheckId::WpPosts, name: "WordPress at least 3 posts via REST API", section: Section::WordPress, protocol: "HTTP", port: "8080", depends_on_ssh: false },
        CheckDef { id: CheckId::WpLogin, name: "WordPress login via XML-RPC", section: Section::WordPress, protocol: "HTTP", port: "8080", depends_on_ssh: false },
        CheckDef { id: CheckId::Portainer, name: "Portainer reachable via HTTPS (port 9443)", section: Section::Portainer, protocol: "HTTPS", port: "9443", depends_on_ssh: false },
        CheckDef { id: CheckId::Vaultwarden, name: "Vaultwarden reachable via HTTPS (port 4123)", section: Section::Vaultwarden, protocol: "HTTPS", port: "4123", depends_on_ssh: false },
        CheckDef { id: CheckId::Planka, name: "Planka reachable + login (port 3000)", section: Section::Planka, protocol: "HTTP", port: "3000", depends_on_ssh: false },
        // SSH-dependent
        CheckDef { id: CheckId::MysqlRemote, name: "MySQL remote login on port 3306", section: Section::Mysql, protocol: "TCP", port: "3306", depends_on_ssh: true },
        CheckDef { id: CheckId::Internet, name: "Internet access from VM (ping 8.8.8.8)", section: Section::Network, protocol: "ICMP", port: "-", depends_on_ssh: true },
        CheckDef { id: CheckId::Sftp, name: "SFTP upload + HTTPS roundtrip", section: Section::Sftp, protocol: "SFTP", port: "22", depends_on_ssh: true },
        CheckDef { id: CheckId::MysqlLocal, name: "MySQL local via SSH", section: Section::Mysql, protocol: "SSH", port: "22", depends_on_ssh: true },
        CheckDef { id: CheckId::MysqlAdmin, name: "MySQL admin not reachable remotely", section: Section::Mysql, protocol: "SSH", port: "3306", depends_on_ssh: true },
        CheckDef { id: CheckId::WpDb, name: "WordPress database wpdb reachable", section: Section::WordPress, protocol: "SSH", port: "22", depends_on_ssh: true },
        CheckDef { id: CheckId::Minetest, name: "Minetest UDP port 30000 open", section: Section::Minetest, protocol: "UDP", port: "30000", depends_on_ssh: true },
        CheckDef { id: CheckId::Docker, name: "Docker containers, volumes & compose", section: Section::Docker, protocol: "SSH", port: "22", depends_on_ssh: true },
    ]
}

#[derive(Debug, Clone)]
pub struct CheckState {
    pub def: CheckDef,
    pub status: CheckStatus,
    pub results: Vec<CheckResult>,
    pub duration: Duration,
}

impl CheckState {
    pub fn new(def: CheckDef) -> Self {
        Self {
            def,
            status: CheckStatus::NotRun,
            results: Vec::new(),
            duration: Duration::ZERO,
        }
    }

    pub fn reset(&mut self) {
        self.status = CheckStatus::NotRun;
        self.results.clear();
        self.duration = Duration::ZERO;
    }

    pub fn derive_overall_status(&self) -> CheckStatus {
        if self.results.is_empty() {
            return CheckStatus::NotRun;
        }
        if self.results.iter().any(|r| r.status == CheckStatus::Fail) {
            return CheckStatus::Fail;
        }
        if self.results.iter().all(|r| r.status == CheckStatus::Skip) {
            return CheckStatus::Skip;
        }
        CheckStatus::Pass
    }
}

#[derive(Debug, Clone, Default)]
pub struct Secrets {
    pub ssh_user: String,
    pub ssh_pass: String,
    pub mysql_remote_user: String,
    pub mysql_remote_pass: String,
    pub mysql_local_user: String,
    pub mysql_local_pass: String,
    pub wp_user: String,
    pub wp_pass: String,
}

impl Secrets {
    pub fn from_map(map: &HashMap<String, String>) -> Self {
        Self {
            ssh_user: map.get("SSH_USER").cloned().unwrap_or_default(),
            ssh_pass: map.get("SSH_PASS").cloned().unwrap_or_default(),
            mysql_remote_user: map.get("MYSQL_REMOTE_USER").cloned().unwrap_or_default(),
            mysql_remote_pass: map.get("MYSQL_REMOTE_PASS").cloned().unwrap_or_default(),
            mysql_local_user: map.get("MYSQL_LOCAL_USER").cloned().unwrap_or_default(),
            mysql_local_pass: map.get("MYSQL_LOCAL_PASS").cloned().unwrap_or_default(),
            wp_user: map.get("WP_USER").cloned().unwrap_or_default(),
            wp_pass: map.get("WP_PASS").cloned().unwrap_or_default(),
        }
    }
}

#[derive(Clone)]
pub struct Config {
    pub target: String,
    pub local_user: String,
    pub secrets: Secrets,
}

/// Shared state between the GUI and background check threads.
pub type SharedStates = Arc<Mutex<Vec<CheckState>>>;
