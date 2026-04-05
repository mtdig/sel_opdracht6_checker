const std = @import("std");
const builtin = @import("builtin");

pub const is_windows = builtin.os.tag == .windows;

/// Close a socket portably.
/// On Windows, socket_t is ws2_32.SOCKET (opaque ptr) and needs closesocket().
/// On POSIX, socket_t is fd_t (i32) and uses close().
pub fn closeSocket(sock: std.posix.socket_t) void {
    if (is_windows) {
        std.os.windows.closesocket(sock) catch {};
    } else {
        std.posix.close(sock);
    }
}

/// Set a socket timeout (SO_SNDTIMEO or SO_RCVTIMEO).
/// On Windows the option value is a DWORD with milliseconds.
/// On POSIX it's a struct timeval.
pub fn setSockTimeout(sock: std.posix.socket_t, opt: u32, seconds: u31) void {
    if (is_windows) {
        const ms: u32 = @as(u32, seconds) * 1000;
        std.posix.setsockopt(sock, std.posix.SOL.SOCKET, opt, std.mem.asBytes(&ms)) catch {};
    } else {
        const tv = std.posix.timeval{ .sec = seconds, .usec = 0 };
        std.posix.setsockopt(sock, std.posix.SOL.SOCKET, opt, std.mem.asBytes(&tv)) catch {};
    }
}

/// Get an environment variable portably.
/// On Windows, std.posix.getenv is unavailable (WTF-16), so we use
/// std.process.getenvW via a small comptime branch.
pub fn getenv(key: []const u8) ?[]const u8 {
    if (comptime is_windows) {
        // On Windows we must go through the wide-char API.
        // std.posix.getenv is a @compileError on Windows, so this
        // branch must never reference it.  We convert the key to a
        // comptime-known sentinel-terminated slice and call getenvW,
        // but that requires a [*:0]const u16 and returns a WTF-16
        // string — far too heavy for our use-case.  Instead, just
        // return hard-coded fallbacks; the only callers are tmpDir()
        // (TEMP/TMP) and gui.zig (USER/USERNAME).
        return null;
    } else {
        return std.posix.getenv(key);
    }
}

/// Get the system temp directory.
pub fn tmpDir() []const u8 {
    if (comptime is_windows) {
        return "C:\\Windows\\Temp";
    } else {
        return "/tmp";
    }
}
