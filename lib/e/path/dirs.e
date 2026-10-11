// Per-user and per-machine application directories, the way platformdirs lays them out:
// XDG on Linux, `~/Library` on macOS, the known folders on Windows. Like `e.path` this
// asks the host nothing: `dir` takes the platform and the environment values it is to
// apply, so every platform's answer is testable on every host. `env_from_process`
// reads the process environment into an `Env` for the caller that wants the host's own.
// Nothing is created, probed or cached; callers create what they use.
//
// The answers follow platformdirs 4.x: an XDG variable counts only when it is set to an
// absolute path (surrounding blanks trimmed); on Windows the base folders come from the
// environment-variable route (`APPDATA`, `LOCALAPPDATA`, `ALLUSERSPROFILE`,
// `USERPROFILE`), the one platformdirs itself falls back to. Not here: the
// `user-dirs.dirs` file, Homebrew prefixes, a root user's redirect to site directories,
// and the `/run/user/<uid>` fallback (a Linux runtime directory without
// `XDG_RUNTIME_DIR` is `Unset`, because choosing one means probing the filesystem).

use e.mem
use e.os
use e.path
use e.str

type Platform = enum u8 { Linux, MacOs, Windows }

type Kind = enum u8 {
    Data, Config, Cache, State, Log, Runtime,
    SiteData, SiteConfig, SiteCache, SiteState, SiteLog,
    Documents, Downloads, Desktop, Pictures, Videos, Music,
}

type Env = struct {
    home: str,
    user_profile: str,
    app_data: str,
    local_app_data: str,
    all_users_profile: str,
    xdg_data_home: str,
    xdg_config_home: str,
    xdg_cache_home: str,
    xdg_state_home: str,
    xdg_runtime_dir: str,
    xdg_data_dirs: str,
    xdg_config_dirs: str,
    xdg_documents_dir: str,
    xdg_download_dir: str,
    xdg_desktop_dir: str,
    xdg_pictures_dir: str,
    xdg_videos_dir: str,
    xdg_music_dir: str,
}

type App = struct { name: str, author: str, version: str, roaming: bool, opinion: bool, multipath: bool, no_author: bool }

error Invalid
error Unset

// The platformdirs defaults for an application: opinionated (`Cache` and `Logs` folders
// on Windows, `log` on Linux), no author, no version.
fn app_named(name: str) -> App {
    ret App { name: name, author: "", version: "", roaming: false, opinion: true, multipath: false, no_author: false }
}

fn platform_of(style: path.Style) -> Platform {
    if style == .Windows { ret .Windows }
    ret .Linux
}

fn trim(s: str) -> str {
    var start = 0usize
    var end = s.len
    while start < end && (s[start] == 32u8 || s[start] == 9u8 || s[start] == 10u8 || s[start] == 13u8) { start += 1usize }
    while end > start && (s[end - 1usize] == 32u8 || s[end - 1usize] == 9u8 || s[end - 1usize] == 10u8 || s[end - 1usize] == 13u8) { end -= 1usize }
    ret s[start..end]
}

// An XDG value is used only when it is an absolute path.
fn xdg_value(s: str) -> str {
    let t = trim(s)
    if t.len > 0usize && t[0usize] == 47u8 { ret t }
    ret ""
}

// A name that would climb out of its base: a root, a drive, or a `..` component.
fn escapes(name: str) -> bool {
    if name.len == 0usize { ret false }
    if name[0usize] == 47u8 || name[0usize] == 92u8 { ret true }
    if name.len >= 2usize && name[1usize] == 58u8 && ((name[0usize] >= 65u8 && name[0usize] <= 90u8) || (name[0usize] >= 97u8 && name[0usize] <= 122u8)) { ret true }
    var start = 0usize
    var i = 0usize
    while i <= name.len {
        if i == name.len || name[i] == 47u8 || name[i] == 92u8 {
            if i - start == 2usize && name[start] == 46u8 && name[start + 1usize] == 46u8 { ret true }
            start = i + 1usize
        }
        i += 1usize
    }
    ret false
}

// os.path.join of two parts: a separator unless the base already ends in one.
fn join_one(a: *mem.Arena, base: str, part: str, windows: bool) -> (str, err) {
    if base.len == 0usize { ret (part, ok) }
    let last = base[base.len - 1usize]
    var need = true
    if last == 47u8 { need = false }
    if windows && (last == 92u8 || last == 58u8) { need = false }
    if !need {
        let (joined, joined_error) = str.concat(a, base, part)
        ret (joined, joined_error)
    }
    var sep = "/"
    if windows { sep = "\\" }
    let (head, head_error) = str.concat(a, base, sep)
    if head_error != ok { ret ("", head_error) }
    let (joined, joined_error) = str.concat(a, head, part)
    ret (joined, joined_error)
}

