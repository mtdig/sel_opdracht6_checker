// SELab Opdracht 6 Checker — Rust/egui edition
// Equivalent of the Java/JavaFX GUI, but less painful (with AI's help)


// windows is a different animal
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod checks;
mod crypto;
mod types;

use checks::SharedSshSession;
use eframe::egui;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::Mutex as TokioMutex;
use types::*;


const COL_BG: egui::Color32 = egui::Color32::from_rgb(30, 30, 36);
const COL_SIDE: egui::Color32 = egui::Color32::from_rgb(24, 24, 30);
const COL_CARD: egui::Color32 = egui::Color32::from_rgb(40, 40, 48);

const COL_PASS: egui::Color32 = egui::Color32::from_rgb(46, 160, 67);
const COL_FAIL: egui::Color32 = egui::Color32::from_rgb(218, 54, 51);
const COL_SKIP: egui::Color32 = egui::Color32::from_rgb(210, 153, 34);
const COL_RUNNING: egui::Color32 = egui::Color32::from_rgb(56, 132, 244);
const COL_NOT_RUN: egui::Color32 = egui::Color32::from_rgb(100, 100, 110);

const COL_TEXT: egui::Color32 = egui::Color32::from_rgb(220, 220, 230);
const COL_TEXT_DIM: egui::Color32 = egui::Color32::from_rgb(140, 140, 155);

fn status_color(s: CheckStatus) -> egui::Color32 {
    match s {
        CheckStatus::Pass => COL_PASS,
        CheckStatus::Fail => COL_FAIL,
        CheckStatus::Skip => COL_SKIP,
        CheckStatus::Running => COL_RUNNING,
        CheckStatus::NotRun => COL_NOT_RUN,
    }
}


//  App state 

#[derive(PartialEq, Clone)]
enum View {
    Grid,
    Detail(Section),
}

struct App {
    target: String,
    local_user: String,
    passphrase: String,
    status_msg: String,
    status_ok: bool,

    states: SharedStates,
    ssh_session: SharedSshSession,
    config: Option<Config>,
    app_config: AppConfig,

    rt: tokio::runtime::Handle,

    view: View,
    running: bool,
    run_start: Option<Instant>,
    total_duration: Duration,

    show_summary: bool,
    summary_shown_for_run: bool,
}

impl App {
    fn new(rt: tokio::runtime::Handle) -> Self {
        let app_config = AppConfig::load();
        let defs = all_checks();
        let states: Vec<CheckState> = defs.into_iter().map(CheckState::new).collect();

        let default_target = app_config.general.default_target.clone();
        Self {
            target: default_target,
            local_user: whoami::username(),
            passphrase: String::new(),
            status_msg: String::new(),
            status_ok: false,

            states: Arc::new(Mutex::new(states)),
            ssh_session: Arc::new(TokioMutex::new(None)),
            config: None,
            app_config,
            rt,

            view: View::Grid,
            running: false,
            run_start: None,
            total_duration: Duration::ZERO,
            show_summary: false,
            summary_shown_for_run: false,
        }
    }

    //  helpers, move to it's own module later?

    fn is_all_done(&self) -> bool {
        let guard = self.states.lock().unwrap();
        guard.iter().all(|s| s.status.is_terminal())
    }

    fn count(&self, status: CheckStatus) -> usize {
        let guard = self.states.lock().unwrap();
        guard
            .iter()
            .flat_map(|s| &s.results)
            .filter(|r| r.status == status)
            .count()
    }

    fn total_results(&self) -> usize {
        let guard = self.states.lock().unwrap();
        guard.iter().map(|s| s.results.len()).sum()
    }

    fn sections_ordered(&self) -> Vec<Section> {
        use Section::*;
        vec![
            Network, Ssh, Apache, Sftp, Mysql, Portainer, Vaultwarden, Planka, WordPress,
            Docker, Minetest,
        ]
    }

    fn checks_for_section(&self, section: Section) -> Vec<CheckState> {
        let guard = self.states.lock().unwrap();
        guard
            .iter()
            .filter(|s| s.def.section == section)
            .cloned()
            .collect()
    }

