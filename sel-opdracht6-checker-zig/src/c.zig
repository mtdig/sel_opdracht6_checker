/// Zig extern declarations for SDL2, SDL2_ttf, libcurl, and libssh2.
/// Instead of @cImport (which fails on aarch64-linux due to _Float128 + ARM NEON
/// translate-c issues in Zig 0.16-dev), we link a C shim (c_bindings.c) and
/// declare only the symbols we actually use.

// ── Opaque types ──
pub const SDL_Window = opaque {};
pub const SDL_Renderer = opaque {};
pub const SDL_Texture = opaque {};
pub const TTF_Font = opaque {};
pub const CURL = opaque {};
pub const LIBSSH2_SESSION = opaque {};
pub const LIBSSH2_CHANNEL = opaque {};
pub const LIBSSH2_SFTP = opaque {};
pub const LIBSSH2_SFTP_HANDLE = opaque {};

/// SDL_Surface — we only need the w/h fields for texture creation.
pub const SDL_Surface = extern struct {
    flags: u32,
    format: ?*anyopaque,
    w: c_int,
    h: c_int,
    pitch: c_int,
    pixels: ?*anyopaque,
    userdata: ?*anyopaque,
    locked: c_int,
    list_blitmap: ?*anyopaque,
    clip_rect: SDL_Rect,
    blit_map: ?*anyopaque,
    refcount: c_int,
};

pub const SDL_Rect = extern struct {
    x: c_int = 0,
    y: c_int = 0,
    w: c_int = 0,
    h: c_int = 0,
};

pub const SDL_Color = extern struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,
};

/// Opaque event storage — 56 bytes on SDL2 (the union is large).
/// We access fields via our C helper functions instead.
pub const SDL_Event = extern struct {
    data: [56]u8 = [_]u8{0} ** 56,
};

pub const curl_slist = extern struct {
    data: ?[*:0]u8,
    next: ?*curl_slist,
};

// ── SDL2 functions ──
pub extern "SDL2" fn SDL_Init(flags: u32) c_int;
pub extern "SDL2" fn SDL_Quit() void;
pub extern "SDL2" fn SDL_CreateWindow(title: [*:0]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: u32) ?*SDL_Window;
pub extern "SDL2" fn SDL_DestroyWindow(window: ?*SDL_Window) void;
pub extern "SDL2" fn SDL_CreateRenderer(window: ?*SDL_Window, index: c_int, flags: u32) ?*SDL_Renderer;
pub extern "SDL2" fn SDL_DestroyRenderer(renderer: ?*SDL_Renderer) void;
pub extern "SDL2" fn SDL_SetRenderDrawColor(renderer: ?*SDL_Renderer, r: u8, g: u8, b: u8, a: u8) c_int;
pub extern "SDL2" fn SDL_SetRenderDrawBlendMode(renderer: ?*SDL_Renderer, mode: c_int) c_int;
pub extern "SDL2" fn SDL_RenderClear(renderer: ?*SDL_Renderer) c_int;
pub extern "SDL2" fn SDL_RenderPresent(renderer: ?*SDL_Renderer) void;
pub extern "SDL2" fn SDL_RenderFillRect(renderer: ?*SDL_Renderer, rect: ?*const SDL_Rect) c_int;
pub extern "SDL2" fn SDL_RenderDrawRect(renderer: ?*SDL_Renderer, rect: ?*const SDL_Rect) c_int;
pub extern "SDL2" fn SDL_RenderDrawLine(renderer: ?*SDL_Renderer, x1: c_int, y1: c_int, x2: c_int, y2: c_int) c_int;
pub extern "SDL2" fn SDL_RenderCopy(renderer: ?*SDL_Renderer, texture: ?*SDL_Texture, srcrect: ?*const SDL_Rect, dstrect: ?*const SDL_Rect) c_int;
pub extern "SDL2" fn SDL_CreateTextureFromSurface(renderer: ?*SDL_Renderer, surface: ?*SDL_Surface) ?*SDL_Texture;
pub extern "SDL2" fn SDL_DestroyTexture(texture: ?*SDL_Texture) void;
pub extern "SDL2" fn SDL_FreeSurface(surface: ?*SDL_Surface) void;
pub extern "SDL2" fn SDL_PollEvent(event: *SDL_Event) c_int;
pub extern "SDL2" fn SDL_GetError() [*:0]const u8;
pub extern "SDL2" fn SDL_GetWindowSize(window: ?*SDL_Window, w: ?*c_int, h: ?*c_int) void;
pub extern "SDL2" fn SDL_StartTextInput() void;
pub extern "SDL2" fn SDL_StopTextInput() void;