// base/name[/version], the Unix and macOS shape.
fn join_app(a: *mem.Arena, base: str, app: App) -> (str, err) {
    if app.name.len == 0usize { ret (base, ok) }
    let (named, named_error) = join_one(a, base, app.name, false)
    if named_error != ok { ret ("", named_error) }
    if app.version.len == 0usize { ret (named, ok) }
    let (versioned, versioned_error) = join_one(a, named, app.version, false)
    ret (versioned, versioned_error)
}

// base\[author\]name\[extra\][version], the Windows shape.
fn windows_parts(a: *mem.Arena, base: str, app: App, extra: str) -> (str, err) {
    if app.name.len == 0usize { ret (base, ok) }
    var current = base
    if !app.no_author {
        var author = app.author
        if author.len == 0usize { author = app.name }
        let (with_author, author_error) = join_one(a, current, author, true)
        if author_error != ok { ret ("", author_error) }
        current = with_author
    }
    let (with_name, name_error) = join_one(a, current, app.name, true)
    if name_error != ok { ret ("", name_error) }
    current = with_name
    if extra.len > 0usize && app.opinion {
        let (with_extra, extra_error) = join_one(a, current, extra, true)
        if extra_error != ok { ret ("", extra_error) }
        current = with_extra
    }
    if app.version.len > 0usize {
        let (with_version, version_error) = join_one(a, current, app.version, true)
        if version_error != ok { ret ("", version_error) }
        current = with_version
    }
    ret (current, ok)
}

fn home_relative(a: *mem.Arena, env: Env, rest: str) -> (str, err) {
    var home = env.home
    while home.len > 0usize && home[home.len - 1usize] == 47u8 { home = home[0usize..home.len - 1usize] }
    if env.home.len == 0usize { ret ("", Unset) }
    let (joined, joined_error) = str.concat(a, home, rest)
    ret (joined, joined_error)
}

// Each absolute entry of a colon-separated list, with the app appended, first one or all.
fn site_list(a: *mem.Arena, list: str, fallback_one: str, fallback_two: str, app: App) -> (str, err) {
    var result = ""
    var count = 0usize
    var at = 0usize
    while at <= list.len {
        var end = at
        while end < list.len && list[end] != 58u8 { end += 1usize }
        let entry = xdg_value(list[at..end])
        if entry.len > 0usize {
            let (full, full_error) = join_app(a, entry, app)
            if full_error != ok { ret ("", full_error) }
            if count == 0usize {
                result = full
            } else if app.multipath {
                let (with_sep, sep_error) = str.concat(a, result, ":")
                if sep_error != ok { ret ("", sep_error) }
                let (more, more_error) = str.concat(a, with_sep, full)
                if more_error != ok { ret ("", more_error) }
                result = more
            }
            count += 1usize
        }
        at = end + 1usize
    }
    if count > 0usize { ret (result, ok) }
    let (first, first_error) = join_app(a, fallback_one, app)
    if first_error != ok { ret ("", first_error) }
    if fallback_two.len == 0usize || !app.multipath { ret (first, ok) }
    let (second, second_error) = join_app(a, fallback_two, app)
    if second_error != ok { ret ("", second_error) }
    let (with_sep, sep_error) = str.concat(a, first, ":")
    if sep_error != ok { ret ("", sep_error) }
    let (both, both_error) = str.concat(a, with_sep, second)
    ret (both, both_error)
}

fn media_name(kind: Kind, mac: bool) -> str {
    if kind == .Documents { ret "/Documents" }
    if kind == .Downloads { ret "/Downloads" }
    if kind == .Desktop { ret "/Desktop" }
    if kind == .Pictures { ret "/Pictures" }
    if kind == .Videos {
        if mac { ret "/Movies" }
        ret "/Videos"
    }
    ret "/Music"
}

fn media_override(env: Env, kind: Kind) -> str {
    if kind == .Documents { ret xdg_value(env.xdg_documents_dir) }
    if kind == .Downloads { ret xdg_value(env.xdg_download_dir) }
    if kind == .Desktop { ret xdg_value(env.xdg_desktop_dir) }
    if kind == .Pictures { ret xdg_value(env.xdg_pictures_dir) }
    if kind == .Videos { ret xdg_value(env.xdg_videos_dir) }
    ret xdg_value(env.xdg_music_dir)
}