    fn aggregate_section_status(&self, section: Section) -> CheckStatus {
        let checks = self.checks_for_section(section);
        let mut any_running = false;
        let mut any_fail = false;
        let mut any_pass = false;
        let mut any_skip = false;
        let mut all_not_run = true;

        for c in &checks {
            match c.status {
                CheckStatus::Running => {
                    any_running = true;
                    all_not_run = false;
                }
                CheckStatus::Fail => {
                    any_fail = true;
                    all_not_run = false;
                }
                CheckStatus::Pass => {
                    any_pass = true;
                    all_not_run = false;
                }
                CheckStatus::Skip => {
                    any_skip = true;
                    all_not_run = false;
                }
                CheckStatus::NotRun => {}
            }
        }

        if all_not_run {
            CheckStatus::NotRun
        } else if any_running {
            CheckStatus::Running
        } else if any_fail {
            CheckStatus::Fail
        } else if any_skip && !any_pass {
            CheckStatus::Skip
        } else {
            CheckStatus::Pass
        }
    }

    //  actions 

    fn on_run_all(&mut self) {
        self.status_msg.clear();

        if self.target.trim().is_empty() {
            self.status_msg = "Target is required.".into();
            self.status_ok = false;
            return;
        }
        if self.passphrase.is_empty() {
            self.status_msg = "Passphrase is required.".into();
            self.status_ok = false;
            return;
        }

        let secrets_map = match crypto::decrypt_secrets(&self.passphrase) {
            Ok(m) => m,
            Err(e) => {
                self.status_msg = format!("Decryption failed: {e}");
                self.status_ok = false;
                return;
            }
        };

        let secrets = Secrets::from_map(&secrets_map);
        let config = Config {
            target: self.target.trim().to_string(),
            local_user: self.local_user.trim().to_string(),
            secrets,
            app: self.app_config.clone(),
        };
        self.config = Some(config.clone());

        // Reset states
        {
            let mut guard = self.states.lock().unwrap();
            for s in guard.iter_mut() {
                s.reset();
            }
        }

        self.status_msg = "Secrets decrypted OK — running checks…".into();
        self.status_ok = true;
        self.running = true;
        self.run_start = Some(Instant::now());
        self.show_summary = false;
        self.summary_shown_for_run = false;

        // Reset SSH session
        self.ssh_session = Arc::new(TokioMutex::new(None));

        checks::run_all(config, self.states.clone(), self.ssh_session.clone(), self.rt.clone());
    }

    fn on_run_single(&mut self, check_id: CheckId) {
        if let Some(config) = &self.config {
            checks::run_single(
                check_id,
                config.clone(),
                self.states.clone(),
                self.ssh_session.clone(),
                self.rt.clone(),
            );
        }
    }
}

//  egui rendering - lots of AI generated code here, not much to explain
// didn't want to handle all ui alligning and coloring manually, so I let the AI do it based on some examples and tweaks
// I will spend more time with egui, because it seems what i want and i can use it with WASM.
// Tauri is also interesting, but I want to avoid the web stack if possible, and egui can do native and WASM with the same codebase.
// leptos is pretty awesome and also does WASM
impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        // Poll for completion
        if self.running {
            if self.is_all_done() {
                self.running = false;
                self.total_duration = self.run_start.map_or(Duration::ZERO, |s| s.elapsed());
                if !self.summary_shown_for_run {
                    self.summary_shown_for_run = true;
                    self.show_summary = true;
                }
            }
            // Keep repainting while running
            ctx.request_repaint_after(std::time::Duration::from_millis(100));
        }

        // Configure visuals
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = COL_BG;
        visuals.window_fill = COL_BG;
        visuals.widgets.noninteractive.bg_fill = COL_CARD;
        ctx.set_visuals(visuals);

        // Side panel
        egui::SidePanel::left("config_panel")
            .min_width(240.0)
            .max_width(280.0)
            .resizable(false)
            .show(ctx, |ui| {
                ui.painter()
                    .rect_filled(ui.max_rect(), 0.0, COL_SIDE);
                self.draw_side_panel(ui);
            });

        // Central panel — always show the current view (grid or detail)
        egui::CentralPanel::default().show(ctx, |ui| match self.view.clone() {
            View::Grid => self.draw_grid(ui),
            View::Detail(section) => self.draw_detail(ui, section),
        });

        // Summary overlay popup (floating on top of the grid/detail)
        if self.show_summary {
            self.draw_summary_window(ctx);
        }
    }
}

impl App {
    //  Side panel 

