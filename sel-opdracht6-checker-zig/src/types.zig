const std = @import("std");

pub const CheckStatus = enum {
    not_run,
    running,
    pass,
    fail,
    skip,

    pub fn isTerminal(self: CheckStatus) bool {
        return self == .pass or self == .fail or self == .skip;
    }

    pub fn label(self: CheckStatus) []const u8 {
        return switch (self) {
            .not_run => "NOT RUN",
            .running => "RUNNING",
            .pass => "PASS",
            .fail => "FAIL",
            .skip => "SKIP",
        };
    }
};

pub const CheckResult = struct {
    status: CheckStatus,
    message: []const u8,
    detail: []const u8,

    pub fn passed(msg: []const u8) CheckResult {
        return .{ .status = .pass, .message = msg, .detail = "" };
    }

    pub fn failed(msg: []const u8, detail: []const u8) CheckResult {
        return .{ .status = .fail, .message = msg, .detail = detail };
    }

    pub fn skipped(msg: []const u8, reason: []const u8) CheckResult {
        return .{ .status = .skip, .message = msg, .detail = reason };
    }
};

pub const Section = enum {
    network,
    ssh,
    apache,
    sftp,
    mysql,
    portainer,
    vaultwarden,
    planka,
    wordpress,
    docker,
    minetest,

    pub fn label(self: Section) []const u8 {
        return switch (self) {
            .network => "Network",
            .ssh => "SSH",
            .apache => "Apache",
            .sftp => "SFTP",
            .mysql => "MySQL",
            .portainer => "Portainer",
            .vaultwarden => "Vaultwarden",
            .planka => "Planka",
            .wordpress => "WordPress",
            .docker => "Docker",
            .minetest => "Minetest",
        };
    }
};

pub const CheckId = enum {
    ping,
    ssh,
    apache,
    sftp,
    docker,
    internet,
    mysql_remote,
    mysql_local,
    mysql_admin,
    portainer,
    vaultwarden,
    planka,
    wp_reachable,
    wp_posts,
    wp_login,
    wp_db,
    minetest,
};

pub const CheckDef = struct {
    id: CheckId,
    name: []const u8,
    section: Section,
    protocol: []const u8,
    port: []const u8,
    depends_on_ssh: bool,
};

pub const all_checks = [_]CheckDef{
    .{ .id = .ping, .name = "VM reachable via ICMP ping", .section = .network, .protocol = "ICMP", .port = "-", .depends_on_ssh = false },
    .{ .id = .ssh, .name = "SSH connection on port 22", .section = .ssh, .protocol = "TCP/SSH", .port = "22", .depends_on_ssh = false },
    .{ .id = .apache, .name = "Apache HTTPS + index.html content", .section = .apache, .protocol = "HTTPS", .port = "443", .depends_on_ssh = false },
    .{ .id = .wp_reachable, .name = "WordPress reachable on port 8080", .section = .wordpress, .protocol = "HTTP", .port = "8080", .depends_on_ssh = false },
    .{ .id = .wp_posts, .name = "WordPress at least 3 posts via REST API", .section = .wordpress, .protocol = "HTTP", .port = "8080", .depends_on_ssh = false },
    .{ .id = .wp_login, .name = "WordPress login via XML-RPC", .section = .wordpress, .protocol = "HTTP", .port = "8080", .depends_on_ssh = false },
    .{ .id = .portainer, .name = "Portainer reachable via HTTPS (port 9443)", .section = .portainer, .protocol = "HTTPS", .port = "9443", .depends_on_ssh = false },
    .{ .id = .vaultwarden, .name = "Vaultwarden reachable via HTTPS (port 4123)", .section = .vaultwarden, .protocol = "HTTPS", .port = "4123", .depends_on_ssh = false },
    .{ .id = .planka, .name = "Planka reachable + login (port 3000)", .section = .planka, .protocol = "HTTP", .port = "3000", .depends_on_ssh = false },
    // SSH-dependent
    .{ .id = .internet, .name = "Internet access from VM (ping 8.8.8.8)", .section = .network, .protocol = "ICMP", .port = "-", .depends_on_ssh = true },
    .{ .id = .sftp, .name = "SFTP upload + HTTPS roundtrip", .section = .sftp, .protocol = "SFTP", .port = "22", .depends_on_ssh = true },
    .{ .id = .mysql_remote, .name = "MySQL remote login on port 3306", .section = .mysql, .protocol = "TCP", .port = "3306", .depends_on_ssh = false },
    .{ .id = .mysql_local, .name = "MySQL local via SSH", .section = .mysql, .protocol = "SSH", .port = "22", .depends_on_ssh = true },
    .{ .id = .mysql_admin, .name = "MySQL admin not reachable remotely", .section = .mysql, .protocol = "SSH", .port = "3306", .depends_on_ssh = true },
    .{ .id = .wp_db, .name = "WordPress database wpdb reachable", .section = .wordpress, .protocol = "SSH", .port = "22", .depends_on_ssh = true },
    .{ .id = .minetest, .name = "Minetest UDP port 30000 open", .section = .minetest, .protocol = "UDP", .port = "30000", .depends_on_ssh = true },
    .{ .id = .docker, .name = "Docker containers, volumes & compose", .section = .docker, .protocol = "SSH", .port = "22", .depends_on_ssh = true },
};

pub const CheckState = struct {
    def: *const CheckDef,
    status: CheckStatus = .not_run,
    results: std.ArrayListUnmanaged(CheckResult) = .empty,
    duration_ms: i64 = 0,
    alloc: std.mem.Allocator,
    mutex: ?*std.Thread.Mutex = null,

    pub fn init(alloc: std.mem.Allocator, def: *const CheckDef) CheckState {
        return .{
            .def = def,
            .alloc = alloc,
        };
    }

    pub fn reset(self: *CheckState) void {
        // Called from main thread before worker starts — no lock needed
        self.results.clearRetainingCapacity();
        self.status = .not_run;
        self.duration_ms = 0;
    }

    pub fn appendResult(self: *CheckState, result: CheckResult) void {
        if (self.mutex) |m| m.lock();
        self.results.append(self.alloc, result) catch {};
        if (self.mutex) |m| m.unlock();
    }

    pub fn deriveOverallStatus(self: *const CheckState) CheckStatus {
        if (self.results.items.len == 0) return .not_run;
        var has_fail = false;
        var all_skip = true;
        for (self.results.items) |r| {
            if (r.status == .fail) has_fail = true;
            if (r.status != .skip) all_skip = false;
        }
        if (has_fail) return .fail;
        if (all_skip) return .skip;
        return .pass;
    }
};

pub const Secrets = struct {
    ssh_user: []const u8 = "",
    ssh_pass: []const u8 = "",
    mysql_remote_user: []const u8 = "",
    mysql_remote_pass: []const u8 = "",
    mysql_local_user: []const u8 = "",
    mysql_local_pass: []const u8 = "",
    wp_user: []const u8 = "",
    wp_pass: []const u8 = "",
};

pub const Config = struct {
    target: []const u8,
    local_user: []const u8,
    secrets: Secrets,
};
