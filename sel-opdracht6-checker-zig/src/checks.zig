const std = @import("std");
const types = @import("types.zig");
const ssh_mod = @import("ssh.zig");
const http = @import("http.zig");
const compat = @import("compat.zig");

const CheckResult = types.CheckResult;
const SshSession = ssh_mod.SshSession;

pub const CheckContext = struct {
    config: types.Config,
    ssh: ?SshSession = null,
    alloc: std.mem.Allocator,

    pub fn apacheUrl(self: *const CheckContext) []const u8 {
        return std.fmt.allocPrint(self.alloc, "https://{s}", .{self.config.target}) catch "https://unknown";
    }

    pub fn wpUrl(self: *const CheckContext) []const u8 {
        return std.fmt.allocPrint(self.alloc, "http://{s}:8080", .{self.config.target}) catch "http://unknown:8080";
    }

    pub fn portainerUrl(self: *const CheckContext) []const u8 {
        return std.fmt.allocPrint(self.alloc, "https://{s}:9443", .{self.config.target}) catch "https://unknown:9443";
    }

    pub fn vaultwardenUrl(self: *const CheckContext) []const u8 {
        return std.fmt.allocPrint(self.alloc, "https://{s}:4123", .{self.config.target}) catch "https://unknown:4123";
    }

    pub fn plankaUrl(self: *const CheckContext) []const u8 {
        return std.fmt.allocPrint(self.alloc, "http://{s}:3000", .{self.config.target}) catch "http://unknown:3000";
    }

    pub fn sshOk(self: *const CheckContext) bool {
        if (self.ssh) |s| return s.ok;
        return false;
    }

    pub fn sshExec(self: *CheckContext, cmd: []const u8) ![]const u8 {
        if (self.ssh) |*s| {
            return s.exec(self.alloc, cmd);
        }
        return error.ChannelFailed;
    }
};

/// Run a check by ID, appending results to the state's result list.
pub fn runCheck(ctx: *CheckContext, state: *types.CheckState) void {
    switch (state.def.id) {
        .ping => checkPing(ctx, state),
        .ssh => checkSsh(ctx, state),
        .apache => checkApache(ctx, state),
        .sftp => checkSftp(ctx, state),
        .docker => checkDocker(ctx, state),
        .internet => checkInternet(ctx, state),
        .mysql_remote => checkMysqlRemote(ctx, state),
        .mysql_local => checkMysqlLocal(ctx, state),
        .mysql_admin => checkMysqlAdmin(ctx, state),
        .portainer => checkPortainer(ctx, state),
        .vaultwarden => checkVaultwarden(ctx, state),
        .planka => checkPlanka(ctx, state),
        .wp_reachable => checkWpReachable(ctx, state),
        .wp_posts => checkWpPosts(ctx, state),
        .wp_login => checkWpLogin(ctx, state),
        .wp_db => checkWpDb(ctx, state),
        .minetest => checkMinetest(ctx, state),
    }
}

fn addResult(state: *types.CheckState, result: CheckResult) void {
    state.appendResult(result);
}

fn requireSsh(ctx: *CheckContext, state: *types.CheckState, name: []const u8) bool {
    if (!ctx.sshOk()) {
        addResult(state, CheckResult.skipped(name, "SSH connection not available"));
        return false;
    }
    return true;
}

// ── Ping ──

fn checkPing(ctx: *CheckContext, state: *types.CheckState) void {
    const target = ctx.config.target;
    // Windows: ping -n 1 -w 5000; POSIX: ping -c 1 -W 5
    const argv: []const []const u8 = if (compat.is_windows)
        &.{ "ping", "-n", "1", "-w", "5000", target }
    else
        &.{ "ping", "-c", "1", "-W", "5", target };
    const result = std.process.Child.run(.{
        .allocator = ctx.alloc,
        .argv = argv,
    }) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "VM is not reachable at {s}", .{target}) catch "Ping failed",
            "Ping error",
        ));
        return;
    };
    defer ctx.alloc.free(result.stdout);
    defer ctx.alloc.free(result.stderr);

    if (result.term == .Exited and result.term.Exited == 0) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "VM is reachable at {s} (ping)", .{target}) catch "Ping OK",
        ));
    } else {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "VM is not reachable at {s}", .{target}) catch "Ping failed",
            "Ping failed - 0 packets received",
        ));
    }
}