    fn draw_side_panel(&mut self, ui: &mut egui::Ui) {
        ui.add_space(12.0);

        ui.vertical_centered(|ui| {
            ui.heading(
                egui::RichText::new("⚙ Configuration")
                    .color(COL_TEXT)
                    .strong(),
            );
        });
        ui.add_space(8.0);

        ui.label(egui::RichText::new("Target (hostname / IP)").color(COL_TEXT).size(14.0));
        ui.add(
            egui::TextEdit::singleline(&mut self.target)
                .desired_width(f32::INFINITY)
                .hint_text("e.g. 192.168.56.20"),
        );
        ui.add_space(4.0);

        ui.label(egui::RichText::new("Local user").color(COL_TEXT).size(14.0));
        ui.add(
            egui::TextEdit::singleline(&mut self.local_user)
                .desired_width(f32::INFINITY),
        );
        ui.add_space(4.0);

        ui.separator();
        ui.add_space(4.0);

        ui.label(egui::RichText::new("Decryption passphrase").color(COL_TEXT).size(14.0));
        ui.add(
            egui::TextEdit::singleline(&mut self.passphrase)
                .password(true)
                .desired_width(f32::INFINITY)
                .hint_text("passphrase for secrets.env.enc"),
        );

        ui.add_space(2.0);
        ui.label(
            egui::RichText::new("Embedded secrets are decrypted at runtime")
                .color(COL_TEXT_DIM)
                .size(12.0)
                .italics(),
        );

        ui.add_space(8.0);

        // Status
        if !self.status_msg.is_empty() {
            let color = if self.status_ok { COL_PASS } else { COL_FAIL };
            ui.label(egui::RichText::new(&self.status_msg).color(color).size(12.0));
        }

        // Stats
        if self.config.is_some() {
            ui.add_space(4.0);
            let pass = self.count(CheckStatus::Pass);
            let fail = self.count(CheckStatus::Fail);
            let skip = self.count(CheckStatus::Skip);
            let total = self.total_results();
            let dur = if self.running {
                self.run_start.map_or(0.0, |s| s.elapsed().as_secs_f64())
            } else {
                self.total_duration.as_secs_f64()
            };
            let text = format!(
                "{pass} passed · {fail} failed · {skip} skipped / {total}  |  {dur:.1}s"
            );
            ui.label(egui::RichText::new(text).color(COL_TEXT).size(12.0));
        }

        // Spacer
        let space = (ui.available_height() - 80.0).max(0.0);
        ui.add_space(space);

        // Buttons
        let btn_width = ui.available_width();

        let run_text = if self.running { "Running…" } else { "▶ Run All" };
        let run_btn = egui::Button::new(
            egui::RichText::new(run_text).color(egui::Color32::WHITE).strong(),
        )
        .fill(if self.running {
            COL_RUNNING
        } else {
            egui::Color32::from_rgb(46, 126, 218)
        })
        .min_size(egui::vec2(btn_width, 36.0));

        if ui.add_enabled(!self.running, run_btn).clicked() {
            self.on_run_all();
        }

        ui.add_space(4.0);

        let exit_btn = egui::Button::new(
            egui::RichText::new("Exit").color(egui::Color32::WHITE).strong(),
        )
        .fill(COL_FAIL)
        .min_size(egui::vec2(btn_width, 32.0));

        if ui.add(exit_btn).clicked() {
            std::process::exit(0);
        }

        ui.add_space(8.0);
    }

    //  Grid view 

    fn draw_grid(&mut self, ui: &mut egui::Ui) {
        ui.add_space(12.0);

        ui.horizontal(|ui| {
            ui.heading(
                egui::RichText::new("SELab Opdracht 6 Checker")
                    .color(COL_TEXT)
                    .strong(),
            );
        });
        ui.add_space(12.0);

        let sections = self.sections_ordered();
        let avail = ui.available_width();
        let tile_width = 180.0_f32;
        let spacing = 12.0_f32;
        let cols = ((avail + spacing) / (tile_width + spacing)).floor().max(1.0) as usize;

        egui::Grid::new("section_grid")
            .spacing(egui::vec2(spacing, spacing))
            .show(ui, |ui| {
                for (i, section) in sections.iter().enumerate() {
                    if i > 0 && i % cols == 0 {
                        ui.end_row();
                    }
                    self.draw_section_tile(ui, *section, tile_width);
                }
            });
    }

