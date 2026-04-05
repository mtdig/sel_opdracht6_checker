const std = @import("std");
const types = @import("types.zig");
const checks_mod = @import("checks.zig");
const crypto = @import("crypto.zig");
const c = @import("c.zig");

const CheckStatus = types.CheckStatus;

// ── Colors (dark theme matching JavaFX version) ──
const Color = c.SDL_Color;

const BG = Color{ .r = 30, .g = 30, .b = 30, .a = 255 };
const PANEL_BG = Color{ .r = 40, .g = 40, .b = 40, .a = 255 };
const CARD_BG = Color{ .r = 50, .g = 50, .b = 50, .a = 255 };
const TEXT_COL = Color{ .r = 220, .g = 220, .b = 220, .a = 255 };
const TEXT_DIM = Color{ .r = 140, .g = 140, .b = 140, .a = 255 };
const ACCENT = Color{ .r = 100, .g = 160, .b = 255, .a = 255 };
const GREEN = Color{ .r = 80, .g = 200, .b = 120, .a = 255 };
const RED = Color{ .r = 220, .g = 80, .b = 80, .a = 255 };
const YELLOW = Color{ .r = 220, .g = 180, .b = 60, .a = 255 };
const ORANGE = Color{ .r = 255, .g = 165, .b = 0, .a = 255 };
const INPUT_BG = Color{ .r = 35, .g = 35, .b = 38, .a = 255 };
const INPUT_BORDER = Color{ .r = 80, .g = 80, .b = 85, .a = 255 };
const INPUT_ACTIVE = Color{ .r = 100, .g = 160, .b = 255, .a = 255 };
const BTN_PRIMARY = Color{ .r = 60, .g = 120, .b = 216, .a = 255 };
const BTN_DANGER = Color{ .r = 180, .g = 50, .b = 50, .a = 255 };

const SIDE_W = 270;
const FONT_SZ = 16;
const TITLE_SZ = 22;
const SMALL_SZ = 13;
const WIN_W = 1100;
const WIN_H = 720;

const View = enum { main, detail, summary };