// ── SSH ──

fn checkSsh(ctx: *CheckContext, state: *types.CheckState) void {
    const user = ctx.config.secrets.ssh_user;
    ctx.ssh = SshSession.connect(ctx.config.target, 22, user, ctx.config.secrets.ssh_pass) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "SSH connection as {s} on port 22", .{user}) catch "SSH failed",
            std.fmt.allocPrint(ctx.alloc, "Cannot log in with {s}", .{user}) catch "Auth failed",
        ));
        return;
    };

    // Verify with echo
    const out = ctx.sshExec("echo ok") catch {
        addResult(state, CheckResult.failed("SSH session unusable", "echo ok failed"));
        return;
    };
    defer ctx.alloc.free(out);

    if (std.mem.indexOf(u8, out, "ok") != null) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "SSH connection as {s} on port 22", .{user}) catch "SSH OK",
        ));
    } else {
        addResult(state, CheckResult.failed("SSH session verification failed", "echo ok returned unexpected output"));
    }
}

// ── Apache ──

fn checkApache(ctx: *CheckContext, state: *types.CheckState) void {
    const url = ctx.apacheUrl();
    defer ctx.alloc.free(url);

    var resp = http.get(ctx.alloc, url) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "Apache not reachable via HTTPS on {s}", .{url}) catch "Apache unreachable",
            "Connection failed",
        ));
        return;
    };
    defer resp.deinit(ctx.alloc);

    if (resp.status >= 400) {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "Apache not reachable via HTTPS on {s}", .{url}) catch "Apache error",
            std.fmt.allocPrint(ctx.alloc, "HTTP status: {d}", .{resp.status}) catch "Bad status",
        ));
        return;
    }

    addResult(state, CheckResult.passed(
        std.fmt.allocPrint(ctx.alloc, "Apache reachable via HTTPS (HTTP {d})", .{resp.status}) catch "Apache OK",
    ));

    const expected = "Als u dit kan lezen dan is de toegang tot de webpagina correct ingesteld!";
    if (std.mem.indexOf(u8, resp.body, expected) != null) {
        addResult(state, CheckResult.passed("index.html contains expected text"));
    } else {
        addResult(state, CheckResult.failed("index.html does not contain expected text", std.fmt.allocPrint(ctx.alloc, "Expected: '{s}'", .{expected}) catch "Missing text"));
    }
}

// ── SFTP ──