    fn draw_section_tile(&mut self, ui: &mut egui::Ui, section: Section, width: f32) {
        let checks = self.checks_for_section(section);
        let agg = self.aggregate_section_status(section);
        let col = status_color(agg);

        let (rect, response) = ui.allocate_exact_size(
            egui::vec2(width, 100.0),
            egui::Sense::click(),
        );

        // Background
        let rounding = 8.0;
        ui.painter().rect_filled(rect, rounding, COL_CARD);
        // Left accent
        let accent_rect = egui::Rect::from_min_max(
            rect.left_top(),
            egui::pos2(rect.left() + 4.0, rect.bottom()),
        );
        ui.painter()
            .rect_filled(accent_rect, rounding, col);

        // Hover
        if response.hovered() {
            ui.painter().rect(
                rect,
                rounding,
                egui::Color32::TRANSPARENT,
                egui::Stroke::new(1.5, col),
                egui::StrokeKind::Outside,
            );
        }

        // Text
        let text_rect = rect.shrink2(egui::vec2(14.0, 10.0));
        ui.painter().text(
            text_rect.left_top(),
            egui::Align2::LEFT_TOP,
            section.label(),
            egui::FontId::proportional(16.0),
            COL_TEXT,
        );

        let count_text = format!(
            "{} check{}",
            checks.len(),
            if checks.len() == 1 { "" } else { "s" }
        );
        ui.painter().text(
            text_rect.left_top() + egui::vec2(0.0, 22.0),
            egui::Align2::LEFT_TOP,
            count_text,
            egui::FontId::proportional(12.0),
            COL_TEXT_DIM,
        );

        // Status summary
        let summary = self.status_summary(&checks);
        ui.painter().text(
            egui::pos2(text_rect.left(), text_rect.bottom()),
            egui::Align2::LEFT_BOTTOM,
            summary,
            egui::FontId::proportional(12.0),
            col,
        );

        if response.clicked() {
            self.view = View::Detail(section);
        }
    }

    fn status_summary(&self, checks: &[CheckState]) -> String {
        let pass = checks.iter().filter(|c| c.status == CheckStatus::Pass).count();
        let fail = checks.iter().filter(|c| c.status == CheckStatus::Fail).count();
        let skip = checks.iter().filter(|c| c.status == CheckStatus::Skip).count();
        let running = checks.iter().filter(|c| c.status == CheckStatus::Running).count();
        let not_run = checks.iter().filter(|c| c.status == CheckStatus::NotRun).count();

        if not_run == checks.len() {
            return "Not yet run".into();
        }

        let mut parts = Vec::new();
        if pass > 0 { parts.push(format!("{pass} passed")); }
        if fail > 0 { parts.push(format!("{fail} failed")); }
        if skip > 0 { parts.push(format!("{skip} skipped")); }
        if running > 0 { parts.push(format!("{running} running")); }
        parts.join(" · ")
    }

    //  Detail view 

    fn draw_detail(&mut self, ui: &mut egui::Ui, section: Section) {
        ui.add_space(8.0);

        // Back button
        ui.horizontal(|ui| {
            if ui
                .button(egui::RichText::new("< Back to overview").color(COL_TEXT_DIM))
                .clicked()
            {
                self.view = View::Grid;
            }

            ui.heading(
                egui::RichText::new(format!("{} — Check Details", section.label()))
                    .color(COL_TEXT)
                    .strong(),
            );
        });
        ui.add_space(8.0);
        ui.separator();
        ui.add_space(8.0);

        let checks = self.checks_for_section(section);
        let mut action: Option<CheckId> = None;

        egui::ScrollArea::vertical().show(ui, |ui| {
            for cs in &checks {
                action = action.or(self.draw_check_card(ui, cs));
                ui.add_space(8.0);
            }
        });

        if let Some(id) = action {
            self.on_run_single(id);
        }
    }