pub const Gui = struct {
    alloc: std.mem.Allocator,
    states: []types.CheckState,
    config: ?types.Config = null,
    ctx: ?checks_mod.CheckContext = null,

    // SDL
    window: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,
    font: ?*c.TTF_Font = null,
    font_small: ?*c.TTF_Font = null,
    font_title: ?*c.TTF_Font = null,

    // Input buffers
    target_buf: [256]u8 = undefined,
    target_len: usize = 0,
    user_buf: [256]u8 = undefined,
    user_len: usize = 0,
    pass_buf: [256]u8 = undefined,
    pass_len: usize = 0,
    status_msg: [512]u8 = undefined,
    status_len: usize = 0,
    status_ok: bool = false,

    // UI state
    active_input: u8 = 0, // 0=none, 1=target, 2=user, 3=pass
    running: bool = false,
    run_thread: ?std.Thread = null,
    decrypt_backing: ?[]const u8 = null,
    state_mutex: std.Thread.Mutex = .{},
    pending_run_all: bool = false,
    pending_run_single: ?*types.CheckState = null,
    current_view: View = .main,
    detail_section: types.Section = .network,
    scroll_y: i32 = 0,
    total_duration_ms: i64 = 0,
    frame_counter: u32 = 0,
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,
    mouse_clicked: bool = false,

    pub fn init(alloc: std.mem.Allocator) !Gui {
        var states = try alloc.alloc(types.CheckState, types.all_checks.len);
        for (0..types.all_checks.len) |i| {
            states[i] = types.CheckState.init(alloc, &types.all_checks[i]);
        }

        var gui = Gui{
            .alloc = alloc,
            .states = states,
        };

        // Default target
        const default_target = "192.168.56.20";
        @memcpy(gui.target_buf[0..default_target.len], default_target);
        gui.target_len = default_target.len;

        // Default user
        const user = c.sliceFromSentinel(c.sel_getenv("USER")) orelse "student";
        const ulen = @min(user.len, gui.user_buf.len);
        @memcpy(gui.user_buf[0..ulen], user[0..ulen]);
        gui.user_len = ulen;

        return gui;
    }

    pub fn deinit(self: *Gui) void {
        if (self.decrypt_backing) |b| self.alloc.free(b);
        self.alloc.free(self.states);
    }

    pub fn run(self: *Gui) void {
        if (c.SDL_Init(@intCast(c.sel_SDL_INIT_VIDEO())) != 0) {
            std.debug.print("SDL_Init failed: {s}\n", .{c.SDL_GetError()});
            return;
        }
        defer c.SDL_Quit();

        if (c.TTF_Init() != 0) {
            std.debug.print("TTF_Init failed: {s}\n", .{c.TTF_GetError()});
            return;
        }
        defer c.TTF_Quit();

        // Load font: try SEL_FONT_PATH env, then fc-match, then common paths
        const font_path: [*:0]const u8 = blk: {
            // 1. Environment variable (set by nix develop)
            if (c.sel_getenv("SEL_FONT_PATH")) |p| break :blk p;

            // 2. Ask fontconfig at runtime
            if (fcMatch(self.alloc)) |p| break :blk p;

            // 3. Common hardcoded paths
            const fallbacks = [_][*:0]const u8{
                "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
                "/usr/share/fonts/liberation-mono/LiberationMono-Regular.ttf",
                "/usr/share/fonts/truetype/LiberationMono-Regular.ttf",
                "/usr/share/fonts/TTF/LiberationMono-Regular.ttf",
                "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                "/usr/share/fonts/dejavu-sans-mono/DejaVuSansMono.ttf",
                "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
            };
            for (fallbacks) |fp| {
                if (c.TTF_OpenFont(fp, FONT_SZ)) |_| break :blk fp;
            }
            break :blk "/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf";
        };

        self.font = c.TTF_OpenFont(font_path, FONT_SZ);
        if (self.font == null) {
            std.debug.print("TTF_OpenFont failed: {s}\n", .{c.TTF_GetError()});
            std.debug.print("Hint: set SEL_FONT_PATH to a .ttf file, or run inside 'nix develop'\n", .{});
            return;
        }
        self.font_small = c.TTF_OpenFont(font_path, SMALL_SZ) orelse self.font;
        self.font_title = c.TTF_OpenFont(font_path, TITLE_SZ) orelse self.font;

        self.window = c.SDL_CreateWindow(
            "SELab Opdracht 6 Checker",
            c.sel_SDL_WINDOWPOS_CENTERED(),
            c.sel_SDL_WINDOWPOS_CENTERED(),
            WIN_W,
            WIN_H,
            @intCast(c.sel_SDL_WINDOW_SHOWN() | c.sel_SDL_WINDOW_RESIZABLE()),
        );
        if (self.window == null) {
            std.debug.print("SDL_CreateWindow failed: {s}\n", .{c.SDL_GetError()});
            return;
        }
        defer c.SDL_DestroyWindow(self.window);

        self.renderer = c.SDL_CreateRenderer(self.window, -1, @intCast(c.sel_SDL_RENDERER_ACCELERATED() | c.sel_SDL_RENDERER_PRESENTVSYNC()));
        if (self.renderer == null) {
            std.debug.print("SDL_CreateRenderer failed: {s}\n", .{c.SDL_GetError()});
            return;
        }
        defer c.SDL_DestroyRenderer(self.renderer);

        // Enable alpha blending
        _ = c.SDL_SetRenderDrawBlendMode(self.renderer, c.sel_SDL_BLENDMODE_BLEND());

        c.SDL_StartTextInput();

        var quit = false;
        while (!quit) {
            self.mouse_clicked = false;
            var ev: c.SDL_Event = undefined;
            while (c.SDL_PollEvent(&ev) != 0) {
                const evtype = c.sel_event_type(&ev);
                if (evtype == c.sel_SDL_QUIT()) {
                    quit = true;
                } else if (evtype == c.sel_SDL_MOUSEBUTTONDOWN()) {
                    if (c.sel_event_button_button(&ev) == c.sel_SDL_BUTTON_LEFT()) {
                        self.mouse_x = c.sel_event_button_x(&ev);
                        self.mouse_y = c.sel_event_button_y(&ev);
                        self.mouse_clicked = true;
                    }
                } else if (evtype == c.sel_SDL_MOUSEWHEEL()) {
                    self.scroll_y -= c.sel_event_wheel_y(&ev) * 30;
                    if (self.scroll_y < 0) self.scroll_y = 0;
                } else if (evtype == c.sel_SDL_TEXTINPUT()) {
                    if (self.active_input != 0) {
                        const ch = c.sel_event_text_char(&ev);
                        if (ch > 0) {
                            self.appendChar(ch);
                        }
                    }
                } else if (evtype == c.sel_SDL_KEYDOWN()) {
                    self.handleKeyDown(c.sel_event_key_sym(&ev));
                }
            }

            // Lock mutex for reading shared state (results, status)
            self.state_mutex.lock();
            self.update();

            // Render
            setDrawColor(self.renderer.?, BG);
            _ = c.SDL_RenderClear(self.renderer);

            switch (self.current_view) {
                .main => self.drawMain(),
                .detail => self.drawDetail(),
                .summary => self.drawSummary(),
            }

            c.SDL_RenderPresent(self.renderer);
            self.frame_counter +%= 1;
            self.state_mutex.unlock();

            // Process deferred actions OUTSIDE the lock
            if (self.pending_run_all) {
                self.pending_run_all = false;
                self.onRunAll();
            }
            if (self.pending_run_single) |state| {
                self.pending_run_single = null;
                self.runSingle(state);
            }
        }

        c.SDL_StopTextInput();
    }

    fn appendChar(self: *Gui, ch: u8) void {
        switch (self.active_input) {
            1 => if (self.target_len < self.target_buf.len - 1) {
                self.target_buf[self.target_len] = ch;
                self.target_len += 1;
            },
            2 => if (self.user_len < self.user_buf.len - 1) {
                self.user_buf[self.user_len] = ch;
                self.user_len += 1;
            },
            3 => if (self.pass_len < self.pass_buf.len - 1) {
                self.pass_buf[self.pass_len] = ch;
                self.pass_len += 1;
            },
            else => {},
        }
    }

    fn handleKeyDown(self: *Gui, keysym: c_int) void {
        if (self.active_input != 0) {
            if (keysym == c.sel_SDLK_BACKSPACE()) {
                switch (self.active_input) {
                    1 => if (self.target_len > 0) {
                        self.target_len -= 1;
                    },
                    2 => if (self.user_len > 0) {
                        self.user_len -= 1;
                    },
                    3 => if (self.pass_len > 0) {
                        self.pass_len -= 1;
                    },
                    else => {},
                }
            } else if (keysym == c.sel_SDLK_TAB()) {
                self.active_input = if (self.active_input >= 3) 1 else self.active_input + 1;
            } else if (keysym == c.sel_SDLK_RETURN()) {
                self.active_input = 0;
            } else if (keysym == c.sel_SDLK_ESCAPE()) {
                self.active_input = 0;
            }
            return;
        }

        // Non-input keys
        if (keysym == c.sel_SDLK_ESCAPE()) {
            if (self.current_view != .main) {
                self.current_view = .main;
                self.scroll_y = 0;
            }
        }
    }

    fn update(self: *Gui) void {
        if (self.running) {
            var still_running = false;
            for (self.states) |s| {
                if (s.status == .running) {
                    still_running = true;
                    break;
                }
            }
            if (!still_running and !self.hasNotRunChecks()) {
                self.running = false;
                self.current_view = .summary;
            }
        }
    }

    fn hasNotRunChecks(self: *Gui) bool {
        for (self.states) |s| {
            if (s.status == .not_run) return true;
        }
        return false;
    }

    // ── Draw main view ──

    fn drawMain(self: *Gui) void {
        var win_w: c_int = 0;
        var win_h: c_int = 0;
        c.SDL_GetWindowSize(self.window, &win_w, &win_h);

        // Side panel
        fillRect(self.renderer.?, 0, 0, SIDE_W, win_h, PANEL_BG);
        self.drawSidePanel(win_h);

        // Grid area
        const grid_x = SIDE_W + 10;
        const grid_w = win_w - grid_x - 10;
        self.drawGrid(grid_x, 10, grid_w, win_h);

        // Status bar
        fillRect(self.renderer.?, 0, win_h - 28, win_w, 28, PANEL_BG);
        self.drawStatusBar(win_h - 24);
    }

    fn drawSidePanel(self: *Gui, win_h: c_int) void {
        var y: i32 = 15;

        self.renderText("Configuration", 15, y, self.font_title.?, ACCENT);
        y += 30;

        self.renderText("Target (hostname/IP)", 15, y, self.font_small.?, TEXT_DIM);
        y += 18;
        self.drawInput(15, y, SIDE_W - 30, &self.target_buf, &self.target_len, 1, "e.g. 192.168.56.20");
        y += 32;

        self.renderText("Local user", 15, y, self.font_small.?, TEXT_DIM);
        y += 18;
        self.drawInput(15, y, SIDE_W - 30, &self.user_buf, &self.user_len, 2, "student");
        y += 32;

        self.renderText("Decryption passphrase", 15, y, self.font_small.?, TEXT_DIM);
        y += 18;
        self.drawPassInput(15, y, SIDE_W - 30, &self.pass_len, 3);
        y += 26;

        self.renderText("Embedded secrets are decrypted", 15, y, self.font_small.?, TEXT_DIM);
        y += 16;
        self.renderText("at runtime", 15, y, self.font_small.?, TEXT_DIM);
        y += 24;

        // Status message
        if (self.status_len > 0) {
            const col = if (self.status_ok) GREEN else RED;
            self.renderText(self.status_msg[0..self.status_len], 15, y, self.font_small.?, col);
            y += 20;
        }

        // Buttons at bottom
        const btn_y = win_h - 100;
        const btn_label = if (self.running) "Running..." else "Run All";
        if (self.drawButton(15, btn_y, SIDE_W - 30, 32, btn_label, BTN_PRIMARY, self.running)) {
            self.pending_run_all = true;
        }
        if (self.drawButton(15, btn_y + 40, SIDE_W - 30, 32, "Exit", BTN_DANGER, false)) {
            c.sel_push_quit();
        }
    }

    fn drawGrid(self: *Gui, start_x: i32, start_y: i32, total_w: i32, win_h: i32) void {
        const tile_w: i32 = 180;
        const tile_h: i32 = 120;
        const gap: i32 = 10;
        const cols = @max(1, @divTrunc(total_w, tile_w + gap));

        var col: i32 = 0;
        var row: i32 = 0;

        // Iterate over all sections (unique, ordered)
        const all_sections = comptime blk: {
            const fields = @typeInfo(types.Section).@"enum".fields;
            var arr: [fields.len]types.Section = undefined;
            for (fields, 0..) |f, i| {
                arr[i] = @enumFromInt(f.value);
            }
            break :blk arr;
        };

        for (all_sections) |section| {
            // Count checks and compute aggregate status for this section
            var check_count: u32 = 0;
            var has_fail = false;
            var has_running = false;
            var has_skip = false;
            var has_pass = false;
            var all_not_run = true;

            for (self.states) |*state| {
                if (state.def.section == section) {
                    check_count += 1;
                    switch (state.status) {
                        .fail => has_fail = true,
                        .running => has_running = true,
                        .skip => has_skip = true,
                        .pass => has_pass = true,
                        .not_run => {},
                    }
                    if (state.status != .not_run) all_not_run = false;
                }
            }
            if (check_count == 0) continue;

            const agg_status: types.CheckStatus = if (has_fail)
                .fail
            else if (has_running)
                .running
            else if (has_skip)
                .skip
            else if (has_pass and all_not_run == false)
                .pass
            else
                .not_run;

            const tx = start_x + col * (tile_w + gap);
            const ty = start_y + row * (tile_h + gap) - self.scroll_y;

            if (ty > -tile_h and ty < win_h) {
                self.drawSectionTile(tx, ty, tile_w, tile_h, section, check_count, agg_status);
            }

            col += 1;
            if (col >= cols) {
                col = 0;
                row += 1;
            }
        }
    }

    fn drawSectionTile(self: *Gui, x: i32, y: i32, w: i32, h: i32, section: types.Section, check_count: u32, status: types.CheckStatus) void {
        const bg = statusTileColor(status);
        fillRect(self.renderer.?, x, y, w, h, bg);

        // Section name (title)
        self.renderText(section.label(), x + 10, y + 12, self.font.?, TEXT_COL);

        // Check count
        var count_buf: [32]u8 = undefined;
        const count_str = std.fmt.bufPrint(&count_buf, "{d} check{s}", .{ check_count, if (check_count == 1) @as([]const u8, "") else "s" }) catch "?";
        self.renderText(count_str, x + 10, y + 38, self.font_small.?, TEXT_DIM);

        // Aggregate status
        const status_text = status.label();
        const status_col = statusColor(status);
        self.renderText(status_text, x + 10, y + h - 28, self.font_small.?, status_col);

        // Click detection
        if (self.mouse_clicked) {
            if (self.mouse_x >= x and self.mouse_x <= x + w and self.mouse_y >= y and self.mouse_y <= y + h) {
                self.detail_section = section;
                self.current_view = .detail;
                self.scroll_y = 0;
            }
        }
    }

    // ── Detail view ──

    fn drawDetail(self: *Gui) void {
        var win_w: c_int = 0;
        c.SDL_GetWindowSize(self.window, &win_w, null);

        const pad: i32 = 20;
        var y: i32 = pad - self.scroll_y;

        self.renderText(self.detail_section.label(), pad, y, self.font_title.?, ACCENT);
        y += 36;

        if (self.drawButton(pad, y, 80, 26, "< Back", CARD_BG, false)) {
            self.current_view = .main;
            self.scroll_y = 0;
            return;
        }
        y += 36;

        for (self.states) |*state| {
            if (state.def.section != self.detail_section) continue;

            const card_h = measureCardHeight(state);
            const card_w = win_w - pad * 2;

            self.drawCard(pad, y, card_w, card_h, state);
            y += card_h + 10;
        }
    }

    fn measureCardHeight(state: *const types.CheckState) i32 {
        var h: i32 = 70;
        if (state.status == .running) h += 12;
        for (state.results.items) |r| {
            h += 20;
            if (r.detail.len > 0 and state.status != .running) h += 16;
        }
        return h;
    }

    fn drawCard(self: *Gui, x: i32, y: i32, w: i32, h: i32, state: *types.CheckState) void {
        const bg = statusCardColor(state.status);
        fillRect(self.renderer.?, x, y, w, h, bg);

        var cy = y + 8;

        self.renderText(state.def.name, x + 12, cy, self.font.?, TEXT_COL);
        const badge = state.status.label();
        const badge_col = statusColor(state.status);
        self.renderText(badge, x + w - 80, cy, self.font_small.?, badge_col);
        cy += 22;

        var meta_buf: [256]u8 = undefined;
        const meta = std.fmt.bufPrint(&meta_buf, "Protocol: {s}  |  Port: {s}", .{ state.def.protocol, state.def.port }) catch "...";
        self.renderText(meta, x + 12, cy, self.font_small.?, TEXT_DIM);
        cy += 18;

        // Progress bar if running
        if (state.status == .running) {
            const bar_w = w - 24;
            fillRect(self.renderer.?, x + 12, cy, bar_w, 6, PANEL_BG);
            const t: f32 = @floatFromInt(@mod(self.frame_counter, 120));
            const pos: i32 = @intFromFloat(t / 120.0 * @as(f32, @floatFromInt(bar_w)));
            fillRect(self.renderer.?, x + 12 + pos, cy, @min(60, bar_w - pos), 6, ACCENT);
            cy += 12;
        }

        for (state.results.items) |r| {
            const icon = resultIcon(r.status);
            const icon_col = if (state.status == .running) TEXT_DIM else statusColor(r.status);
            self.renderText(icon, x + 12, cy, self.font_small.?, icon_col);
            const msg_col = if (state.status == .running) TEXT_DIM else TEXT_COL;
            self.renderText(r.message, x + 70, cy, self.font_small.?, msg_col);
            cy += 20;

            if (r.detail.len > 0 and state.status != .running) {
                self.renderText(r.detail, x + 82, cy, self.font_small.?, TEXT_DIM);
                cy += 16;
            }
        }

        // Run button
        const btn_y = y + h - 30;
        const is_running = state.status == .running;
        const btn_label = if (is_running) "Running..." else "> Run";
        if (self.drawButton(x + w - 90, btn_y, 78, 24, btn_label, ACCENT, is_running or !self.isConfigured())) {
            self.pending_run_single = state;
        }
    }

    // ── Summary view ──

    fn drawSummary(self: *Gui) void {
        var win_w: c_int = 0;
        c.SDL_GetWindowSize(self.window, &win_w, null);

        const pad: i32 = 30;
        var y: i32 = pad - self.scroll_y;

        const pass_count = self.countByStatus(.pass);
        const fail_count = self.countByStatus(.fail);
        const skip_count = self.countByStatus(.skip);

        const title = if (fail_count == 0) "All Checks Passed!" else "Run Complete";
        const title_col = if (fail_count == 0) GREEN else ORANGE;
        self.renderText(title, pad, y, self.font_title.?, title_col);
        y += 40;

        self.drawStatPill(pad, y, pass_count, "PASSED", GREEN);
        self.drawStatPill(pad + 140, y, fail_count, "FAILED", RED);
        self.drawStatPill(pad + 280, y, skip_count, "SKIPPED", YELLOW);
        y += 60;

        var total_buf: [128]u8 = undefined;
        const total_str = std.fmt.bufPrint(&total_buf, "{d} total results  |  {d}ms", .{
            pass_count + fail_count + skip_count,
            self.total_duration_ms,
        }) catch "...";
        self.renderText(total_str, pad, y, self.font.?, TEXT_DIM);
        y += 30;

        if (self.drawButton(pad, y, 100, 28, "< Back", CARD_BG, false)) {
            self.current_view = .main;
            self.scroll_y = 0;
            return;
        }
        y += 40;

        var prev_section: ?types.Section = null;
        for (self.states) |*state| {
            if (prev_section == null or prev_section.? != state.def.section) {
                self.renderText(state.def.section.label(), pad, y, self.font.?, ACCENT);
                y += 24;
                prev_section = state.def.section;
            }

            for (state.results.items) |r| {
                const icon = resultIcon(r.status);
                const row_bg = resultRowColor(r.status);
                fillRect(self.renderer.?, pad, y, win_w - pad * 2, 22, row_bg);
                self.renderText(icon, pad + 4, y + 2, self.font_small.?, statusColor(r.status));
                self.renderText(r.message, pad + 64, y + 2, self.font_small.?, TEXT_COL);
                y += 24;

                if (r.detail.len > 0) {
                    self.renderText(r.detail, pad + 76, y, self.font_small.?, TEXT_DIM);
                    y += 18;
                }
            }
        }
    }

    fn drawStatPill(self: *Gui, x: i32, y: i32, count: usize, label_text: []const u8, col: Color) void {
        const w: i32 = 120;
        const h: i32 = 50;
        const bg = Color{ .r = col.r / 3, .g = col.g / 3, .b = col.b / 3, .a = 200 };
        fillRect(self.renderer.?, x, y, w, h, bg);
        var num_buf: [16]u8 = undefined;
        const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{count}) catch "?";
        self.renderText(num_str, x + 10, y + 6, self.font_title.?, col);
        self.renderText(label_text, x + 10, y + 30, self.font_small.?, col);
    }

    // ── Helpers ──

    fn drawInput(self: *Gui, x: i32, y: i32, w: i32, buf: *[256]u8, len: *usize, id: u8, placeholder: []const u8) void {
        const active = self.active_input == id;
        fillRect(self.renderer.?, x, y, w, 24, INPUT_BG);
        drawRectOutline(self.renderer.?, x, y, w, 24, if (active) INPUT_ACTIVE else INPUT_BORDER);

        if (len.* > 0) {
            self.renderText(buf[0..len.*], x + 4, y + 4, self.font_small.?, TEXT_COL);
        } else if (!active) {
            self.renderText(placeholder, x + 4, y + 4, self.font_small.?, TEXT_DIM);
        }

        if (active and @mod(self.frame_counter, 60) < 30) {
            const cx = x + 4 + @as(i32, @intCast(len.*)) * 8;
            setDrawColor(self.renderer.?, TEXT_COL);
            _ = c.SDL_RenderDrawLine(self.renderer, cx, y + 4, cx, y + 20);
        }

        if (self.mouse_clicked) {
            if (self.mouse_x >= x and self.mouse_x <= x + w and self.mouse_y >= y and self.mouse_y <= y + 24) {
                self.active_input = id;
            }
        }
    }

    fn drawPassInput(self: *Gui, x: i32, y: i32, w: i32, len: *usize, id: u8) void {
        const active = self.active_input == id;
        fillRect(self.renderer.?, x, y, w, 24, INPUT_BG);
        drawRectOutline(self.renderer.?, x, y, w, 24, if (active) INPUT_ACTIVE else INPUT_BORDER);

        if (len.* > 0) {
            var dots: [256]u8 = undefined;
            const dlen = @min(len.*, dots.len);
            @memset(dots[0..dlen], '*');
            self.renderText(dots[0..dlen], x + 4, y + 4, self.font_small.?, TEXT_COL);
        } else if (!active) {
            self.renderText("passphrase", x + 4, y + 4, self.font_small.?, TEXT_DIM);
        }

        if (active and @mod(self.frame_counter, 60) < 30) {
            const cx = x + 4 + @as(i32, @intCast(len.*)) * 8;
            setDrawColor(self.renderer.?, TEXT_COL);
            _ = c.SDL_RenderDrawLine(self.renderer, cx, y + 4, cx, y + 20);
        }

        if (self.mouse_clicked) {
            if (self.mouse_x >= x and self.mouse_x <= x + w and self.mouse_y >= y and self.mouse_y <= y + 24) {
                self.active_input = id;
            }
        }
    }

    fn drawButton(self: *Gui, x: i32, y: i32, w: i32, h: i32, label_text: []const u8, bg: Color, disabled: bool) bool {
        const col = if (disabled) Color{ .r = bg.r / 2, .g = bg.g / 2, .b = bg.b / 2, .a = 180 } else bg;
        fillRect(self.renderer.?, x, y, w, h, col);
        const text_col = if (disabled) TEXT_DIM else TEXT_COL;
        self.renderText(label_text, x + 10, y + @divTrunc(h - FONT_SZ + 2, 2), self.font_small.?, text_col);

        if (disabled) return false;
        if (self.mouse_clicked) {
            if (self.mouse_x >= x and self.mouse_x <= x + w and self.mouse_y >= y and self.mouse_y <= y + h) {
                return true;
            }
        }
        return false;
    }

    fn drawStatusBar(self: *Gui, y: i32) void {
        const pass_count = self.countByStatus(.pass);
        const fail_count = self.countByStatus(.fail);
        const skip_count = self.countByStatus(.skip);
        const total = pass_count + fail_count + skip_count;

        var buf: [256]u8 = undefined;
        const text = if (total == 0)
            "Ready"
        else
            std.fmt.bufPrint(&buf, "Results: {d} passed, {d} failed, {d} skipped / {d} total", .{
                pass_count, fail_count, skip_count, total,
            }) catch "Ready";

        self.renderText(text, 10, y, self.font_small.?, TEXT_DIM);
    }

    fn countByStatus(self: *Gui, status: CheckStatus) usize {
        var count: usize = 0;
        for (self.states) |s| {
            for (s.results.items) |r| {
                if (r.status == status) count += 1;
            }
        }
        return count;
    }

    fn isConfigured(self: *Gui) bool {
        return self.config != null;
    }

    fn onRunAll(self: *Gui) void {
        if (self.running) return;
        self.active_input = 0;

        if (self.target_len == 0) {
            self.setStatus("Target is required.", false);
            return;
        }
        if (self.pass_len == 0) {
            self.setStatus("Passphrase is required.", false);
            return;
        }

        const dec_result = crypto.decryptSecrets(self.alloc, self.pass_buf[0..self.pass_len]) catch {
            self.setStatus("Decryption failed: wrong passphrase?", false);
            return;
        };
        // NOTE: dec_result.backing must live as long as secrets are used.
        // Store it so it won't be freed prematurely.
        if (self.decrypt_backing) |old| self.alloc.free(old);
        self.decrypt_backing = dec_result.backing;

        self.setStatus("Secrets decrypted OK - running checks...", true);

        self.config = types.Config{
            .target = self.target_buf[0..self.target_len],
            .local_user = self.user_buf[0..self.user_len],
            .secrets = dec_result.secrets,
        };

        for (self.states) |*s| s.reset();
        for (self.states) |*s| s.mutex = &self.state_mutex;
        self.running = true;

        self.run_thread = std.Thread.spawn(.{ .stack_size = 32 * 1024 * 1024 }, runAllThread, .{self}) catch {
            self.setStatus("Failed to spawn check thread", false);
            self.running = false;
            return;
        };
    }

    fn runAllThread(self: *Gui) void {
        var ctx = checks_mod.CheckContext{
            .config = self.config.?,
            .alloc = self.alloc,
        };

        const start = std.time.milliTimestamp();

        // SSH check first
        for (self.states) |*state| {
            if (state.def.id == .ssh) {
                self.state_mutex.lock();
                state.status = .running;
                state.results.clearRetainingCapacity();
                self.state_mutex.unlock();

                checks_mod.runCheck(&ctx, state);

                self.state_mutex.lock();
                state.status = state.deriveOverallStatus();
                self.state_mutex.unlock();
                break;
            }
        }

        // Non-SSH-dependent
        for (self.states) |*state| {
            if (state.def.id == .ssh) continue;
            if (state.def.depends_on_ssh) continue;

            self.state_mutex.lock();
            state.status = .running;
            state.results.clearRetainingCapacity();
            self.state_mutex.unlock();

            checks_mod.runCheck(&ctx, state);

            self.state_mutex.lock();
            state.status = state.deriveOverallStatus();
            self.state_mutex.unlock();
        }

        // SSH-dependent
        for (self.states) |*state| {
            if (state.def.id == .ssh) continue;
            if (!state.def.depends_on_ssh) continue;

            self.state_mutex.lock();
            state.status = .running;
            state.results.clearRetainingCapacity();
            self.state_mutex.unlock();

            checks_mod.runCheck(&ctx, state);

            self.state_mutex.lock();
            state.status = state.deriveOverallStatus();
            self.state_mutex.unlock();
        }

        self.state_mutex.lock();
        self.total_duration_ms = std.time.milliTimestamp() - start;
        self.running = false;
        self.ctx = ctx;
        self.state_mutex.unlock();
    }

    fn runSingle(self: *Gui, state: *types.CheckState) void {
        if (self.config == null) return;
        state.reset();
        state.mutex = &self.state_mutex;
        state.status = .running;
        _ = std.Thread.spawn(.{ .stack_size = 32 * 1024 * 1024 }, runSingleThread, .{ self, state }) catch return;
    }

    fn runSingleThread(self: *Gui, state: *types.CheckState) void {
        var ctx = if (self.ctx) |*existing| existing.* else checks_mod.CheckContext{
            .config = self.config.?,
            .alloc = self.alloc,
        };

        checks_mod.runCheck(&ctx, state);

        self.state_mutex.lock();
        state.status = state.deriveOverallStatus();
        self.state_mutex.unlock();
    }

    fn setStatus(self: *Gui, msg: []const u8, ok: bool) void {
        const len = @min(msg.len, self.status_msg.len);
        @memcpy(self.status_msg[0..len], msg[0..len]);
        self.status_len = len;
        self.status_ok = ok;
    }

    // ── Text rendering via SDL2_ttf ──

    fn renderText(self: *Gui, text: []const u8, x: i32, y: i32, font: *c.TTF_Font, col: Color) void {
        if (text.len == 0) return;
        var buf: [512]u8 = undefined;
        const len = @min(text.len, buf.len - 1);
        @memcpy(buf[0..len], text[0..len]);
        buf[len] = 0;
        const surface = c.sel_TTF_RenderText(font, @ptrCast(&buf), col.r, col.g, col.b, col.a) orelse return;
        defer c.SDL_FreeSurface(surface);
        const texture = c.SDL_CreateTextureFromSurface(self.renderer, surface) orelse return;
        defer c.SDL_DestroyTexture(texture);
        const dst = c.SDL_Rect{ .x = x, .y = y, .w = surface.w, .h = surface.h };
        _ = c.SDL_RenderCopy(self.renderer, texture, null, &dst);
    }
};

