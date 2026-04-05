const std = @import("std");
const compat = @import("compat.zig");
const c = @cImport({
    @cInclude("libssh2.h");
    @cInclude("libssh2_sftp.h");
});

pub const SshError = error{
    InitFailed,
    ConnectFailed,
    HandshakeFailed,
    AuthFailed,
    ChannelFailed,
    ExecFailed,
    SftpFailed,
    ReadFailed,
    WriteFailed,
    SocketError,
};

pub const SshSession = struct {
    session: *c.LIBSSH2_SESSION,
    sock: std.posix.socket_t,
    ok: bool = false,

    pub fn connect(host: []const u8, port: u16, user: []const u8, pass: []const u8) SshError!SshSession {
        // Initialize libssh2
        if (c.libssh2_init(0) != 0) return SshError.InitFailed;

        // Create TCP socket
        const addr = std.net.Address.resolveIp(host, port) catch return SshError.ConnectFailed;

        const sock = std.posix.socket(
            addr.any.family,
            std.posix.SOCK.STREAM,
            std.posix.IPPROTO.TCP,
        ) catch return SshError.SocketError;
        errdefer compat.closeSocket(sock);

        // Set a connect timeout via SO_SNDTIMEO
        compat.setSockTimeout(sock, std.posix.SO.SNDTIMEO, 10);
        compat.setSockTimeout(sock, std.posix.SO.RCVTIMEO, 10);

        std.posix.connect(sock, &addr.any, addr.getOsSockLen()) catch return SshError.ConnectFailed;

        // Create session
        const session = c.libssh2_session_init_ex(null, null, null, null) orelse return SshError.InitFailed;
        errdefer _ = c.libssh2_session_free(session);

        c.libssh2_session_set_timeout(session, 15000);

        // libssh2_socket_t is c_ulonglong on Windows but std.posix.socket_t
        // is an opaque pointer – cast via @intFromPtr.  On POSIX both are
        // plain ints so the cast is a no-op widening.
        const raw_sock: c.libssh2_socket_t = if (comptime compat.is_windows)
            @intFromPtr(sock)
        else
            sock;
        if (c.libssh2_session_handshake(session, raw_sock) != 0) return SshError.HandshakeFailed;

        // Password auth
        if (c.libssh2_userauth_password_ex(
            session,
            user.ptr,
            @intCast(user.len),
            pass.ptr,
            @intCast(pass.len),
            null,
        ) != 0) return SshError.AuthFailed;

        return .{ .session = session, .sock = sock, .ok = true };
    }

    /// Execute a command and return stdout as a heap-allocated string.
    pub fn exec(self: *SshSession, alloc: std.mem.Allocator, command: []const u8) ![]const u8 {
        const channel = c.libssh2_channel_open_ex(
            self.session,
            "session",
            7, // strlen("session")
            2 * 1024 * 1024, // LIBSSH2_CHANNEL_WINDOW_DEFAULT
            32768, // LIBSSH2_CHANNEL_PACKET_DEFAULT
            null,
            0,
        ) orelse return SshError.ChannelFailed;
        defer _ = c.libssh2_channel_free(channel);

        if (c.libssh2_channel_process_startup(
            channel,
            "exec",
            4, // strlen("exec")
            command.ptr,
            @intCast(command.len),
        ) != 0) return SshError.ExecFailed;

        var buf: [4096]u8 = undefined;
        var output: std.ArrayListUnmanaged(u8) = .empty;
        errdefer output.deinit(alloc);

        while (true) {
            const n = c.libssh2_channel_read(channel, &buf, buf.len);
            if (n > 0) {
                output.appendSlice(alloc, buf[0..@intCast(n)]) catch return SshError.ReadFailed;
            } else break;
        }

        _ = c.libssh2_channel_close(channel);

        // Trim trailing whitespace
        const result = output.toOwnedSlice(alloc) catch return SshError.ReadFailed;
        return std.mem.trimRight(u8, result, " \t\r\n");
    }

    /// Upload a file via SFTP
    pub fn sftpUpload(self: *SshSession, remote_path: []const u8, data: []const u8) SshError!void {
        const sftp = c.libssh2_sftp_init(self.session) orelse return SshError.SftpFailed;
        defer _ = c.libssh2_sftp_shutdown(sftp);

        const handle = c.libssh2_sftp_open_ex(
            sftp,
            remote_path.ptr,
            @intCast(remote_path.len),
            c.LIBSSH2_FXF_WRITE | c.LIBSSH2_FXF_CREAT | c.LIBSSH2_FXF_TRUNC,
            0o644,
            c.LIBSSH2_SFTP_OPENFILE,
        ) orelse return SshError.SftpFailed;
        defer _ = c.libssh2_sftp_close(handle);

        var written: usize = 0;
        while (written < data.len) {
            const n = c.libssh2_sftp_write(handle, data.ptr + written, data.len - written);
            if (n < 0) return SshError.WriteFailed;
            written += @intCast(n);
        }
    }

    pub fn close(self: *SshSession) void {
        _ = c.libssh2_session_disconnect(self.session, "bye");
        _ = c.libssh2_session_free(self.session);
        compat.closeSocket(self.sock);
        self.ok = false;
    }
};