// ── SDL2_ttf functions ──
pub extern "SDL2_ttf" fn TTF_Init() c_int;
pub extern "SDL2_ttf" fn TTF_Quit() void;
pub extern "SDL2_ttf" fn TTF_OpenFont(file: [*:0]const u8, ptsize: c_int) ?*TTF_Font;
pub extern "SDL2_ttf" fn TTF_GetError() [*:0]const u8;

// ── libcurl functions ──
pub extern "curl" fn curl_easy_init() ?*CURL;
pub extern "curl" fn curl_easy_cleanup(handle: ?*CURL) void;
pub extern "curl" fn curl_easy_setopt(handle: ?*CURL, option: c_int, ...) c_int;
pub extern "curl" fn curl_easy_perform(handle: ?*CURL) c_int;
pub extern "curl" fn curl_easy_getinfo(handle: ?*CURL, info: c_int, ...) c_int;
pub extern "curl" fn curl_slist_append(list: ?*curl_slist, data: [*:0]const u8) ?*curl_slist;
pub extern "curl" fn curl_slist_free_all(list: ?*curl_slist) void;

// ── libssh2 functions ──
pub extern "ssh2" fn libssh2_init(flags: c_int) c_int;
pub extern "ssh2" fn libssh2_session_init_ex(alloc_func: ?*anyopaque, free_func: ?*anyopaque, realloc_func: ?*anyopaque, abstract_ptr: ?*anyopaque) ?*LIBSSH2_SESSION;
pub extern "ssh2" fn libssh2_session_free(session: ?*LIBSSH2_SESSION) c_int;
pub extern "ssh2" fn libssh2_session_handshake(session: ?*LIBSSH2_SESSION, sock: c_int) c_int;
pub extern "ssh2" fn libssh2_session_set_timeout(session: ?*LIBSSH2_SESSION, timeout: c_long) void;
pub extern "ssh2" fn libssh2_session_disconnect(session: ?*LIBSSH2_SESSION, description: [*:0]const u8) c_int;
pub extern "ssh2" fn libssh2_userauth_password_ex(session: ?*LIBSSH2_SESSION, username: [*]const u8, username_len: c_uint, password: [*]const u8, password_len: c_uint, passwd_change_cb: ?*anyopaque) c_int;
pub extern "ssh2" fn libssh2_channel_open_ex(session: ?*LIBSSH2_SESSION, channel_type: [*]const u8, channel_type_len: c_uint, window_size: c_uint, packet_size: c_uint, message: ?[*]const u8, message_len: c_uint) ?*LIBSSH2_CHANNEL;
pub extern "ssh2" fn libssh2_channel_process_startup(channel: ?*LIBSSH2_CHANNEL, request: [*]const u8, request_len: c_uint, message: [*]const u8, message_len: c_uint) c_int;
pub extern "ssh2" fn libssh2_channel_read(channel: ?*LIBSSH2_CHANNEL, buf: [*]u8, buflen: usize) isize;
pub extern "ssh2" fn libssh2_channel_close(channel: ?*LIBSSH2_CHANNEL) c_int;
pub extern "ssh2" fn libssh2_channel_free(channel: ?*LIBSSH2_CHANNEL) c_int;
pub extern "ssh2" fn libssh2_sftp_init(session: ?*LIBSSH2_SESSION) ?*LIBSSH2_SFTP;
pub extern "ssh2" fn libssh2_sftp_shutdown(sftp: ?*LIBSSH2_SFTP) c_int;
pub extern "ssh2" fn libssh2_sftp_open_ex(sftp: ?*LIBSSH2_SFTP, filename: [*]const u8, filename_len: c_uint, flags: c_ulong, mode: c_long, open_type: c_int) ?*LIBSSH2_SFTP_HANDLE;
pub extern "ssh2" fn libssh2_sftp_close(handle: ?*LIBSSH2_SFTP_HANDLE) c_int;
pub extern "ssh2" fn libssh2_sftp_write(handle: ?*LIBSSH2_SFTP_HANDLE, buffer: [*]const u8, count: usize) isize;

