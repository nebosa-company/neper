// The browser shell's model: the omnibox rules, tabs with their own session history (back, forward, a new navigation cutting the
// forward entries), `about:` pages, the error page, bookmarks and the profile text.
use e.fs
use e.mem
use e.net.fetch as fetch
use e.os
use e.str
use e.text.fontset as fontset
use e.web.shell as shell

fn page(a: *mem.Arena, title: str) -> str {
    let (s, e) = str.concat(a, "data:text/html,<title>", title)
    let (s2, e2) = str.concat(a, s, "</title><p>x</p>")
    ret s2
}

fn main(a: *mem.Arena, args: []str) -> err {
    // 1. The omnibox.
    if !str.eq(shell.omnibox_url(a, "  example.com/a?b=1 "), "https://example.com/a?b=1") { os.exit(1i32) }
    if !str.eq(shell.omnibox_url(a, "localhost:8080/x"), "http://localhost:8080/x") { os.exit(2i32) }
    if !str.eq(shell.omnibox_url(a, "192.168.0.1"), "http://192.168.0.1") { os.exit(3i32) }
    if !str.eq(shell.omnibox_url(a, "https://a.test/"), "https://a.test/") { os.exit(4i32) }
    if !str.eq(shell.omnibox_url(a, "about:history"), "about:history") { os.exit(5i32) }
    if !str.eq(shell.omnibox_url(a, "cats and dogs"), "https://duckduckgo.com/?q=cats%20and%20dogs") { os.exit(6i32) }
    if !str.eq(shell.omnibox_url(a, "weather"), "https://duckduckgo.com/?q=weather") { os.exit(7i32) }
    if !str.eq(shell.omnibox_url(a, ""), "about:blank") { os.exit(8i32) }
    // The shell.
    let (made, me) = fontset.new(a)
    if me != ok { os.exit(10i32) }
    var fonts = made
    let (data, fe) = fs.read_file(a, "docs/ui/looks/ref/linux/fonts/Cantarell-Regular.ttf", 16777216usize)
    if fe != ok { os.exit(11i32) }
    let added = fontset.add(&fonts, "Arial", 400u32, false, data, 0u32)
    fontset.set_generic(&fonts, "sans-serif", "Arial")
    fontset.set_generic(&fonts, "serif", "Arial")
    fontset.set_generic(&fonts, "monospace", "Arial")
    let (cl, ce) = fetch.client(a, fetch.default_config(""), 16usize)
    if ce != ok { os.exit(12i32) }
    var client = cl
    let (sh, se) = shell.new(a, &client, &fonts, 400.0f32, 200.0f32)
    if se != ok { os.exit(13i32) }
    // 2. Tabs and history.
    let (t1, e1) = shell.open_tab(sh, page(a, "one"))
    if e1 != ok { os.exit(20i32) }
    if !str.eq(shell.tab_title(t1), "one") { os.exit(21i32) }
    if shell.navigate(sh, t1, page(a, "two")) != ok { os.exit(22i32) }
    if shell.navigate(sh, t1, page(a, "three")) != ok { os.exit(23i32) }
    if !shell.can_go_back(t1) || shell.can_go_forward(t1) { os.exit(24i32) }
    if !shell.go_back(sh, t1) || !str.eq(t1.pg.title, "two") { os.exit(25i32) }
    if !shell.go_back(sh, t1) || !str.eq(t1.pg.title, "one") || shell.can_go_back(t1) { os.exit(26i32) }
    if !shell.go_forward(sh, t1) || !str.eq(t1.pg.title, "two") { os.exit(27i32) }
    // A new navigation from the middle drops the forward entries.
    if shell.navigate(sh, t1, page(a, "four")) != ok { os.exit(28i32) }
    if shell.can_go_forward(t1) || t1.history.len != 3usize { os.exit(29i32) }
    shell.reload(sh, t1)
    if !str.eq(t1.pg.title, "four") { os.exit(30i32) }
    // 3. A second tab, switching, closing.
    let (t2, e2) = shell.open_tab(sh, "about:blank")
    if e2 != ok || shell.tab_count(sh) != 2usize || sh.active != 1usize { os.exit(31i32) }
    if shell.select_tab(sh, 0usize) != ok || shell.active_tab(sh) != t1 { os.exit(32i32) }
    // 4. Bookmarks, about pages, the profile.
    if !shell.toggle_bookmark(sh, t1) || !shell.is_bookmarked(sh, t1) { os.exit(33i32) }
    let (t3, e3) = shell.open_tab(sh, "about:bookmarks")
    if e3 != ok || !str.eq(t3.pg.title, "Bookmarks") { os.exit(34i32) }
    let text = shell.profile_text(sh)
    if text.len == 0usize || text[0usize] != 66u8 { os.exit(35i32) }
    let (sh2, se2) = shell.new(a, &client, &fonts, 400.0f32, 200.0f32)
    if se2 != ok || shell.load_profile_text(sh2, text) != ok { os.exit(36i32) }
    if sh2.bookmarks.len != sh.bookmarks.len || sh2.visits.len != sh.visits.len { os.exit(37i32) }
    if shell.toggle_bookmark(sh, t1) || shell.is_bookmarked(sh, t1) { os.exit(38i32) }
    // 5. A failed load leaves an error page, and the history keeps the attempt.
    let (t4, e4) = shell.open_tab(sh, "ftp://nowhere.test/file")
    if e4 != ok || !str.eq(t4.pg.title, "Can't load page") { os.exit(39i32) }
    if shell.close_tab(sh, 3usize) != ok || shell.tab_count(sh) != 3usize { os.exit(40i32) }
    if shell.close_tab(sh, 9usize) == ok { os.exit(41i32) }
    // 6. The visit log: one entry per address, a revisit bumps the count and takes the newest end; it can be searched, deleted,
    // cleared and survives the profile.
    let (vs, vse) = shell.new(a, &client, &fonts, 400.0f32, 200.0f32)
    if vse != ok { os.exit(42i32) }
    shell.record_visit(vs, "https://a.test/x", "Alpha")
    shell.record_visit(vs, "https://b.test/y", "Beta")
    shell.record_visit(vs, "https://a.test/x", "Alpha 2")
    shell.record_visit(vs, "about:blank", "skipped")
    if vs.visits.len != 2usize || vs.visits.items[1usize].count != 2u32 || !str.eq(vs.visits.items[1usize].title, "Alpha 2") || !str.eq(vs.visits.items[0usize].url, "https://b.test/y") { os.exit(43i32) }
    let beta = shell.search_visits(vs, "BETA")
    if beta.len != 1usize || !str.eq(beta[0usize].url, "https://b.test/y") { os.exit(44i32) }
    let both = shell.search_visits(vs, "test")
    if both.len != 2usize || !str.eq(both[0usize].url, "https://a.test/x") { os.exit(45i32) }
    let (vs2, vse2) = shell.new(a, &client, &fonts, 400.0f32, 200.0f32)
    if vse2 != ok || shell.load_profile_text(vs2, shell.profile_text(vs)) != ok { os.exit(46i32) }
    if vs2.visits.len != 2usize || vs2.visits.items[1usize].count != 2u32 || vs2.visits.items[1usize].at != vs.visits.items[1usize].at { os.exit(47i32) }
    let (vs3, vse3) = shell.new(a, &client, &fonts, 400.0f32, 200.0f32)
    if vse3 != ok || shell.load_profile_text(vs3, "V\thttps://c.test/\tGamma\n") != ok { os.exit(48i32) }
    if vs3.visits.len != 1usize || vs3.visits.items[0usize].count != 1u32 || !str.eq(vs3.visits.items[0usize].title, "Gamma") { os.exit(49i32) }
    if !shell.delete_visit(vs, "https://b.test/y") || vs.visits.len != 1usize || shell.delete_visit(vs, "https://b.test/y") { os.exit(50i32) }
    shell.clear_visits(vs)
    if vs.visits.len != 0usize { os.exit(51i32) }
    var vi = 0i64
    while vi < 5002i64 {
        let (u, ue) = str.concat(a, "https://many.test/", shell.i64_text(a, vi))
        shell.record_visit(vs, u, "n")
        vi += 1i64
    }
    if vs.visits.len != 5000usize || !str.eq(vs.visits.items[0usize].url, "https://many.test/2") { os.exit(52i32) }
    ret ok
}
