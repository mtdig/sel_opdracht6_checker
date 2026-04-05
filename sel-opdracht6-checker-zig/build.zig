const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── mbedtls (compile from C source) ──
    const mbedtls_dep = b.dependency("mbedtls", .{});
    const mbedtls_lib = b.addLibrary(.{
        .name = "mbedtls",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });

    const mbedtls_include = mbedtls_dep.path("include");
    const mbedtls_library_inc = mbedtls_dep.path("library");
    mbedtls_lib.root_module.addIncludePath(mbedtls_include);
    mbedtls_lib.root_module.addIncludePath(mbedtls_library_inc);

    const mbedtls_sources = [_][]const u8{
        "library/aes.c",        "library/aesce.c",      "library/aesni.c",
        "library/aria.c",       "library/asn1parse.c",  "library/asn1write.c",
        "library/base64.c",     "library/bignum.c",     "library/bignum_core.c",
        "library/bignum_mod.c", "library/bignum_mod_raw.c", "library/block_cipher.c",
        "library/camellia.c",   "library/ccm.c",        "library/chacha20.c",
        "library/chachapoly.c", "library/cipher.c",     "library/cipher_wrap.c",
        "library/cmac.c",       "library/constant_time.c", "library/ctr_drbg.c",
        "library/debug.c",      "library/des.c",        "library/dhm.c",
        "library/ecdh.c",       "library/ecdsa.c",      "library/ecjpake.c",
        "library/ecp.c",        "library/ecp_curves.c", "library/ecp_curves_new.c",
        "library/entropy.c",    "library/entropy_poll.c", "library/error.c",
        "library/gcm.c",        "library/hkdf.c",       "library/hmac_drbg.c",
        "library/lmots.c",      "library/lms.c",        "library/md.c",
        "library/md5.c",        "library/memory_buffer_alloc.c",
        "library/mps_reader.c", "library/mps_trace.c",  "library/net_sockets.c",
        "library/nist_kw.c",    "library/oid.c",        "library/padlock.c",
        "library/pem.c",        "library/pk.c",         "library/pk_ecc.c",
        "library/pk_wrap.c",    "library/pkcs12.c",     "library/pkcs5.c",
        "library/pkcs7.c",      "library/pkparse.c",    "library/pkwrite.c",
        "library/platform.c",   "library/platform_util.c", "library/poly1305.c",
        "library/psa_crypto.c", "library/psa_crypto_aead.c", "library/psa_crypto_cipher.c",
        "library/psa_crypto_client.c", "library/psa_crypto_driver_wrappers_no_static.c",
        "library/psa_crypto_ecp.c", "library/psa_crypto_ffdh.c", "library/psa_crypto_hash.c",
        "library/psa_crypto_mac.c", "library/psa_crypto_pake.c", "library/psa_crypto_rsa.c",
        "library/psa_crypto_se.c", "library/psa_crypto_slot_management.c",
        "library/psa_crypto_storage.c", "library/psa_its_file.c", "library/psa_util.c",
        "library/ripemd160.c",  "library/rsa.c",        "library/rsa_alt_helpers.c",
        "library/sha1.c",       "library/sha256.c",     "library/sha3.c",
        "library/sha512.c",     "library/ssl_cache.c",  "library/ssl_ciphersuites.c",
        "library/ssl_client.c", "library/ssl_cookie.c", "library/ssl_debug_helpers_generated.c",
        "library/ssl_msg.c",    "library/ssl_ticket.c", "library/ssl_tls.c",
        "library/ssl_tls12_client.c", "library/ssl_tls12_server.c",
        "library/ssl_tls13_client.c", "library/ssl_tls13_generic.c",
        "library/ssl_tls13_keys.c",   "library/ssl_tls13_server.c",
        "library/threading.c",  "library/timing.c",     "library/version.c",
        "library/version_features.c",
        "library/x509.c",       "library/x509_create.c", "library/x509_crl.c",
        "library/x509_crt.c",   "library/x509_csr.c",   "library/x509write.c",
        "library/x509write_crt.c", "library/x509write_csr.c",
    };
    for (mbedtls_sources) |src| {
        mbedtls_lib.root_module.addCSourceFile(.{
            .file = mbedtls_dep.path(src),
            .flags = &.{"-fno-sanitize=undefined"},
        });
    }

    // ── libssh2 (compile from C source with mbedtls backend) ──
    const libssh2_dep = b.dependency("libssh2", .{});
    const libssh2_lib = b.addLibrary(.{
        .name = "ssh2",
        .linkage = .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    libssh2_lib.root_module.addIncludePath(mbedtls_include);
    libssh2_lib.root_module.addIncludePath(libssh2_dep.path("include"));
    libssh2_lib.root_module.addIncludePath(libssh2_dep.path("src"));

    const config_wf = b.addWriteFiles();
    _ = config_wf.add("libssh2_config.h",
        \\#ifndef LIBSSH2_CONFIG_H
        \\#define LIBSSH2_CONFIG_H
        \\#define HAVE_UNISTD_H 1
        \\#define HAVE_INTTYPES_H 1
        \\#define HAVE_STDLIB_H 1
        \\#define HAVE_SYS_SELECT_H 1
        \\#define HAVE_SYS_UIO_H 1
        \\#define HAVE_SYS_SOCKET_H 1
        \\#define HAVE_SYS_IOCTL_H 1
        \\#define HAVE_SYS_TIME_H 1
        \\#define HAVE_SYS_UN_H 1
        \\#define HAVE_ARPA_INET_H 1
        \\#define HAVE_NETINET_IN_H 1
        \\#define HAVE_FCNTL_H 1
        \\#define HAVE_ERRNO_H 1
        \\#define HAVE_STDIO_H 1
        \\#define HAVE_STRING_H 1
        \\#define HAVE_STDINT_H 1
        \\#define HAVE_STRTOLL 1
        \\#define HAVE_SNPRINTF 1
        \\#define HAVE_POLL 1
        \\#define HAVE_SELECT 1
        \\#define HAVE_GETTIMEOFDAY 1
        \\#define HAVE_EXPLICIT_BZERO 1
        \\#define HAVE_O_NONBLOCK 1
        \\#define LIBSSH2_MBEDTLS 1
        \\#endif
    );
    const config_dir = config_wf.getDirectory();
    libssh2_lib.root_module.addIncludePath(config_dir);

    const libssh2_flags: []const []const u8 = &.{ "-DLIBSSH2_MBEDTLS", "-DHAVE_CONFIG_H", "-fno-sanitize=undefined" };
    const libssh2_sources = [_][]const u8{
        "src/agent.c",     "src/bcrypt_pbkdf.c", "src/blowfish.c",  "src/chacha.c",
        "src/channel.c",   "src/cipher-chachapoly.c", "src/comp.c", "src/crypt.c",
        "src/crypto.c",    "src/global.c",       "src/hostkey.c",   "src/keepalive.c",
        "src/kex.c",       "src/knownhost.c",    "src/mac.c",       "src/mbedtls.c",
        "src/misc.c",      "src/packet.c",       "src/pem.c",       "src/poly1305.c",
        "src/publickey.c", "src/scp.c",          "src/session.c",   "src/sftp.c",
        "src/transport.c", "src/userauth.c",     "src/userauth_kbd_packet.c", "src/version.c",
    };
    for (libssh2_sources) |src| {
        libssh2_lib.root_module.addCSourceFile(.{
            .file = libssh2_dep.path(src),
            .flags = libssh2_flags,
        });
    }

    // ── Main executable ──
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.linkLibrary(mbedtls_lib);
    exe_mod.linkLibrary(libssh2_lib);

    // SDL2 + SDL2_ttf (system, from nix develop)
    exe_mod.linkSystemLibrary("SDL2", .{});
    exe_mod.linkSystemLibrary("SDL2_ttf", .{});

    // libcurl for HTTP/HTTPS with TLS cert skip
    exe_mod.linkSystemLibrary("curl", .{});

    exe_mod.addIncludePath(mbedtls_include);
    exe_mod.addIncludePath(libssh2_dep.path("include"));
    exe_mod.addIncludePath(config_dir);

    // C bindings shim (avoids @cImport which fails on aarch64 in Zig 0.16-dev)
    exe_mod.addCSourceFile(.{
        .file = b.path("src/c_bindings.c"),
        .flags = &.{"-fno-sanitize=undefined"},
    });

    const exe = b.addExecutable(.{
        .name = "sel-checker",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the checker");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    // Tests
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    test_mod.linkLibrary(mbedtls_lib);
    test_mod.linkLibrary(libssh2_lib);
    test_mod.linkSystemLibrary("SDL2", .{});
    test_mod.linkSystemLibrary("SDL2_ttf", .{});
    test_mod.linkSystemLibrary("curl", .{});
    test_mod.addIncludePath(mbedtls_include);
    test_mod.addIncludePath(libssh2_dep.path("include"));
    test_mod.addIncludePath(config_dir);
    test_mod.addCSourceFile(.{
        .file = b.path("src/c_bindings.c"),
        .flags = &.{"-fno-sanitize=undefined"},
    });

    const exe_tests = b.addTest(.{
        .root_module = test_mod,
    });

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);
}
