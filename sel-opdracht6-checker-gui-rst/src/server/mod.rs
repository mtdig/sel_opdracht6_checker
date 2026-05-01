//! Web server mode: `--server [--port PORT]`
//!
//! Env vars (loaded from .env if present):
//!   PASSPHRASE   — decryption passphrase for secrets.env.enc
//!   TARGET       — default SSH target (overrides config default)
//!   LOCAL_USER   — local username (overrides whoami)
//!
//! Endpoints:
//!   GET  /                          HTML dashboard (Bootstrap + HTMX)
//!   GET  /fragments/dashboard       HTMX-polled section cards grid
//!   GET  /fragments/stats           HTMX-polled stats bar
//!   GET  /fragments/section/:id     HTMX section detail panel
//!   GET  /api/status                Full JSON status of all checks
//!   GET  /api/status/:section       JSON status of one section
//!   POST /api/run                   Start all checks (no body required)
//!   POST /api/run/:check_id         Re-run one check  { "check": "<id>" }

use std::sync::{Arc, Mutex};

use askama::Template;
use axum::{
    extract::{Path, State},
    response::{Html, IntoResponse, Response},
    routing::get,
    Json, Router,
};
use serde::Serialize;
use tokio::sync::Mutex as TokioMutex;

use crate::{checks, crypto, types::*};

//  Shared server state 

#[derive(Clone)]
pub struct ServerState {
    states:      SharedStates,
    ssh_session: checks::SharedSshSession,
    config:      Arc<Mutex<Option<Config>>>,
    app_config:  AppConfig,
    /// Passphrase from PASSPHRASE env var (may be empty)
    passphrase:  String,
    /// Default target from TARGET env var (falls back to app_config)
    env_target:  String,
    /// Local user from LOCAL_USER env var (falls back to whoami)
    env_user:    String,
}

impl ServerState {
    fn new(app_config: AppConfig, passphrase: String, env_target: String, env_user: String) -> Self {
        let states = all_checks().into_iter().map(CheckState::new).collect();
        Self {
            states:      Arc::new(Mutex::new(states)),
            ssh_session: Arc::new(TokioMutex::new(None)),
            config:      Arc::new(Mutex::new(None)),
            app_config,
            passphrase,
            env_target,
            env_user,
        }
    }

    fn is_running(&self) -> bool {
        self.states.lock().unwrap().iter().any(|s| s.status == CheckStatus::Running)
    }

    fn reset_all(&self) {
        for s in self.states.lock().unwrap().iter_mut() { s.reset(); }
    }

    fn stats(&self) -> Stats {
        let g = self.states.lock().unwrap();
        let results: Vec<&CheckResult> = g.iter().flat_map(|s| &s.results).collect();
        Stats {
            passed:  results.iter().filter(|r| r.status == CheckStatus::Pass).count(),
            failed:  results.iter().filter(|r| r.status == CheckStatus::Fail).count(),
            skipped: results.iter().filter(|r| r.status == CheckStatus::Skip).count(),
            total:   results.len(),
            running: g.iter().any(|s| s.status == CheckStatus::Running),
        }
    }