    fn draw_check_card(&self, ui: &mut egui::Ui, cs: &CheckState) -> Option<CheckId> {
        let mut run_clicked = None;
        let col = status_color(cs.status);

        egui::Frame::NONE
            .fill(COL_CARD)
            .corner_radius(8.0)
            .inner_margin(12.0)
            .stroke(egui::Stroke::new(1.0, col.gamma_multiply(0.4)))
            .show(ui, |ui| {
                ui.set_min_width(ui.available_width());

                // Row 1: name + badge
                ui.horizontal(|ui| {
                    ui.label(
                        egui::RichText::new(cs.def.name)
                            .color(COL_TEXT)
                            .strong(),
                    );

                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        let badge_text = cs.status.label();

                        let (rect, _) = ui.allocate_exact_size(
                            egui::vec2(70.0, 20.0),
                            egui::Sense::hover(),
                        );
                        ui.painter().rect_filled(rect, 4.0, col);
                        ui.painter().text(
                            rect.center(),
                            egui::Align2::CENTER_CENTER,
                            badge_text,
                            egui::FontId::proportional(11.0),
                            egui::Color32::WHITE,
                        );
                    });
                });

                // Row 2: metadata
                let mut meta = format!(
                    "Protocol: {}  |  Port: {}",
                    cs.def.protocol, cs.def.port
                );
                if cs.duration.as_millis() > 0 {
                    meta += &format!("  |  Duration: {:.1}s", cs.duration.as_secs_f64());
                }
                ui.label(egui::RichText::new(meta).color(COL_TEXT_DIM).size(12.0));

                // Progress bar while running
                if cs.status == CheckStatus::Running {
                    ui.add_space(4.0);
                    let bar = egui::ProgressBar::new(0.0)
                        .animate(true)
                        .desired_width(ui.available_width());
                    ui.add(bar);
                }

                // Results
                if !cs.results.is_empty() {
                    ui.add_space(4.0);
                    ui.separator();
                    ui.add_space(4.0);

                    for r in &cs.results {
                        let (icon, icon_col) = match r.status {
                            CheckStatus::Pass => ("PASS", COL_PASS),
                            CheckStatus::Fail => ("FAIL", COL_FAIL),
                            CheckStatus::Skip => ("SKIP", COL_SKIP),
                            _ => ("——", COL_NOT_RUN),
                        };

                        ui.horizontal(|ui| {
                            ui.label(
                                egui::RichText::new(icon)
                                    .color(icon_col)
                                    .strong(),
                            );
                            ui.label(egui::RichText::new(&r.message).color(COL_TEXT));
                        });

                        if !r.detail.is_empty() {
                            ui.horizontal(|ui| {
                                ui.add_space(58.0);
                                ui.label(
                                    egui::RichText::new(format!("   {}", r.detail))
                                        .color(COL_TEXT_DIM)
                                        .size(12.0),
                                );
                            });
                        }
                    }
                }

                // Run button
                ui.add_space(6.0);
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Min), |ui| {
                    let is_running = cs.status == CheckStatus::Running;
                    let label = if is_running { "Running…" } else { "▶ Run" };
                    let btn = egui::Button::new(
                        egui::RichText::new(label).color(egui::Color32::WHITE).size(12.0),
                    )
                    .fill(if is_running {
                        COL_RUNNING
                    } else {
                        egui::Color32::from_rgb(60, 60, 72)
                    })
                    .min_size(egui::vec2(80.0, 24.0));

                    if ui
                        .add_enabled(!is_running && self.config.is_some(), btn)
                        .clicked()
                    {
                        run_clicked = Some(cs.def.id);
                    }
                });
            });

        run_clicked
    }

    //  Summary popup window (overlay) 

    fn draw_summary_window(&mut self, ctx: &egui::Context) {
        let pass = self.count(CheckStatus::Pass);
        let fail = self.count(CheckStatus::Fail);
        let skip = self.count(CheckStatus::Skip);
        let total = self.total_results();
        let dur = self.total_duration.as_secs_f64();

        let mut open = true;
        egui::Window::new("Run Complete")
            .open(&mut open)
            .collapsible(false)
            .resizable(true)
            .default_size([620.0, 560.0])
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.add_space(8.0);
                ui.vertical_centered(|ui| {
                    let title = if fail == 0 {
                        "✅ All Checks Passed!"
                    } else {
                        "⚠ Run Complete"
                    };
                    let title_col = if fail == 0 { COL_PASS } else { COL_SKIP };
                    ui.heading(
                        egui::RichText::new(title)
                            .color(title_col)
                            .strong()
                            .size(24.0),
                    );
                    ui.add_space(12.0);

                    // Stat pills
                    ui.horizontal(|ui| {
                        ui.add_space((ui.available_width() - 300.0).max(0.0) / 2.0);
                        self.draw_stat_pill(ui, &pass.to_string(), "PASSED", COL_PASS);
                        ui.add_space(12.0);
                        self.draw_stat_pill(ui, &fail.to_string(), "FAILED", COL_FAIL);
                        ui.add_space(12.0);
                        self.draw_stat_pill(ui, &skip.to_string(), "SKIPPED", COL_SKIP);
                    });

                    ui.add_space(8.0);
                    ui.label(
                        egui::RichText::new(format!("{total} total results  ·  {dur:.1}s"))
                            .color(COL_TEXT_DIM),
                    );
                });

                ui.add_space(8.0);
                ui.separator();
                ui.add_space(8.0);

                // Result list grouped by section
                egui::ScrollArea::vertical()
                    .max_height(350.0)
                    .show(ui, |ui| {
                        let sections = self.sections_ordered();
                        for section in &sections {
                            let checks = self.checks_for_section(*section);
                            let has_results = checks.iter().any(|c| !c.results.is_empty());
                            if !has_results {
                                continue;
                            }

                            ui.add_space(4.0);
                            ui.label(
                                egui::RichText::new(section.label())
                                    .color(COL_TEXT)
                                    .strong()
                                    .size(14.0),
                            );
                            ui.add_space(2.0);

                            for cs in &checks {
                                for r in &cs.results {
                                    let (icon, icon_col) = match r.status {
                                        CheckStatus::Pass => ("✅ PASS", COL_PASS),
                                        CheckStatus::Fail => ("❌ FAIL", COL_FAIL),
                                        CheckStatus::Skip => ("⚠ SKIP", COL_SKIP),
                                        _ => ("——", COL_NOT_RUN),
                                    };

                                    let row_bg = icon_col.gamma_multiply(0.1);
                                    egui::Frame::NONE
                                        .fill(row_bg)
                                        .corner_radius(4.0)
                                        .inner_margin(egui::Margin::symmetric(8, 3))
                                        .show(ui, |ui| {
                                            ui.horizontal(|ui| {
                                                ui.label(
                                                    egui::RichText::new(icon)
                                                        .color(icon_col)
                                                        .strong(),
                                                );
                                                ui.label(
                                                    egui::RichText::new(&r.message)
                                                        .color(COL_TEXT),
                                                );
                                            });
                                        });

                                    if !r.detail.is_empty() {
                                        ui.horizontal(|ui| {
                                            ui.add_space(24.0);
                                            ui.label(
                                                egui::RichText::new(format!("   {}", r.detail))
                                                    .color(COL_TEXT_DIM),
                                            );
                                        });
                                    }
                                }
                            }
                        }
                    });
            });

        if !open {
            self.show_summary = false;
        }
    }

    fn draw_stat_pill(
        &self,
        ui: &mut egui::Ui,
        number: &str,
        label: &str,
        color: egui::Color32,
    ) {
        let (rect, _) = ui.allocate_exact_size(egui::vec2(80.0, 54.0), egui::Sense::hover());
        ui.painter()
            .rect_filled(rect, 8.0, color.gamma_multiply(0.15));
        ui.painter().rect(
            rect,
            8.0,
            egui::Color32::TRANSPARENT,
            egui::Stroke::new(1.0, color.gamma_multiply(0.4)),
            egui::StrokeKind::Outside,
        );

        ui.painter().text(
            rect.center_top() + egui::vec2(0.0, 12.0),
            egui::Align2::CENTER_CENTER,
            number,
            egui::FontId::proportional(22.0),
            color,
        );
        ui.painter().text(
            rect.center_bottom() - egui::vec2(0.0, 12.0),
            egui::Align2::CENTER_CENTER,
            label,
            egui::FontId::proportional(10.0),
            color.gamma_multiply(0.7),
        );
    }
}

//  main 

fn main() -> eframe::Result<()> {
    // Handle --config: dump embedded config to stdout and exit
    if std::env::args().any(|a| a == "--config") {
        print!("{}", AppConfig::EMBEDDED_TOML);
        return Ok(());
    }

    // Build tokio runtime
    let rt = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .expect("Failed to create tokio runtime");

    let handle = rt.handle().clone();

    // Keep runtime alive in a background thread
    let _rt_guard = std::thread::spawn(move || {
        rt.block_on(std::future::pending::<()>());
    });

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1100.0, 680.0])
            .with_min_inner_size([960.0, 560.0])
            .with_title("SELab Opdracht 6 Checker"),
        ..Default::default()
    };

    eframe::run_native(
        "SELab Opdracht 6 Checker",
        options,
        Box::new(move |_cc| Ok(Box::new(App::new(handle)))),
    )
}
