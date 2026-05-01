use serde::Deserialize;
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
    pub status:  CheckStatus,
    pub message: String,
    pub detail:  String,
    /// The shell command that was executed (empty for non-SSH checks)
    pub command: String,
    /// Raw stdout/stderr output of the command (empty if not applicable)
    pub output:  String,
}

impl CheckResult {
    pub fn pass(msg: impl Into<String>) -> Self {
        Self {
            status:  CheckStatus::Pass,
            message: msg.into(),
            detail:  String::new(),
            command: String::new(),
            output:  String::new(),
        }
    }

    pub fn fail(msg: impl Into<String>, detail: impl Into<String>) -> Self {
        Self {
            status:  CheckStatus::Fail,
            message: msg.into(),
            detail:  detail.into(),
            command: String::new(),
            output:  String::new(),
        }
    }

    pub fn skip(msg: impl Into<String>, reason: impl Into<String>) -> Self {
        Self {
            status:  CheckStatus::Skip,
            message: msg.into(),
            detail:  reason.into(),
            command: String::new(),
            output:  String::new(),
        }
    }

    /// Attach the SSH command and its raw output to this result.
    pub fn with_cmd(mut self, command: impl Into<String>, output: impl Into<String>) -> Self {
        self.command = command.into();
        self.output  = output.into();
        self
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

// hardcoded, i don't care for this uc
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
        // SSH-dependent !
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
    pub app: AppConfig,
}

//  checker.toml

#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    #[serde(default)]
    pub general: GeneralCfg,
    #[serde(default)]
    pub ssh: SshCfg,
    #[serde(default)]
    pub apache: ApacheCfg,
    #[serde(default)]
    pub sftp: SftpCfg,
    #[serde(default)]
    pub mysql: MysqlCfg,
    #[serde(default)]
    pub wordpress: WordPressCfg,
    #[serde(default)]
    pub portainer: PortainerCfg,
    #[serde(default)]
    pub vaultwarden: VaultwardenCfg,
    #[serde(default)]
    pub planka: PlankaCfg,
    #[serde(default)]
    pub minetest: MinetestCfg,
    #[serde(default)]
    pub docker: DockerCfg,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct GeneralCfg {
    pub default_target: String,
    pub internet_ping_target: String,
}

// virtualbox default hostonly network is 192.168.56.0/24
// on Gilles' machine, the VM is at 192.168.128.20
impl Default for GeneralCfg {
    fn default() -> Self {
        Self {
            default_target: "192.168.56.20".into(),
            internet_ping_target: "8.8.8.8".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct SshCfg {
    pub port: u16,
}
impl Default for SshCfg {
    fn default() -> Self { Self { port: 22 } }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct ApacheCfg {
    pub expected_text: String,
}
impl Default for ApacheCfg {
    fn default() -> Self {
        Self {
            expected_text: "Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct SftpCfg {
    pub remote_path: String,
    pub check_filename: String,
}
impl Default for SftpCfg {
    fn default() -> Self {
        Self {
            remote_path: "/var/www/html/opdracht6.html".into(),
            check_filename: "opdracht6.html".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct MysqlCfg {
    pub port: u16,
    pub database: String,
}
impl Default for MysqlCfg {
    fn default() -> Self {
        Self { port: 3306, database: "appdb".into() }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct WordPressCfg {
    pub port: u16,
    pub database: String,
    pub min_posts: usize,
}
impl Default for WordPressCfg {
    fn default() -> Self {
        Self { port: 8080, database: "wpdb".into(), min_posts: 3 }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct PortainerCfg {
    pub port: u16,
}
impl Default for PortainerCfg {
    fn default() -> Self { Self { port: 9443 } }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct VaultwardenCfg {
    pub port: u16,
}
impl Default for VaultwardenCfg {
    fn default() -> Self { Self { port: 4123 } }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct PlankaCfg {
    pub port: u16,
    pub test_user: String,
    pub test_pass: String,
}
impl Default for PlankaCfg {
    fn default() -> Self {
        Self {
            port: 3000,
            test_user: "troubleshoot@selab.hogent.be".into(),
            test_pass: "shoot".into(),
        }
    }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct MinetestCfg {
    pub port: u16,
}
impl Default for MinetestCfg {
    fn default() -> Self { Self { port: 30000 } }
}

#[derive(Debug, Clone, Deserialize)]
#[serde(default)]
pub struct DockerCfg {
    pub expected_containers: Vec<String>,
    pub shared_compose_path: String,
    pub planka_compose_path: String,
}
impl Default for DockerCfg {
    fn default() -> Self {
        Self {
            expected_containers: vec![
                "vaultwarden".into(), "minetest".into(),
                "portainer".into(), "planka".into(),
            ],
            shared_compose_path: "~/docker".into(),
            planka_compose_path: "~/docker/planka".into(),
        }
    }
}

impl Default for AppConfig {
    fn default() -> Self {
        Self {
            general: GeneralCfg::default(),
            ssh: SshCfg::default(),
            apache: ApacheCfg::default(),
            sftp: SftpCfg::default(),
            mysql: MysqlCfg::default(),
            wordpress: WordPressCfg::default(),
            portainer: PortainerCfg::default(),
            vaultwarden: VaultwardenCfg::default(),
            planka: PlankaCfg::default(),
            minetest: MinetestCfg::default(),
            docker: DockerCfg::default(),
        }
    }
}

impl AppConfig {
    /// The embedded default configuration compiled into the binary.
    pub const EMBEDDED_TOML: &'static str = include_str!("../checker.toml");

    /// Load configuration.
    /// 1. If checker.toml exists next to the executable, use it.
    /// 2. Otherwise, parse the embedded default.
    pub fn load() -> Self {
        // 1. Next to the executable
        if let Ok(exe) = std::env::current_exe() {
            if let Some(dir) = exe.parent() {
                let path = dir.join("checker.toml");
                if let Ok(text) = std::fs::read_to_string(&path) {
                    if let Ok(cfg) = toml::from_str::<AppConfig>(&text) {
                        eprintln!("[config] loaded {}", path.display());
                        return cfg;
                    }
                }
            }
        }
        // 2. Embedded default
        eprintln!("[config] using embedded defaults");
        toml::from_str::<AppConfig>(Self::EMBEDDED_TOML)
            .expect("embedded checker.toml is invalid")
    }
}

/// Shared state between the GUI and background check threads.
pub type SharedStates = Arc<Mutex<Vec<CheckState>>>;