    fn section_views(&self) -> Vec<SectionView> {
        use Section::*;
        [Network, Ssh, Apache, Sftp, Mysql, Portainer, Vaultwarden, Planka, WordPress, Docker, Minetest]
            .into_iter()
            .map(|sec| {
                let checks: Vec<CheckState> = {
                    let g = self.states.lock().unwrap();
                    g.iter().filter(|s| s.def.section == sec).cloned().collect()
                };

                let pass    = checks.iter().filter(|c| c.status == CheckStatus::Pass).count();
                let fail    = checks.iter().filter(|c| c.status == CheckStatus::Fail).count();
                let skip    = checks.iter().filter(|c| c.status == CheckStatus::Skip).count();
                let running = checks.iter().any(|c| c.status == CheckStatus::Running);
                let notrun  = checks.iter().all(|c| c.status == CheckStatus::NotRun);

                let status = if running    { "running" }
                    else if notrun         { "notrun"  }
                    else if fail > 0       { "fail"    }
                    else if skip > 0 && pass == 0 { "skip" }
                    else                   { "pass"    }.to_string();

                let color = hex_for(&status);

                let summary = if notrun {
                    "Not yet run".to_string()
                } else {
                    let mut p = Vec::new();
                    if pass > 0    { p.push(format!("{pass} passed"));  }
                    if fail > 0    { p.push(format!("{fail} failed"));  }
                    if skip > 0    { p.push(format!("{skip} skipped")); }
                    if running     { p.push("running…".to_string());    }
                    p.join(" · ")
                };

                SectionView {
                    id:          sec_str(sec),
                    label:       sec.label().to_string(),
                    color,
                    status,
                    check_count: checks.len(),
                    summary,
                    checks: checks.iter().map(|cs| {
                        let st = status_str(cs.status);
                        let co = hex_for(&st);
                        CheckView {
                            id:          check_str(cs.def.id),
                            name:        cs.def.name.to_string(),
                            color:       co,
                            status:      st,
                            protocol:    cs.def.protocol.to_string(),
                            port:        cs.def.port.to_string(),
                            duration_ms: cs.duration.as_millis() as u64,
                            results: cs.results.iter().map(|r| {
                                let rs = status_str(r.status);
                                let rc = hex_for(&rs);
                                ResultView {
                                    status:  rs,
                                    color:   rc,
                                    icon:    result_icon(r.status).to_string(),
                                    message: r.message.clone(),
                                    detail:  r.detail.clone(),
                                    command: r.command.clone(),
                                    output:  r.output.clone(),
                                }
                            }).collect(),
                        }
                    }).collect(),
                }
            })
            .collect()
    }
}

//  View structs (passed to Askama templates) 

struct Stats {
    passed:  usize,
    failed:  usize,
    skipped: usize,
    total:   usize,
    running: bool,
}

struct SectionView {
    id:          String,
    label:       String,
    color:       String,   // hex colour for this status
    status:      String,   // "pass" | "fail" | "skip" | "running" | "notrun"
    check_count: usize,
    summary:     String,
    checks:      Vec<CheckView>,
}

struct CheckView {
    id:          String,
    name:        String,
    color:       String,
    status:      String,
    protocol:    String,
    port:        String,
    duration_ms: u64,
    results:     Vec<ResultView>,
}

struct ResultView {
    status:  String,
    color:   String,
    icon:    String,
    message: String,
    detail:  String,
    command: String,
    output:  String,
}

//  Helpers 

fn hex_for(status: &str) -> String {
    match status {
        "pass"    => "#2ea043",
        "fail"    => "#da3633",
        "skip"    => "#d29922",
        "running" => "#3884f4",
        _         => "#64646e",
    }.to_string()
}

fn status_str(s: CheckStatus) -> String {
    match s {
        CheckStatus::Pass    => "pass",
        CheckStatus::Fail    => "fail",
        CheckStatus::Skip    => "skip",
        CheckStatus::Running => "running",
        CheckStatus::NotRun  => "notrun",
    }.to_string()
}

fn result_icon(s: CheckStatus) -> &'static str {
    match s {
        CheckStatus::Pass => "PASS",
        CheckStatus::Fail => "FAIL",
        CheckStatus::Skip => "SKIP",
        _                 => "——",
    }
}

fn sec_str(s: Section) -> String {
    match s {
        Section::Network     => "network",
        Section::Ssh         => "ssh",
        Section::Apache      => "apache",
        Section::Sftp        => "sftp",
        Section::Mysql       => "mysql",
        Section::Portainer   => "portainer",
        Section::Vaultwarden => "vaultwarden",
        Section::Planka      => "planka",
        Section::WordPress   => "wordpress",
        Section::Docker      => "docker",
        Section::Minetest    => "minetest",
    }.to_string()
}

