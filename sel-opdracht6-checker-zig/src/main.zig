const std = @import("std");
const gui_mod = @import("gui.zig");
const crypto = @import("crypto.zig");

pub fn main(init: std.process.Init.Minimal) !void {
    // Use the C allocator to avoid debug allocator canary corruption
    // from C libraries (SDL2, libssh2, mbedtls) that may write past
    // buffer boundaries into GPA metadata pages.
    const alloc = std.heap.c_allocator;

    // CLI test mode: pass --test-decrypt <passphrase> to test crypto
    var args_it: std.process.Args.Iterator = .init(init.args);
    _ = args_it.skip(); // skip argv[0]
    if (args_it.next()) |arg1| {
        if (std.mem.eql(u8, arg1, "--test-decrypt")) {
            if (args_it.next()) |pass| {
                std.debug.print("Testing decryption with passphrase: '{s}' (len={d})\n", .{ pass, pass.len });
                const result = crypto.decryptSecrets(alloc, pass) catch |err| {
                    std.debug.print("Decryption FAILED: {}\n", .{err});
                    return;
                };
                defer alloc.free(result.backing);
                std.debug.print("Decryption OK!\n", .{});
                std.debug.print("  SSH_USER={s}\n", .{result.secrets.ssh_user});
                std.debug.print("  SSH_PASS={s}\n", .{result.secrets.ssh_pass});
                return;
            }
        }
    }

    var g = try gui_mod.Gui.init(alloc);
    defer g.deinit();
    g.run();
}