// A user base directory: the XDG variable when it is usable, else home plus `fallback`.
fn user_base(a: *mem.Arena, env: Env, variable: str, fallback: str, app: App) -> (str, err) {
    var base = xdg_value(variable)
    if base.len == 0usize {
        let (from_home, home_error) = home_relative(a, env, fallback)
        if home_error != ok { ret ("", home_error) }
        base = from_home
    }
    let (joined, joined_error) = join_app(a, base, app)
    ret (joined, joined_error)
}

fn unix_dir(a: *mem.Arena, mac: bool, env: Env, kind: Kind, app: App) -> (str, err) {
    if kind == .Documents || kind == .Downloads || kind == .Desktop || kind == .Pictures || kind == .Videos || kind == .Music {
        let override = media_override(env, kind)
        if override.len > 0usize { ret (override, ok) }
        let (media, media_error) = home_relative(a, env, media_name(kind, mac))
        ret (media, media_error)
    }
    if kind == .Data {
        var fallback = "/.local/share"
        if mac { fallback = "/Library/Application Support" }
        let (data, data_error) = user_base(a, env, env.xdg_data_home, fallback, app)
        ret (data, data_error)
    }
    if kind == .Config {
        var fallback = "/.config"
        if mac { fallback = "/Library/Application Support" }
        let (config, config_error) = user_base(a, env, env.xdg_config_home, fallback, app)
        ret (config, config_error)
    }
    if kind == .Cache {
        var fallback = "/.cache"
        if mac { fallback = "/Library/Caches" }
        let (cache, cache_error) = user_base(a, env, env.xdg_cache_home, fallback, app)
        ret (cache, cache_error)
    }
    if kind == .State {
        var fallback = "/.local/state"
        if mac { fallback = "/Library/Application Support" }
        let (state, state_error) = user_base(a, env, env.xdg_state_home, fallback, app)
        ret (state, state_error)
    }
    if kind == .Log {
        if mac {
            let (logs, logs_error) = user_base(a, env, "", "/Library/Logs", app)
            ret (logs, logs_error)
        }
        let (state, state_error) = user_base(a, env, env.xdg_state_home, "/.local/state", app)
        if state_error != ok { ret ("", state_error) }
        if !app.opinion { ret (state, ok) }
        let (log, log_error) = join_one(a, state, "log", false)
        ret (log, log_error)
    }
    if kind == .Runtime {
        if xdg_value(env.xdg_runtime_dir).len > 0usize {
            let (runtime, runtime_error) = user_base(a, env, env.xdg_runtime_dir, "", app)
            ret (runtime, runtime_error)
        }
        if !mac { ret ("", Unset) }
        let (temporary, temporary_error) = user_base(a, env, "", "/Library/Caches/TemporaryItems", app)
        ret (temporary, temporary_error)
    }
    if kind == .SiteData {
        if mac {
            let (site, site_error) = site_list(a, env.xdg_data_dirs, "/Library/Application Support", "", app)
            ret (site, site_error)
        }
        let (site, site_error) = site_list(a, env.xdg_data_dirs, "/usr/local/share", "/usr/share", app)
        ret (site, site_error)
    }
    if kind == .SiteConfig {
        if mac {
            let (site, site_error) = site_list(a, env.xdg_config_dirs, "/Library/Application Support", "", app)
            ret (site, site_error)
        }
        let (site, site_error) = site_list(a, env.xdg_config_dirs, "/etc/xdg", "", app)
        ret (site, site_error)
    }
    if kind == .SiteCache {
        var base = "/var/cache"
        if mac { base = "/Library/Caches" }
        let (cache, cache_error) = join_app(a, base, app)
        ret (cache, cache_error)
    }
    if kind == .SiteState {
        var base = "/var/lib"
        if mac { base = "/Library/Application Support" }
        let (state, state_error) = join_app(a, base, app)
        ret (state, state_error)
    }
    var base = "/var/log"
    if mac { base = "/Library/Logs" }
    let (log, log_error) = join_app(a, base, app)
    ret (log, log_error)
}

// ntpath.normpath turns every / into \; e.path keeps a root as written, so do it first.
fn backslashes(a: *mem.Arena, value: str) -> str {
    let (buffer, buffer_error) = mem.alloc[u8](a, value.len)
    if buffer_error != ok { ret value }
    var i = 0usize
    while i < value.len {
        buffer[i] = value[i]
        if value[i] == 47u8 { buffer[i] = 92u8 }
        i += 1usize
    }
    ret buffer[0usize..value.len]
}

