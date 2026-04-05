const std = @import("std");
const types = @import("types.zig");
const compat = @import("compat.zig");

pub const DecryptError = error{
    DataTooShort,
    BadHeader,
    KeyDerivationFailed,
    DecryptionFailed,
    MissingKey,
    OutOfMemory,
};

/// Decrypt OpenSSL AES-256-CBC + PBKDF2 encrypted data via openssl CLI.
/// The returned Secrets contains slices into an internal buffer.
/// Call freeDecryptedBacking(alloc, secrets) when done.
pub fn decryptSecrets(alloc: std.mem.Allocator, passphrase: []const u8) DecryptError!struct { secrets: types.Secrets, backing: []const u8 } {
    const encrypted = @embedFile("secrets.env.enc");
    const plain = decrypt(alloc, encrypted, passphrase) catch return DecryptError.DecryptionFailed;
    const secrets = parseSecrets(alloc, plain);
    return .{ .secrets = secrets, .backing = plain };
}

fn decrypt(alloc: std.mem.Allocator, data: []const u8, passphrase: []const u8) ![]u8 {
    // Write encrypted data to a temp file, invoke openssl to decrypt
    const tmp_dir = compat.tmpDir();
    const tmp_path = try std.fmt.allocPrint(alloc, "{s}{c}.sel-checker-enc.tmp", .{ tmp_dir, std.fs.path.sep });
    defer alloc.free(tmp_path);

    // Write encrypted data
    {
        const f = try std.fs.createFileAbsolute(tmp_path, .{});
        defer f.close();
        try f.writeAll(data);
    }
    defer std.fs.deleteFileAbsolute(tmp_path) catch {};

    // Build pass:XXXX argument
    const pass_arg = try std.fmt.allocPrint(alloc, "pass:{s}", .{passphrase});
    defer alloc.free(pass_arg);

    const result = std.process.Child.run(.{
        .allocator = alloc,
        .argv = &.{
            "openssl",
            "enc",
            "-d",
            "-aes-256-cbc",
            "-pbkdf2",
            "-in",
            tmp_path,
            "-pass",
            pass_arg,
        },
    }) catch return error.DecryptionFailed;
    defer alloc.free(result.stderr);

    if (result.term != .Exited or result.term.Exited != 0) {
        alloc.free(result.stdout);
        return error.DecryptionFailed;
    }

    return result.stdout;
}

fn parseSecrets(alloc: std.mem.Allocator, plain: []const u8) types.Secrets {
    _ = alloc;
    var secrets = types.Secrets{};
    var lines = std.mem.splitScalar(u8, plain, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq| {
            const key = std.mem.trim(u8, trimmed[0..eq], " \t");
            const val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
            if (std.mem.eql(u8, key, "SSH_USER")) {
                secrets.ssh_user = val;
            } else if (std.mem.eql(u8, key, "SSH_PASS")) {
                secrets.ssh_pass = val;
            } else if (std.mem.eql(u8, key, "MYSQL_REMOTE_USER")) {
                secrets.mysql_remote_user = val;
            } else if (std.mem.eql(u8, key, "MYSQL_REMOTE_PASS")) {
                secrets.mysql_remote_pass = val;
            } else if (std.mem.eql(u8, key, "MYSQL_LOCAL_USER")) {
                secrets.mysql_local_user = val;
            } else if (std.mem.eql(u8, key, "MYSQL_LOCAL_PASS")) {
                secrets.mysql_local_pass = val;
            } else if (std.mem.eql(u8, key, "WP_USER")) {
                secrets.wp_user = val;
            } else if (std.mem.eql(u8, key, "WP_PASS")) {
                secrets.wp_pass = val;
            }
        }
    }
    return secrets;
}
