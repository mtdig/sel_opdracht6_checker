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
pub fn getenv(key: []const u8) ?[]const u8 {
    return std.posix.getenv(key);
}

/// Get the system temp directory.
pub fn tmpDir() []const u8 {
    if (is_windows) {
        return getenv("TEMP") orelse getenv("TMP") orelse "C:\\Windows\\Temp";
    } else {
        return "/tmp";
    }
}