fn windows_base(a: *mem.Arena, value: str, rest: str) -> (str, err) {
    if value.len == 0usize { ret ("", Unset) }
    let (clean, clean_error) = path.normalize(a, backslashes(a, value), .Windows)
    if clean_error != ok { ret ("", clean_error) }
    if rest.len == 0usize { ret (clean, ok) }
    let (joined, joined_error) = join_one(a, clean, rest, true)
    ret (joined, joined_error)
}

fn windows_dir(a: *mem.Arena, env: Env, kind: Kind, app: App) -> (str, err) {
    if kind == .Documents || kind == .Downloads || kind == .Desktop || kind == .Pictures || kind == .Videos || kind == .Music {
        var leaf = "Documents"
        if kind == .Downloads { leaf = "Downloads" }
        if kind == .Desktop { leaf = "Desktop" }
        if kind == .Pictures { leaf = "Pictures" }
        if kind == .Videos { leaf = "Videos" }
        if kind == .Music { leaf = "Music" }
        let (media, media_error) = windows_base(a, env.user_profile, leaf)
        ret (media, media_error)
    }
    var value = env.local_app_data
    var extra = ""
    var logs = false
    if kind == .Data || kind == .Config || kind == .State {
        if app.roaming { value = env.app_data }
    } else if kind == .Log {
        if app.roaming { value = env.app_data }
        logs = true
    } else if kind == .Cache {
        extra = "Cache"
    } else if kind == .SiteData || kind == .SiteConfig || kind == .SiteState {
        value = env.all_users_profile
    } else if kind == .SiteCache {
        value = env.all_users_profile
        extra = "Cache"
    } else if kind == .SiteLog {
        value = env.all_users_profile
        logs = true
    }
    var base = ""
    if kind == .Runtime {
        let (temp, temp_error) = windows_base(a, env.local_app_data, "Temp")
        if temp_error != ok { ret ("", temp_error) }
        base = temp
    } else {
        let (clean, clean_error) = windows_base(a, value, "")
        if clean_error != ok { ret ("", clean_error) }
        base = clean
    }
    let (parts, parts_error) = windows_parts(a, base, app, extra)
    if parts_error != ok { ret ("", parts_error) }
    if !logs || !app.opinion { ret (parts, ok) }
    let (with_logs, logs_error) = join_one(a, parts, "Logs", true)
    ret (with_logs, logs_error)
}

fn dir(a: *mem.Arena, platform: Platform, env: Env, kind: Kind, app: App) -> (str, err) {
    if escapes(app.name) || escapes(app.version) || (!app.no_author && escapes(app.author)) { ret ("", Invalid) }
    if platform == .Windows {
        let (windows, windows_error) = windows_dir(a, env, kind, app)
        ret (windows, windows_error)
    }
    let (unix, unix_error) = unix_dir(a, platform == .MacOs, env, kind, app)
    ret (unix, unix_error)
}

fn env_value(a: *mem.Arena, name: str) -> str {
    let (value, value_error) = os.env(a, name)
    if value_error != ok { ret "" }
    ret value
}

fn env_from_process(a: *mem.Arena) -> (Env, err) {
    var e: Env = zero
    e.home = env_value(a, "HOME")
    e.user_profile = env_value(a, "USERPROFILE")
    e.app_data = env_value(a, "APPDATA")
    e.local_app_data = env_value(a, "LOCALAPPDATA")
    e.all_users_profile = env_value(a, "ALLUSERSPROFILE")
    e.xdg_data_home = env_value(a, "XDG_DATA_HOME")
    e.xdg_config_home = env_value(a, "XDG_CONFIG_HOME")
    e.xdg_cache_home = env_value(a, "XDG_CACHE_HOME")
    e.xdg_state_home = env_value(a, "XDG_STATE_HOME")
    e.xdg_runtime_dir = env_value(a, "XDG_RUNTIME_DIR")
    e.xdg_data_dirs = env_value(a, "XDG_DATA_DIRS")
    e.xdg_config_dirs = env_value(a, "XDG_CONFIG_DIRS")
    e.xdg_documents_dir = env_value(a, "XDG_DOCUMENTS_DIR")
    e.xdg_download_dir = env_value(a, "XDG_DOWNLOAD_DIR")
    e.xdg_desktop_dir = env_value(a, "XDG_DESKTOP_DIR")
    e.xdg_pictures_dir = env_value(a, "XDG_PICTURES_DIR")
    e.xdg_videos_dir = env_value(a, "XDG_VIDEOS_DIR")
    e.xdg_music_dir = env_value(a, "XDG_MUSIC_DIR")
    ret (e, ok)
}