// ── Free drawing helpers ──

fn setDrawColor(renderer: *c.SDL_Renderer, col: Color) void {
    _ = c.SDL_SetRenderDrawColor(renderer, col.r, col.g, col.b, col.a);
}

fn fillRect(renderer: *c.SDL_Renderer, x: i32, y: i32, w: i32, h: i32, col: Color) void {
    setDrawColor(renderer, col);
    const rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
    _ = c.SDL_RenderFillRect(renderer, &rect);
}

fn drawRectOutline(renderer: *c.SDL_Renderer, x: i32, y: i32, w: i32, h: i32, col: Color) void {
    setDrawColor(renderer, col);
    const rect = c.SDL_Rect{ .x = x, .y = y, .w = w, .h = h };
    _ = c.SDL_RenderDrawRect(renderer, &rect);
}

fn statusColor(status: CheckStatus) Color {
    return switch (status) {
        .not_run => TEXT_DIM,
        .running => ACCENT,
        .pass => GREEN,
        .fail => RED,
        .skip => YELLOW,
    };
}

fn statusTileColor(status: CheckStatus) Color {
    return switch (status) {
        .not_run => Color{ .r = 55, .g = 55, .b = 60, .a = 255 },
        .running => Color{ .r = 50, .g = 60, .b = 80, .a = 255 },
        .pass => Color{ .r = 35, .g = 70, .b = 50, .a = 255 },
        .fail => Color{ .r = 80, .g = 35, .b = 35, .a = 255 },
        .skip => Color{ .r = 70, .g = 60, .b = 30, .a = 255 },
    };
}