fn checkSftp(ctx: *CheckContext, state: *types.CheckState) void {
    if (!requireSsh(ctx, state, "SFTP upload")) return;

    const remote_path = "/var/www/html/opdracht6.html";
    const user = ctx.config.local_user;
    const html = std.fmt.allocPrint(ctx.alloc,
        \\<!DOCTYPE html>
        \\<html>
        \\    <head><title>Opdracht 6</title></head>
        \\    <body>
        \\        <h1>SELab Opdracht 6</h1>
        \\        <p>Submitted by: {s}</p>
        \\    </body>
        \\</html>
    , .{user}) catch {
        addResult(state, CheckResult.failed("SFTP upload", "Failed to format HTML"));
        return;
    };
    defer ctx.alloc.free(html);

    if (ctx.ssh) |*s| {
        s.sftpUpload(remote_path, html) catch {
            addResult(state, CheckResult.failed("SFTP upload failed", "Could not write file"));
            return;
        };
    } else {
        addResult(state, CheckResult.skipped("SFTP upload", "No SSH session"));
        return;
    }

    addResult(state, CheckResult.passed(
        std.fmt.allocPrint(ctx.alloc, "SFTP upload to {s} as {s}", .{ remote_path, ctx.config.secrets.ssh_user }) catch "SFTP OK",
    ));

    // chmod
    _ = ctx.sshExec(std.fmt.allocPrint(ctx.alloc, "chmod 644 {s}", .{remote_path}) catch "chmod 644 /var/www/html/opdracht6.html") catch {};

    // Roundtrip via HTTPS
    const check_url = std.fmt.allocPrint(ctx.alloc, "{s}/opdracht6.html", .{ctx.apacheUrl()}) catch return;
    defer ctx.alloc.free(check_url);

    var resp = http.get(ctx.alloc, check_url) catch {
        addResult(state, CheckResult.failed("opdracht6.html not reachable via HTTPS", "Connection failed"));
        return;
    };
    defer resp.deinit(ctx.alloc);

    if (resp.status >= 200 and resp.status < 400) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "opdracht6.html reachable via HTTPS (HTTP {d})", .{resp.status}) catch "HTTPS OK",
        ));
        if (std.mem.indexOf(u8, resp.body, user) != null) {
            addResult(state, CheckResult.passed(
                std.fmt.allocPrint(ctx.alloc, "Roundtrip OK: '{s}' found in page", .{user}) catch "Roundtrip OK",
            ));
        } else {
            addResult(state, CheckResult.failed("Roundtrip: username not found in page", "Expected your username in page content"));
        }
    } else {
        addResult(state, CheckResult.failed("opdracht6.html not reachable via HTTPS", std.fmt.allocPrint(ctx.alloc, "HTTP status: {d}", .{resp.status}) catch "Bad status"));
    }
}

// ── Docker ──

fn checkDocker(ctx: *CheckContext, state: *types.CheckState) void {
    if (!requireSsh(ctx, state, "Docker compose check")) return;

    const containers = ctx.sshExec("docker ps --format '{{.Names}}' 2>/dev/null") catch {
        addResult(state, CheckResult.failed("Docker check failed", "SSH command failed"));
        return;
    };
    defer ctx.alloc.free(containers);

    const lower = std.ascii.allocLowerString(ctx.alloc, containers) catch containers;
    defer if (lower.ptr != containers.ptr) ctx.alloc.free(lower);

    for ([_][]const u8{ "vaultwarden", "minetest", "portainer", "planka" }) |svc| {
        if (std.mem.indexOf(u8, lower, svc) != null) {
            addResult(state, CheckResult.passed(
                std.fmt.allocPrint(ctx.alloc, "Container {s} running", .{svc}) catch "Container OK",
            ));
        } else {
            addResult(state, CheckResult.failed(
                std.fmt.allocPrint(ctx.alloc, "Container {s} not running", .{svc}) catch "Container missing",
                "",
            ));
        }
    }

    // Vaultwarden bind mount
    const vw_mount = ctx.sshExec("docker inspect $(docker ps -q --filter name=vaultwarden) --format '{{json .Mounts}}' 2>/dev/null") catch "";
    if (std.mem.indexOf(u8, vw_mount, "\"Type\":\"bind\"") != null) {
        addResult(state, CheckResult.passed("Vaultwarden: local directory (bind mount)"));
    } else {
        addResult(state, CheckResult.failed("Vaultwarden: no bind mount for data", ""));
    }

    // Minetest bind mount
    const mt_mount = ctx.sshExec("docker inspect $(docker ps -q --filter name=minetest) --format '{{json .Mounts}}' 2>/dev/null") catch "";
    if (std.mem.indexOf(u8, mt_mount, "\"Type\":\"bind\"") != null) {
        addResult(state, CheckResult.passed("Minetest: local directory (bind mount)"));
    } else {
        addResult(state, CheckResult.failed("Minetest: no bind mount for data", ""));
    }

    // Portainer volume
    const pt_mount = ctx.sshExec("docker inspect $(docker ps -q --filter name=portainer) --format '{{json .Mounts}}' 2>/dev/null") catch "";
    if (std.mem.indexOf(u8, pt_mount, "\"Type\":\"volume\"") != null) {
        addResult(state, CheckResult.passed("Portainer: Docker volume"));
    } else {
        addResult(state, CheckResult.failed("Portainer: no Docker volume for data", ""));
    }

    // Planka compose
    const compose = ctx.sshExec("test -f ~/docker/planka/docker-compose.yml && echo ok || test -f ~/docker/planka/compose.yml && echo ok || echo nok") catch "";
    if (std.mem.indexOf(u8, compose, "ok") != null) {
        addResult(state, CheckResult.passed("Planka compose in ~/docker/planka/"));
    } else {
        addResult(state, CheckResult.failed("No compose in ~/docker/planka/", "Expected docker-compose.yml or compose.yml"));
    }
}