fn str_to_sec(s: &str) -> Option<Section> {
    match s {
        "network"     => Some(Section::Network),
        "ssh"         => Some(Section::Ssh),
        "apache"      => Some(Section::Apache),
        "sftp"        => Some(Section::Sftp),
        "mysql"       => Some(Section::Mysql),
        "portainer"   => Some(Section::Portainer),
        "vaultwarden" => Some(Section::Vaultwarden),
        "planka"      => Some(Section::Planka),
        "wordpress"   => Some(Section::WordPress),
        "docker"      => Some(Section::Docker),
        "minetest"    => Some(Section::Minetest),
        _             => None,
    }
}

fn check_str(c: CheckId) -> String {
    match c {
        CheckId::Ping        => "ping",
        CheckId::Ssh         => "ssh",
        CheckId::Apache      => "apache",
        CheckId::Sftp        => "sftp",
        CheckId::Docker      => "docker",
        CheckId::Internet    => "internet",
        CheckId::MysqlRemote => "mysql-remote",
        CheckId::MysqlLocal  => "mysql-local",
        CheckId::MysqlAdmin  => "mysql-admin",
        CheckId::Portainer   => "portainer",
        CheckId::Vaultwarden => "vaultwarden",
        CheckId::Planka      => "planka",
        CheckId::WpReachable => "wp-reachable",
        CheckId::WpPosts     => "wp-posts",
        CheckId::WpLogin     => "wp-login",
        CheckId::WpDb        => "wp-db",
        CheckId::Minetest    => "minetest",
    }.to_string()
}

fn str_to_check(s: &str) -> Option<CheckId> {
    match s {
        "ping"         => Some(CheckId::Ping),
        "ssh"          => Some(CheckId::Ssh),
        "apache"       => Some(CheckId::Apache),
        "sftp"         => Some(CheckId::Sftp),
        "docker"       => Some(CheckId::Docker),
        "internet"     => Some(CheckId::Internet),
        "mysql-remote" => Some(CheckId::MysqlRemote),
        "mysql-local"  => Some(CheckId::MysqlLocal),
        "mysql-admin"  => Some(CheckId::MysqlAdmin),
        "portainer"    => Some(CheckId::Portainer),
        "vaultwarden"  => Some(CheckId::Vaultwarden),
        "planka"       => Some(CheckId::Planka),
        "wp-reachable" => Some(CheckId::WpReachable),
        "wp-posts"     => Some(CheckId::WpPosts),
        "wp-login"     => Some(CheckId::WpLogin),
        "wp-db"        => Some(CheckId::WpDb),
        "minetest"     => Some(CheckId::Minetest),
        _              => None,
    }
}

//  Askama templates 

#[derive(Template)]
#[template(path = "index.html")]
struct IndexTmpl {
    default_target: String,
    local_user:     String,
}

#[derive(Template)]
#[template(path = "frags/dashboard.html")]
struct DashFrag {
    sections: Vec<SectionView>,
}

#[derive(Template)]
#[template(path = "frags/stats.html")]
struct StatsFrag {
    stats: Stats,
}

#[derive(Template)]
#[template(path = "frags/section.html")]
struct SectionFrag {
    section: SectionView,
    section_id: String,
    running: bool,
}

fn render<T: Template>(t: T) -> Html<String> {
    Html(t.render().unwrap_or_else(|e| format!("<pre style='color:#da3633'>Template error: {e}</pre>")))
}

//  API types 

#[derive(Serialize)]
struct RunSingleResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    error:   Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    check:   Option<ApiCheck>,
    #[serde(skip_serializing_if = "Option::is_none")]
    section: Option<ApiSection>,
}

impl RunSingleResponse {
    fn ok(check: ApiCheck)          -> Self { Self { error: None,           check: Some(check), section: None         } }
    fn ok_section(s: ApiSection)    -> Self { Self { error: None,           check: None,        section: Some(s)      } }
    fn err(e: impl Into<String>)    -> Self { Self { error: Some(e.into()), check: None,        section: None         } }
}

