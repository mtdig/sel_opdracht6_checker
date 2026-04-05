const std = @import("std");

const c = @cImport({
    @cInclude("curl/curl.h");
});

pub const HttpError = error{
    ConnectionFailed,
    RequestFailed,
    TlsError,
    Timeout,
    OutOfMemory,
    InvalidUri,
};

pub const HttpResponse = struct {
    status: u16,
    body: []const u8,

    pub fn deinit(self: *HttpResponse, alloc: std.mem.Allocator) void {
        if (self.body.len > 0) alloc.free(self.body);
    }
};

/// Callback context passed to CURLOPT_WRITEFUNCTION.
const WriteCtx = struct {
    alloc: std.mem.Allocator,
    buf: []u8,
    len: usize,
    oom: bool,
};

/// libcurl write callback — appends received data to a growable buffer.
fn writeCallback(
    data: [*c]u8,
    size: usize,
    nmemb: usize,
    userp: ?*anyopaque,
) callconv(.c) usize {
    const total = size * nmemb;
    if (total == 0) return 0;

    const ctx: *WriteCtx = @ptrCast(@alignCast(userp));
    if (ctx.oom) return 0;

    // Grow buffer if needed
    const needed = ctx.len + total;
    if (needed > ctx.buf.len) {
        var new_cap = if (ctx.buf.len == 0) @as(usize, 4096) else ctx.buf.len;
        while (new_cap < needed) new_cap *= 2;
        const new_buf = ctx.alloc.realloc(ctx.buf, new_cap) catch {
            ctx.oom = true;
            return 0;
        };
        ctx.buf = new_buf;
    }

    @memcpy(ctx.buf[ctx.len..][0..total], data[0..total]);
    ctx.len += total;
    return total;
}

pub fn get(alloc: std.mem.Allocator, url: []const u8) HttpError!HttpResponse {
    return curlRequest(alloc, url, "GET", null, null);
}

pub fn post(alloc: std.mem.Allocator, url: []const u8, content_type: []const u8, body: []const u8) HttpError!HttpResponse {
    return curlRequest(alloc, url, "POST", content_type, body);
}

fn curlRequest(
    alloc: std.mem.Allocator,
    url: []const u8,
    method: []const u8,
    content_type: ?[]const u8,
    body: ?[]const u8,
) HttpError!HttpResponse {
    const handle = c.curl_easy_init() orelse return HttpError.ConnectionFailed;
    defer c.curl_easy_cleanup(handle);

    // URL (must be null-terminated)
    const url_z = alloc.dupeZ(u8, url) catch return HttpError.OutOfMemory;
    defer alloc.free(url_z);

    _ = c.curl_easy_setopt(handle, c.CURLOPT_URL, url_z.ptr);

    // Disable TLS certificate verification (self-signed certs)
    _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYPEER, @as(c_long, 0));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_SSL_VERIFYHOST, @as(c_long, 0));

    // Follow redirects (up to 5)
    _ = c.curl_easy_setopt(handle, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_MAXREDIRS, @as(c_long, 5));

    // Timeout
    _ = c.curl_easy_setopt(handle, c.CURLOPT_TIMEOUT, @as(c_long, 15));
    _ = c.curl_easy_setopt(handle, c.CURLOPT_CONNECTTIMEOUT, @as(c_long, 10));

    // Method
    if (std.mem.eql(u8, method, "POST")) {
        _ = c.curl_easy_setopt(handle, c.CURLOPT_POST, @as(c_long, 1));
    } else if (!std.mem.eql(u8, method, "GET")) {
        const method_z = alloc.dupeZ(u8, method) catch return HttpError.OutOfMemory;
        defer alloc.free(method_z);
        _ = c.curl_easy_setopt(handle, c.CURLOPT_CUSTOMREQUEST, method_z.ptr);
    }

    // Headers
    var headers_list: [*c]c.struct_curl_slist = null;
    defer if (headers_list != null) c.curl_slist_free_all(headers_list);

    if (content_type) |ct| {
        const hdr = std.fmt.allocPrint(alloc, "Content-Type: {s}\x00", .{ct}) catch return HttpError.OutOfMemory;
        defer alloc.free(hdr);
        headers_list = c.curl_slist_append(headers_list, hdr.ptr);
        _ = c.curl_easy_setopt(handle, c.CURLOPT_HTTPHEADER, headers_list);
    }

    // POST body
    if (body) |b| {
        _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDSIZE, @as(c_long, @intCast(b.len)));
        _ = c.curl_easy_setopt(handle, c.CURLOPT_POSTFIELDS, b.ptr);
    }

    // Write callback
    var ctx = WriteCtx{
        .alloc = alloc,
        .buf = alloc.alloc(u8, 4096) catch return HttpError.OutOfMemory,
        .len = 0,
        .oom = false,
    };
    errdefer alloc.free(ctx.buf);

    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEFUNCTION, &writeCallback);
    _ = c.curl_easy_setopt(handle, c.CURLOPT_WRITEDATA, &ctx);

    // Perform
    const res = c.curl_easy_perform(handle);
    if (ctx.oom) return HttpError.OutOfMemory;
    if (res != c.CURLE_OK) {
        if (res == c.CURLE_OPERATION_TIMEDOUT) return HttpError.Timeout;
        return HttpError.ConnectionFailed;
    }

    // Get status code
    var status_code: c_long = 0;
    _ = c.curl_easy_getinfo(handle, c.CURLINFO_RESPONSE_CODE, &status_code);

    // Shrink buffer to actual size
    const final_body = if (ctx.len == 0) blk: {
        alloc.free(ctx.buf);
        break :blk &[_]u8{};
    } else blk: {
        const shrunk = alloc.realloc(ctx.buf, ctx.len) catch ctx.buf;
        break :blk shrunk[0..ctx.len];
    };

    return HttpResponse{
        .status = @intCast(status_code),
        .body = final_body,
    };
}