fn statusCardColor(status: CheckStatus) Color {
    return switch (status) {
        .not_run => CARD_BG,
        .running => Color{ .r = 45, .g = 55, .b = 75, .a = 255 },
        .pass => Color{ .r = 35, .g = 60, .b = 45, .a = 255 },
        .fail => Color{ .r = 70, .g = 35, .b = 35, .a = 255 },
        .skip => Color{ .r = 65, .g = 55, .b = 30, .a = 255 },
    };
}

fn resultIcon(status: CheckStatus) []const u8 {
    return switch (status) {
        .pass => "PASS",
        .fail => "FAIL",
        .skip => "SKIP",
        else => " -- ",
    };
}

fn resultRowColor(status: CheckStatus) Color {
    return switch (status) {
        .pass => Color{ .r = 30, .g = 50, .b = 35, .a = 100 },
        .fail => Color{ .r = 60, .g = 25, .b = 25, .a = 100 },
        .skip => Color{ .r = 55, .g = 45, .b = 20, .a = 100 },
        else => Color{ .r = 0, .g = 0, .b = 0, .a = 0 },
    };
}

/// Use fontconfig `fc-match` to discover a monospace font path at runtime.
fn fcMatch(alloc: std.mem.Allocator) ?[*:0]const u8 {
    var buf: [1024]u8 = undefined;
    var out_len: usize = 0;
    const ret = c.sel_run_command("fc-match --format=%{file} monospace", &buf, buf.len, &out_len);
    if (ret != 0 or out_len == 0) return null;

    // Copy to a sentinel-terminated allocation
    const with_sentinel = alloc.allocSentinel(u8, out_len, 0) catch return null;
    @memcpy(with_sentinel[0..out_len], buf[0..out_len]);
    return with_sentinel.ptr;
}