#[derive(Serialize)]
struct RunResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    error:   Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

impl RunResponse {
    fn ok(msg: impl Into<String>) -> Self { Self { error: None, message: Some(msg.into()) } }
    fn err(e: impl Into<String>) -> Self  { Self { error: Some(e.into()), message: None } }
}

#[derive(Serialize)]
struct ApiStatus {
    running:  bool,
    total:    usize,
    passed:   usize,
    failed:   usize,
    skipped:  usize,
    sections: Vec<ApiSection>,
}

#[derive(Serialize)]
struct ApiSection {
    id:     String,
    name:   String,
    status: String,
    checks: Vec<ApiCheck>,
}

#[derive(Serialize)]
struct ApiCheck {
    id:          String,
    name:        String,
    status:      String,
    duration_ms: u64,
    protocol:    String,
    port:        String,
    results:     Vec<ApiResult>,
}

#[derive(Serialize)]
struct ApiResult {
    status:  String,
    message: String,
    detail:  String,
    command: String,
    output:  String,
}

fn section_view_to_api(s: SectionView) -> ApiSection {
    ApiSection {
        id:     s.id,
        name:   s.label,
        status: s.status,
        checks: s.checks.into_iter().map(|c| ApiCheck {
            id:          c.id,
            name:        c.name,
            status:      c.status,
            duration_ms: c.duration_ms,
            protocol:    c.protocol,
            port:        c.port,
            results:     c.results.into_iter().map(|r| ApiResult {
                status:  r.status,
                message: r.message,
                detail:  r.detail,
                command: r.command,
                output:  r.output,
            }).collect(),
        }).collect(),
    }
}

//  Handlers 

type AS = Arc<ServerState>;

async fn handle_index(State(st): State<AS>) -> Html<String> {
    render(IndexTmpl {
        default_target: st.app_config.general.default_target.clone(),
        local_user:     whoami::username(),
    })
}

async fn handle_dashboard_frag(State(st): State<AS>) -> Html<String> {
    render(DashFrag { sections: st.section_views() })
}

async fn handle_stats_frag(State(st): State<AS>) -> Html<String> {
    render(StatsFrag { stats: st.stats() })
}

async fn handle_section_frag(State(st): State<AS>, Path(section_id): Path<String>) -> Html<String> {
    let sections = st.section_views();
    let running  = st.is_running();
    match sections.into_iter().find(|s| s.id == section_id) {
        Some(section) => render(SectionFrag { section, section_id, running }),
        None => Html(format!("<p style='color:#da3633'>Unknown section: {section_id}</p>")),
    }
}

async fn handle_api_status(State(st): State<AS>) -> Json<ApiStatus> {
    let stats    = st.stats();
    let sections = st.section_views().into_iter().map(section_view_to_api).collect();
    Json(ApiStatus {
        running:  stats.running,
        total:    stats.total,
        passed:   stats.passed,
        failed:   stats.failed,
        skipped:  stats.skipped,
        sections,
    })
}

async fn handle_api_status_section(
    State(st): State<AS>,
    Path(section_id): Path<String>,
) -> Response {
    if str_to_sec(&section_id).is_none() {
        return (axum::http::StatusCode::NOT_FOUND,
                Json(serde_json::json!({"error": "unknown section"}))).into_response();
    }
    match st.section_views().into_iter().find(|s| s.id == section_id) {
        Some(sv) => Json(section_view_to_api(sv)).into_response(),
        None     => (axum::http::StatusCode::NOT_FOUND,
                     Json(serde_json::json!({"error": "section not found"}))).into_response(),
    }
}