// ── Internet ──

fn checkInternet(ctx: *CheckContext, state: *types.CheckState) void {
    if (!requireSsh(ctx, state, "Internet check")) return;

    const out = ctx.sshExec("ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 && echo ok || echo nok") catch {
        addResult(state, CheckResult.failed("Internet check failed", "SSH command failed"));
        return;
    };
    defer ctx.alloc.free(out);

    if (std.mem.indexOf(u8, out, "ok") != null) {
        addResult(state, CheckResult.passed("VM has internet access"));
    } else {
        addResult(state, CheckResult.failed("VM has no internet access", "ping 8.8.8.8 from VM failed"));
    }
}

// ── MySQL Remote ──

fn checkMysqlRemote(ctx: *CheckContext, state: *types.CheckState) void {
    const target = ctx.config.target;

    // TCP port check
    const addr = std.net.Address.resolveIp(target, 3306) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "MySQL not reachable on {s}:3306", .{target}) catch "MySQL unreachable",
            "DNS resolution failed",
        ));
        return;
    };

    const sock = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "MySQL not reachable on {s}:3306", .{target}) catch "MySQL unreachable",
            "Socket creation failed",
        ));
        return;
    };
    defer compat.closeSocket(sock);

    compat.setSockTimeout(sock, std.posix.SO.SNDTIMEO, 5);

    std.posix.connect(sock, &addr.any, addr.getOsSockLen()) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "MySQL not reachable on {s}:3306", .{target}) catch "MySQL unreachable",
            "Check if remote access is enabled",
        ));
        return;
    };

    addResult(state, CheckResult.passed(
        std.fmt.allocPrint(ctx.alloc, "MySQL reachable on {s}:3306 as {s}", .{ target, ctx.config.secrets.mysql_remote_user }) catch "MySQL OK",
    ));

    // DB check via SSH
    if (ctx.sshOk()) {
        const cmd = std.fmt.allocPrint(ctx.alloc, "mysql -u {s} -p'{s}' appdb -e 'SELECT 1;' 2>/dev/null", .{
            ctx.config.secrets.mysql_remote_user,
            ctx.config.secrets.mysql_remote_pass,
        }) catch return;
        defer ctx.alloc.free(cmd);

        const out = ctx.sshExec(cmd) catch {
            addResult(state, CheckResult.failed("Database appdb check failed", "SSH command error"));
            return;
        };
        defer ctx.alloc.free(out);

        if (std.mem.indexOf(u8, out, "1") != null) {
            addResult(state, CheckResult.passed(
                std.fmt.allocPrint(ctx.alloc, "Database appdb reachable as {s}", .{ctx.config.secrets.mysql_remote_user}) catch "DB OK",
            ));
        } else {
            addResult(state, CheckResult.failed(
                std.fmt.allocPrint(ctx.alloc, "Database appdb not reachable as {s}", .{ctx.config.secrets.mysql_remote_user}) catch "DB error",
                "Check if database appdb exists and user has access",
            ));
        }
    } else {
        addResult(state, CheckResult.skipped("Database appdb", "No SSH for login validation"));
    }
}

// ── MySQL Local ──