// ── C shim helpers (from c_bindings.c) ──
pub extern fn sel_event_type(ev: *const SDL_Event) c_int;
pub extern fn sel_event_button_button(ev: *const SDL_Event) c_int;
pub extern fn sel_event_button_x(ev: *const SDL_Event) c_int;
pub extern fn sel_event_button_y(ev: *const SDL_Event) c_int;
pub extern fn sel_event_wheel_y(ev: *const SDL_Event) c_int;
pub extern fn sel_event_text_char(ev: *const SDL_Event) u8;
pub extern fn sel_event_key_sym(ev: *const SDL_Event) c_int;
pub extern fn sel_push_quit() void;

// SDL2 constants (via C shim functions)
pub extern fn sel_SDL_QUIT() c_int;
pub extern fn sel_SDL_MOUSEBUTTONDOWN() c_int;
pub extern fn sel_SDL_MOUSEWHEEL() c_int;
pub extern fn sel_SDL_TEXTINPUT() c_int;
pub extern fn sel_SDL_KEYDOWN() c_int;
pub extern fn sel_SDL_BUTTON_LEFT() c_int;
pub extern fn sel_SDLK_BACKSPACE() c_int;
pub extern fn sel_SDLK_ESCAPE() c_int;
pub extern fn sel_SDLK_RETURN() c_int;
pub extern fn sel_SDLK_TAB() c_int;
pub extern fn sel_SDL_INIT_VIDEO() c_int;
pub extern fn sel_SDL_WINDOWPOS_CENTERED() c_int;
pub extern fn sel_SDL_WINDOW_SHOWN() c_int;
pub extern fn sel_SDL_WINDOW_RESIZABLE() c_int;
pub extern fn sel_SDL_RENDERER_ACCELERATED() c_int;
pub extern fn sel_SDL_RENDERER_PRESENTVSYNC() c_int;
pub extern fn sel_SDL_BLENDMODE_BLEND() c_int;

// TTF rendering via C shim (avoids passing SDL_Color struct across ABI)
pub extern fn sel_TTF_RenderText(font: ?*TTF_Font, text: [*:0]const u8, r: u8, g: u8, b: u8, a: u8) ?*SDL_Surface;

// curl constants (via C shim)
pub extern fn sel_CURLOPT_URL() c_int;
pub extern fn sel_CURLOPT_SSL_VERIFYPEER() c_int;
pub extern fn sel_CURLOPT_SSL_VERIFYHOST() c_int;
pub extern fn sel_CURLOPT_FOLLOWLOCATION() c_int;
pub extern fn sel_CURLOPT_MAXREDIRS() c_int;
pub extern fn sel_CURLOPT_TIMEOUT() c_int;
pub extern fn sel_CURLOPT_CONNECTTIMEOUT() c_int;
pub extern fn sel_CURLOPT_POST() c_int;
pub extern fn sel_CURLOPT_CUSTOMREQUEST() c_int;
pub extern fn sel_CURLOPT_HTTPHEADER() c_int;
pub extern fn sel_CURLOPT_POSTFIELDSIZE() c_int;
pub extern fn sel_CURLOPT_POSTFIELDS() c_int;
pub extern fn sel_CURLOPT_WRITEFUNCTION() c_int;
pub extern fn sel_CURLOPT_WRITEDATA() c_int;
pub extern fn sel_CURLE_OK() c_int;
pub extern fn sel_CURLE_OPERATION_TIMEDOUT() c_int;
pub extern fn sel_CURLINFO_RESPONSE_CODE() c_int;

// libssh2 constants (via C shim)
pub extern fn sel_LIBSSH2_FXF_WRITE() c_int;
pub extern fn sel_LIBSSH2_FXF_CREAT() c_int;
pub extern fn sel_LIBSSH2_FXF_TRUNC() c_int;
pub extern fn sel_LIBSSH2_SFTP_OPENFILE() c_int;

// Env var access (replaces std.posix.getenv removed in 0.16)
pub extern fn sel_getenv(name: [*:0]const u8) ?[*:0]const u8;

// File operations (replaces std.fs.createFileAbsolute removed in 0.16)
pub extern fn sel_write_file(path: [*:0]const u8, data: [*]const u8, len: usize) c_int;
pub extern fn sel_delete_file(path: [*:0]const u8) c_int;

// Command execution (replaces std.process.Child.run removed in 0.16)
pub extern fn sel_run_command(cmd: [*:0]const u8, buf: [*]u8, buf_size: usize, out_len: *usize) c_int;

/// Helper to convert a sentinel-terminated optional to a Zig slice.
pub fn sliceFromSentinel(ptr: ?[*:0]const u8) ?[]const u8 {
    const p = ptr orelse return null;
    var len: usize = 0;
    while (p[len] != 0) : (len += 1) {}
    return p[0..len];
}