async fn handle_api_run(State(st): State<AS>) -> Json<RunResponse> {
    if st.is_running() {
        return Json(RunResponse::err("Already running"));
    }

    // Passphrase: env var only
    let passphrase = st.passphrase.clone();
    if passphrase.is_empty() {
        return Json(RunResponse::err(
            "No passphrase: set PASSPHRASE env var (or .env file)"
        ));
    }

    let target = if !st.env_target.is_empty() { st.env_target.clone() }
                 else { st.app_config.general.default_target.clone() };
    let local_user = if !st.env_user.is_empty() { st.env_user.clone() }
                     else { whoami::username() };

    let secrets_map = match crypto::decrypt_secrets(&passphrase) {
        Ok(m)  => m,
        Err(e) => return Json(RunResponse::err(format!("Decryption failed: {e}"))),
    };
    let config = Config {
        target,
        local_user,
        secrets: Secrets::from_map(&secrets_map),
        app:     st.app_config.clone(),
    };
    *st.config.lock().unwrap() = Some(config.clone());
    st.reset_all();
    *st.ssh_session.lock().await = None;
    checks::run_all(config, st.states.clone(), st.ssh_session.clone(),
                    tokio::runtime::Handle::current());
    Json(RunResponse::ok("Secrets decrypted OK — checks started"))
}

async fn handle_api_run_single(
    State(st): State<AS>,
    Path(check_id): Path<String>,
) -> Json<RunSingleResponse> {
    // Check id from path only — accept either a check id or a section name
    let id_str = &check_id;

    // Fast-path: section name → run all checks in that section
    if let Some(sec) = str_to_sec(id_str) {
        // resolve config (same logic as single-check path below)
        let config = {
            let passphrase = st.passphrase.clone();
            if !passphrase.is_empty() {
                let secrets_map = match crypto::decrypt_secrets(&passphrase) {
                    Ok(m)  => m,
                    Err(e) => return Json(RunSingleResponse::err(format!("Decryption failed: {e}"))),
                };
                let cfg = Config {
                    target: if !st.env_target.is_empty() { st.env_target.clone() }
                            else { st.app_config.general.default_target.clone() },
                    local_user: if !st.env_user.is_empty() { st.env_user.clone() }
                                else { whoami::username() },
                    secrets: Secrets::from_map(&secrets_map),
                    app:     st.app_config.clone(),
                };
                *st.config.lock().unwrap() = Some(cfg.clone());
                cfg
            } else {
                match st.config.lock().unwrap().clone() {
                    Some(c) => c,
                    None    => return Json(RunSingleResponse::err(
                        "No passphrase: set PASSPHRASE env var (or .env file)"
                    )),
                }
            }
        };

        // Collect all check ids that belong to this section
        let check_ids: Vec<CheckId> = all_checks()
            .into_iter()
            .filter(|d| d.section == sec)
            .map(|d| d.id)
            .collect();

        // Spawn each check
        let handle = tokio::runtime::Handle::current();
        for id in &check_ids {
            checks::run_single(*id, config.clone(), st.states.clone(),
                               st.ssh_session.clone(), handle.clone());
        }

        // Wait until all checks in the section are no longer Running
        'wait: for _ in 0..40 {
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
            let guard = st.states.lock().unwrap();
            let all_done = check_ids.iter().all(|id| {
                guard.iter()
                    .find(|s| s.def.id == *id)
                    .map(|s| s.status != crate::types::CheckStatus::Running)
                    .unwrap_or(true)
            });
            if all_done { break 'wait; }
        }

        // Return the full section view
        let views = st.section_views();
        if let Some(sv) = views.into_iter().find(|sv| sv.id == *id_str) {
            return Json(RunSingleResponse::ok_section(section_view_to_api(sv)));
        }
        return Json(RunSingleResponse::err(format!("Section '{id_str}' not found in results")));
    }

    let id = match str_to_check(id_str) {
        Some(id) => id,
        None     => return Json(RunSingleResponse::err(format!("Unknown check or section: {id_str}"))),
    };

    // Build config: env passphrase > cached config
    let config = {
        let passphrase = st.passphrase.clone();

        if !passphrase.is_empty() {
            let secrets_map = match crypto::decrypt_secrets(&passphrase) {
                Ok(m)  => m,
                Err(e) => return Json(RunSingleResponse::err(format!("Decryption failed: {e}"))),
            };
            let cfg = Config {
                target: if !st.env_target.is_empty() { st.env_target.clone() }
                        else { st.app_config.general.default_target.clone() },
                local_user: if !st.env_user.is_empty() { st.env_user.clone() }
                            else { whoami::username() },
                secrets: Secrets::from_map(&secrets_map),
                app:     st.app_config.clone(),
            };
            *st.config.lock().unwrap() = Some(cfg.clone());
            cfg
        } else {
            match st.config.lock().unwrap().clone() {
                Some(c) => c,
                None    => return Json(RunSingleResponse::err(
                    "No passphrase: set PASSPHRASE env var (or .env file)"
                )),
            }
        }
    };

    checks::run_single(id, config, st.states.clone(), st.ssh_session.clone(),
                       tokio::runtime::Handle::current());

    // Wait briefly for the check to complete, then return its status.
    // For fast checks this returns final results; for slow ones it returns
    // running status and the caller can poll /api/status.
    for _ in 0..40 {
        tokio::time::sleep(std::time::Duration::from_millis(250)).await;
        let guard = st.states.lock().unwrap();
        if let Some(s) = guard.iter().find(|s| s.def.id == id) {
            if s.status != crate::types::CheckStatus::Running {
                break;
            }
        }
    }

    // Build the ApiCheck response for just this check.
    let views = st.section_views();
    for sec in views {
        for check in sec.checks {
            if check_str(id) == check.id {
                return Json(RunSingleResponse::ok(ApiCheck {
                    id:          check.id,
                    name:        check.name,
                    status:      check.status,
                    duration_ms: check.duration_ms,
                    protocol:    check.protocol,
                    port:        check.port,
                    results:     check.results.into_iter().map(|r| ApiResult {
                        status:  r.status,
                        message: r.message,
                        detail:  r.detail,
                        command: r.command,
                        output:  r.output,
                    }).collect(),
                }));
            }
        }
    }
    Json(RunSingleResponse::err(format!("Check '{id_str}' not found in results")))
}