fn checkMysqlLocal(ctx: *CheckContext, state: *types.CheckState) void {
    if (!requireSsh(ctx, state, "MySQL local via SSH")) return;

    const cmd = std.fmt.allocPrint(ctx.alloc, "mysql -u {s} -p'{s}' -e 'SELECT 1;' 2>/dev/null", .{
        ctx.config.secrets.mysql_local_user,
        ctx.config.secrets.mysql_local_pass,
    }) catch return;
    defer ctx.alloc.free(cmd);

    const out = ctx.sshExec(cmd) catch {
        addResult(state, CheckResult.failed("MySQL local check failed", "SSH command error"));
        return;
    };
    defer ctx.alloc.free(out);

    if (std.mem.indexOf(u8, out, "1") != null) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "MySQL locally reachable via SSH as {s}", .{ctx.config.secrets.mysql_local_user}) catch "MySQL local OK",
        ));
    } else {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "MySQL locally not reachable as {s}", .{ctx.config.secrets.mysql_local_user}) catch "MySQL local error",
            "Check if admin user exists with correct privileges",
        ));
    }
}

// ── MySQL Admin ──

fn checkMysqlAdmin(ctx: *CheckContext, state: *types.CheckState) void {
    if (!requireSsh(ctx, state, "MySQL admin remote check")) return;

    const cmd = std.fmt.allocPrint(ctx.alloc, "mysql -h {s} -P 3306 -u {s} -p'{s}' -e 'SELECT 1;' 2>&1", .{
        ctx.config.target,
        ctx.config.secrets.mysql_local_user,
        ctx.config.secrets.mysql_local_pass,
    }) catch return;
    defer ctx.alloc.free(cmd);

    const out = ctx.sshExec(cmd) catch {
        // Connection error means blocked -> pass
        addResult(state, CheckResult.passed("MySQL admin is not reachable remotely (correct)"));
        return;
    };
    defer ctx.alloc.free(out);

    if (std.mem.indexOf(u8, out, "Access denied") != null or
        std.mem.indexOf(u8, out, "ERROR") != null or
        std.mem.indexOf(u8, out, "1") == null)
    {
        addResult(state, CheckResult.passed("MySQL admin is not reachable remotely (correct)"));
    } else {
        addResult(state, CheckResult.failed("MySQL admin is reachable remotely", "Should only be accessible locally"));
    }
}

// ── Portainer ──

fn checkPortainer(ctx: *CheckContext, state: *types.CheckState) void {
    const url = ctx.portainerUrl();
    defer ctx.alloc.free(url);

    var resp = http.get(ctx.alloc, url) catch {
        addResult(state, CheckResult.failed("Portainer not reachable", "Connection failed"));
        return;
    };
    defer resp.deinit(ctx.alloc);

    if (resp.status >= 200 and resp.status < 400) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "Portainer reachable via HTTPS (HTTP {d})", .{resp.status}) catch "Portainer OK",
        ));
    } else {
        addResult(state, CheckResult.failed("Portainer not reachable", std.fmt.allocPrint(ctx.alloc, "HTTP status: {d}", .{resp.status}) catch "Bad status"));
    }
}

// ── Vaultwarden ──

fn checkVaultwarden(ctx: *CheckContext, state: *types.CheckState) void {
    const url = ctx.vaultwardenUrl();
    defer ctx.alloc.free(url);

    var resp = http.get(ctx.alloc, url) catch {
        addResult(state, CheckResult.failed("Vaultwarden not reachable", "Connection failed"));
        return;
    };
    defer resp.deinit(ctx.alloc);

    if (resp.status >= 200 and resp.status < 400) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "Vaultwarden reachable via HTTPS (HTTP {d})", .{resp.status}) catch "Vaultwarden OK",
        ));
    } else {
        addResult(state, CheckResult.failed("Vaultwarden not reachable", std.fmt.allocPrint(ctx.alloc, "HTTP status: {d}", .{resp.status}) catch "Bad status"));
    }
}

// ── Planka ──

