/* c_bindings.c — Thin C wrappers to avoid Zig translate-c issues on aarch64.
 * We compile this as a C file and link it. The Zig code uses extern decls. */
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <curl/curl.h>
#include <libssh2.h>
#include <libssh2_sftp.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

/* ── SDL2 event helpers ──
 * SDL_Event is a large union that's hard to replicate in Zig extern decls.
 * We provide accessor functions instead. */

int sel_event_type(const SDL_Event *ev) { return ev->type; }

/* Mouse button event */
int sel_event_button_button(const SDL_Event *ev) { return ev->button.button; }
int sel_event_button_x(const SDL_Event *ev) { return ev->button.x; }
int sel_event_button_y(const SDL_Event *ev) { return ev->button.y; }

/* Mouse wheel event */
int sel_event_wheel_y(const SDL_Event *ev) { return ev->wheel.y; }

/* Text input event */
char sel_event_text_char(const SDL_Event *ev) { return ev->text.text[0]; }

/* Keyboard event */
int sel_event_key_sym(const SDL_Event *ev) { return ev->key.keysym.sym; }

/* Push a quit event */
void sel_push_quit(void) {
    SDL_Event ev;
    memset(&ev, 0, sizeof(ev));
    ev.type = SDL_QUIT;
    SDL_PushEvent(&ev);
}

/* ── SDL2 constants ── */
int sel_SDL_QUIT(void) { return SDL_QUIT; }
int sel_SDL_MOUSEBUTTONDOWN(void) { return SDL_MOUSEBUTTONDOWN; }
int sel_SDL_MOUSEWHEEL(void) { return SDL_MOUSEWHEEL; }
int sel_SDL_TEXTINPUT(void) { return SDL_TEXTINPUT; }
int sel_SDL_KEYDOWN(void) { return SDL_KEYDOWN; }
int sel_SDL_BUTTON_LEFT(void) { return SDL_BUTTON_LEFT; }
int sel_SDLK_BACKSPACE(void) { return SDLK_BACKSPACE; }
int sel_SDLK_ESCAPE(void) { return SDLK_ESCAPE; }
int sel_SDLK_RETURN(void) { return SDLK_RETURN; }
int sel_SDLK_TAB(void) { return SDLK_TAB; }
int sel_SDL_INIT_VIDEO(void) { return SDL_INIT_VIDEO; }
int sel_SDL_WINDOWPOS_CENTERED(void) { return SDL_WINDOWPOS_CENTERED; }
int sel_SDL_WINDOW_SHOWN(void) { return SDL_WINDOW_SHOWN; }
int sel_SDL_WINDOW_RESIZABLE(void) { return SDL_WINDOW_RESIZABLE; }
int sel_SDL_RENDERER_ACCELERATED(void) { return SDL_RENDERER_ACCELERATED; }
int sel_SDL_RENDERER_PRESENTVSYNC(void) { return SDL_RENDERER_PRESENTVSYNC; }
int sel_SDL_BLENDMODE_BLEND(void) { return SDL_BLENDMODE_BLEND; }

/* ── TTF_RenderText wrapper (takes separate RGBA instead of SDL_Color struct) ── */
SDL_Surface *sel_TTF_RenderText(TTF_Font *font, const char *text,
                                  unsigned char r, unsigned char g,
                                  unsigned char b, unsigned char a) {
    SDL_Color col = {r, g, b, a};
    return TTF_RenderText_Blended(font, text, col);
}

/* ── libcurl constants ── */
int sel_CURLOPT_URL(void) { return CURLOPT_URL; }
int sel_CURLOPT_SSL_VERIFYPEER(void) { return CURLOPT_SSL_VERIFYPEER; }
int sel_CURLOPT_SSL_VERIFYHOST(void) { return CURLOPT_SSL_VERIFYHOST; }
int sel_CURLOPT_FOLLOWLOCATION(void) { return CURLOPT_FOLLOWLOCATION; }
int sel_CURLOPT_MAXREDIRS(void) { return CURLOPT_MAXREDIRS; }
int sel_CURLOPT_TIMEOUT(void) { return CURLOPT_TIMEOUT; }
int sel_CURLOPT_CONNECTTIMEOUT(void) { return CURLOPT_CONNECTTIMEOUT; }
int sel_CURLOPT_POST(void) { return CURLOPT_POST; }
int sel_CURLOPT_CUSTOMREQUEST(void) { return CURLOPT_CUSTOMREQUEST; }
int sel_CURLOPT_HTTPHEADER(void) { return CURLOPT_HTTPHEADER; }
int sel_CURLOPT_POSTFIELDSIZE(void) { return CURLOPT_POSTFIELDSIZE; }
int sel_CURLOPT_POSTFIELDS(void) { return CURLOPT_POSTFIELDS; }
int sel_CURLOPT_WRITEFUNCTION(void) { return CURLOPT_WRITEFUNCTION; }
int sel_CURLOPT_WRITEDATA(void) { return CURLOPT_WRITEDATA; }
int sel_CURLE_OK(void) { return CURLE_OK; }
int sel_CURLE_OPERATION_TIMEDOUT(void) { return CURLE_OPERATION_TIMEDOUT; }
int sel_CURLINFO_RESPONSE_CODE(void) { return CURLINFO_RESPONSE_CODE; }

/* ── libssh2 constants ── */
int sel_LIBSSH2_FXF_WRITE(void) { return LIBSSH2_FXF_WRITE; }
int sel_LIBSSH2_FXF_CREAT(void) { return LIBSSH2_FXF_CREAT; }
int sel_LIBSSH2_FXF_TRUNC(void) { return LIBSSH2_FXF_TRUNC; }
int sel_LIBSSH2_SFTP_OPENFILE(void) { return LIBSSH2_SFTP_OPENFILE; }

/* ── Env var access (std.posix.getenv removed in 0.16) ── */
const char *sel_getenv(const char *name) { return getenv(name); }

/* ── Simple file write (std.fs.createFileAbsolute removed in 0.16) ── */
int sel_write_file(const char *path, const void *data, size_t len) {
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    size_t written = fwrite(data, 1, len, f);
    fclose(f);
    return (written == len) ? 0 : -1;
}

int sel_delete_file(const char *path) {
    return remove(path);
}

/* ── Simple command execution (replaces std.process.Child.run in 0.16) ── */
/* Returns exit code, writes stdout to buf, sets *out_len to bytes written */
int sel_run_command(const char *cmd, char *buf, size_t buf_size, size_t *out_len) {
    *out_len = 0;
    FILE *fp = popen(cmd, "r");
    if (!fp) return -1;
    
    size_t total = 0;
    while (total < buf_size - 1) {
        size_t n = fread(buf + total, 1, buf_size - 1 - total, fp);
        if (n == 0) break;
        total += n;
    }
    buf[total] = '\0';
    *out_len = total;
    
    int status = pclose(fp);
    /* WEXITSTATUS on Linux */
    if (status == -1) return -1;
    return (status >> 8) & 0xFF;
}
