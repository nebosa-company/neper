// A page's style-sheet imports: a URL is fetched once however many sheets name it, and the number of imported sheets per page is
// capped with the cap recorded on the page, not silent.
use e.fs
use e.mem
use e.net.fetch as fetch
use e.os
use e.str
use e.text.fontset as fontset
use e.web.page as page

fn load_styles(a: *mem.Arena, fonts: *fontset.Set, client: *fetch.Client, css: str) -> *page.Page {
    let (open, oe) = str.concat(a, "data:text/html,<style>", css)
    if oe != ok { os.exit(90i32) }
    let (address, ae) = str.concat(a, open, "</style>")
    if ae != ok { os.exit(91i32) }
    let (pg, e) = page.load(a, client, fonts, address, 400.0f32, 200.0f32, 16777216usize)
    if e != ok { os.exit(92i32) }
    ret pg
}

fn digit(n: usize) -> str {
    if n == 0usize { ret "0" }
    if n == 1usize { ret "1" }
    if n == 2usize { ret "2" }
    if n == 3usize { ret "3" }
    if n == 4usize { ret "4" }
    if n == 5usize { ret "5" }
    if n == 6usize { ret "6" }
    if n == 7usize { ret "7" }
    if n == 8usize { ret "8" }
    ret "9"
}

fn main(a: *mem.Arena, args: []str) -> err {
    let (made, me) = fontset.new(a)
    if me != ok { os.exit(1i32) }
    var fonts = made
    let (data, fe) = fs.read_file(a, "docs/ui/looks/ref/linux/fonts/Cantarell-Regular.ttf", 16777216usize)
    if fe != ok { os.exit(2i32) }
    let added = fontset.add(&fonts, "Arial", 400u32, false, data, 0u32)
    fontset.set_generic(&fonts, "sans-serif", "Arial")
    let (cl, ce) = fetch.client(a, fetch.default_config(""), 16usize)
    if ce != ok { os.exit(3i32) }
    var client = cl

    // the same sheet named twice is fetched and kept once: the inline sheet and one import
    let twice = load_styles(a, &fonts, &client, "@import url(\"data:text/css,.a%7Bcolor:red%7D\"); @import url(\"data:text/css,.a%7Bcolor:red%7D\");")
    if twice.sheets.len != 2usize || twice.imports_capped { os.exit(10i32) }

    // five distinct imports are all kept, with no cap reported
    let few = load_styles(a, &fonts, &client, "@import url(\"data:text/css,.b1%7B%7D\"); @import url(\"data:text/css,.b2%7B%7D\"); @import url(\"data:text/css,.b3%7B%7D\"); @import url(\"data:text/css,.b4%7B%7D\"); @import url(\"data:text/css,.b5%7B%7D\");")
    if few.sheets.len != 6usize || few.imports_capped { os.exit(11i32) }

    // forty distinct imports: 32 are fetched, the rest are refused and the page says so
    var text = ""
    var n = 0usize
    while n < 40usize {
        let (head, pe) = str.concat(a, text, "@import url(\"data:text/css,.c")
        if pe != ok { os.exit(93i32) }
        let (tens, te) = str.concat(a, head, digit(n / 10usize))
        if te != ok { os.exit(93i32) }
        let (ones, oe2) = str.concat(a, tens, digit(n % 10usize))
        if oe2 != ok { os.exit(93i32) }
        let (next, ne) = str.concat(a, ones, "%7B%7D\"); ")
        if ne != ok { os.exit(94i32) }
        text = next
        n += 1usize
    }
    let many = load_styles(a, &fonts, &client, text)
    if many.sheets.len != 33usize || !many.imports_capped { os.exit(12i32) }
    ret ok
}