fn checkPlanka(ctx: *CheckContext, state: *types.CheckState) void {
    const url = ctx.plankaUrl();
    defer ctx.alloc.free(url);

    var resp = http.get(ctx.alloc, url) catch {
        addResult(state, CheckResult.failed("Planka not reachable", "Connection failed"));
        return;
    };
    defer resp.deinit(ctx.alloc);

    if (resp.status >= 400) {
        addResult(state, CheckResult.failed("Planka not reachable", std.fmt.allocPrint(ctx.alloc, "HTTP status: {d}", .{resp.status}) catch "Bad status"));
        return;
    }

    addResult(state, CheckResult.passed(
        std.fmt.allocPrint(ctx.alloc, "Planka reachable (HTTP {d})", .{resp.status}) catch "Planka OK",
    ));

    // Login
    const login_url = std.fmt.allocPrint(ctx.alloc, "{s}/api/access-tokens", .{url}) catch return;
    defer ctx.alloc.free(login_url);

    const payload = "{\"emailOrUsername\":\"troubleshoot@selab.hogent.be\",\"password\":\"shoot\"}";
    var login_resp = http.post(ctx.alloc, login_url, "application/json", payload) catch {
        addResult(state, CheckResult.failed("Planka login failed", "Connection error"));
        return;
    };
    defer login_resp.deinit(ctx.alloc);

    if (std.mem.indexOf(u8, login_resp.body, "\"item\"") != null) {
        addResult(state, CheckResult.passed("Planka login as troubleshoot@selab.hogent.be"));
    } else {
        addResult(state, CheckResult.failed("Planka login failed", "Check user/password"));
    }
}

// ── WordPress Reachable ──

fn checkWpReachable(ctx: *CheckContext, state: *types.CheckState) void {
    const url = ctx.wpUrl();
    defer ctx.alloc.free(url);

    var resp = http.get(ctx.alloc, url) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "WordPress not reachable on {s}", .{url}) catch "WP unreachable",
            "Connection failed",
        ));
        return;
    };
    defer resp.deinit(ctx.alloc);

    if (resp.status >= 200 and resp.status < 400) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "WordPress reachable on {s} (HTTP {d})", .{ url, resp.status }) catch "WP OK",
        ));
    } else {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "WordPress not reachable on {s}", .{url}) catch "WP error",
            std.fmt.allocPrint(ctx.alloc, "HTTP status: {d}", .{resp.status}) catch "Bad status",
        ));
    }
}

// ── WordPress Posts ──

fn checkWpPosts(ctx: *CheckContext, state: *types.CheckState) void {
    const base = ctx.wpUrl();
    defer ctx.alloc.free(base);
    const url = std.fmt.allocPrint(ctx.alloc, "{s}/?rest_route=/wp/v2/posts", .{base}) catch return;
    defer ctx.alloc.free(url);

    var resp = http.get(ctx.alloc, url) catch {
        addResult(state, CheckResult.failed("WordPress posts retrieval failed", "Connection failed"));
        return;
    };
    defer resp.deinit(ctx.alloc);

    // Count posts by splitting on },{
    var count: usize = 0;
    if (resp.body.len > 0 and resp.body[0] == '[') {
        count = 1;
        var i: usize = 0;
        while (i < resp.body.len) : (i += 1) {
            if (i + 2 < resp.body.len and resp.body[i] == '}' and resp.body[i + 1] == ',' and resp.body[i + 2] == '{') {
                count += 1;
            }
        }
    }

    if (count > 2) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "At least 3 posts ({d} found)", .{count}) catch "Posts OK",
        ));
    } else {
        addResult(state, CheckResult.failed("Not enough posts", std.fmt.allocPrint(ctx.alloc, "Only {d} found, at least 3 expected", .{count}) catch "Too few posts"));
    }
}

// ── WordPress Login ──