//  Public entry point 

pub async fn run(port: u16) {
    // Load .env if present (silently ignore if missing)
    let _ = dotenvy::dotenv();

    let passphrase = std::env::var("PASSPHRASE").unwrap_or_default();
    let env_target = std::env::var("TARGET").unwrap_or_default();
    let env_user   = std::env::var("LOCAL_USER").unwrap_or_default();

    if !passphrase.is_empty() {
        println!("PASSPHRASE loaded from environment");
    }
    if !env_target.is_empty() {
        println!("TARGET={env_target}");
    }

    let state = Arc::new(ServerState::new(AppConfig::load(), passphrase, env_target, env_user));

    let router = Router::new()
        .route("/",                         get(handle_index))
        .route("/fragments/dashboard",      get(handle_dashboard_frag))
        .route("/fragments/stats",          get(handle_stats_frag))
        .route("/fragments/section/:id",    get(handle_section_frag))
        .route("/api/status",               get(handle_api_status))
        .route("/api/status/:section",      get(handle_api_status_section))
        .route("/api/run",                  get(handle_api_run))
        .route("/api/run/:check_id",        get(handle_api_run_single))
        .with_state(state);

    let addr = format!("0.0.0.0:{port}");
    println!("SELab checker web UI  →  http://localhost:{port}");
    println!("API docs: GET /api/status  |  POST /api/run  |  POST /api/run/:check");
    let listener = tokio::net::TcpListener::bind(&addr).await
        .unwrap_or_else(|e| panic!("Failed to bind {addr}: {e}"));
    axum::serve(listener, router).await.expect("Server error");
}