fn checkWpLogin(ctx: *CheckContext, state: *types.CheckState) void {
    const base = ctx.wpUrl();
    defer ctx.alloc.free(base);
    const url = std.fmt.allocPrint(ctx.alloc, "{s}/xmlrpc.php", .{base}) catch return;
    defer ctx.alloc.free(url);

    const xml = std.fmt.allocPrint(ctx.alloc,
        \\<?xml version='1.0'?>
        \\<methodCall>
        \\  <methodName>wp.getUsersBlogs</methodName>
        \\  <params>
        \\    <param><value>{s}</value></param>
        \\    <param><value>{s}</value></param>
        \\  </params>
        \\</methodCall>
    , .{ ctx.config.secrets.wp_user, ctx.config.secrets.wp_pass }) catch return;
    defer ctx.alloc.free(xml);

    var resp = http.post(ctx.alloc, url, "text/xml", xml) catch {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "WordPress login as {s} failed", .{ctx.config.secrets.wp_user}) catch "WP login failed",
            "Connection failed",
        ));
        return;
    };
    defer resp.deinit(ctx.alloc);

    if (std.mem.indexOf(u8, resp.body, "blogid") != null) {
        addResult(state, CheckResult.passed(
            std.fmt.allocPrint(ctx.alloc, "WordPress login as {s}", .{ctx.config.secrets.wp_user}) catch "WP login OK",
        ));
    } else {
        addResult(state, CheckResult.failed(
            std.fmt.allocPrint(ctx.alloc, "WordPress login as {s} failed", .{ctx.config.secrets.wp_user}) catch "WP login failed",
            "Check user/password or XML-RPC availability",
        ));
    }
}

// ── WordPress DB ──

fn checkWpDb(ctx: *CheckContext, state: *types.CheckState) void {
    if (!requireSsh(ctx, state, "WordPress database check")) return;

    const cmd = std.fmt.allocPrint(ctx.alloc, "mysql -u {s} -p'{s}' wpdb -e 'SELECT 1;' 2>/dev/null", .{
        ctx.config.secrets.wp_user,
        ctx.config.secrets.wp_pass,
    }) catch return;
    defer ctx.alloc.free(cmd);

    const out = ctx.sshExec(cmd) catch {
        addResult(state, CheckResult.failed("WordPress DB check failed", "SSH command error"));
        return;
    };
    defer ctx.alloc.free(out);

    if (std.mem.indexOf(u8, out, "1") != null) {
        addResult(state, CheckResult.passed("Database wpdb exists and is reachable"));
    } else {
        addResult(state, CheckResult.failed("Database wpdb not reachable", std.fmt.allocPrint(ctx.alloc, "Check if wpdb exists and {s} has access", .{ctx.config.secrets.wp_user}) catch "DB access error"));
    }
}

// ── Minetest ──

fn checkMinetest(ctx: *CheckContext, state: *types.CheckState) void {
    if (!requireSsh(ctx, state, "Minetest check")) return;

    const out = ctx.sshExec("docker ps --filter name=minetest --format '{{.Ports}}' 2>/dev/null") catch {
        addResult(state, CheckResult.failed("Minetest check failed", "SSH command error"));
        return;
    };
    defer ctx.alloc.free(out);

    if (std.mem.indexOf(u8, out, "30000") != null) {
        addResult(state, CheckResult.passed("Minetest container running on UDP port 30000"));
        return;
    }

    // Fallback: check if container is running at all
    const names = ctx.sshExec("docker ps --format '{{.Names}}' 2>/dev/null") catch {
        addResult(state, CheckResult.failed("Minetest container not found on UDP port 30000", "SSH command error"));
        return;
    };
    defer ctx.alloc.free(names);

    const lower = std.ascii.allocLowerString(ctx.alloc, names) catch names;
    defer if (lower.ptr != names.ptr) ctx.alloc.free(lower);

    if (std.mem.indexOf(u8, lower, "minetest") != null) {
        addResult(state, CheckResult.passed("Minetest container running (port not confirmed)"));
    } else {
        addResult(state, CheckResult.failed("Minetest container not found on UDP port 30000", "Check if the Minetest container is running"));
    }
}
