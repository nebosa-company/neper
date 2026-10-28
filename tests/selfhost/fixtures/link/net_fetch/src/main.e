// The redirect policy is shared by HTTP/1.1 and HTTP/2 after the request headers
// have been assembled. These checks target that shared boundary directly.

use e.mem
use e.net.fetch as fetch

error Failed

fn main(a: *mem.Arena) -> err {
    // Host is regenerated for every outbound request, including the initial one.
    if !fetch.drop_redirect_header("HoSt", false) { ret Failed }

    // Credential names are case-insensitive and every independently supplied
    // header (including a duplicate) is stripped on a cross-origin redirect.
    if !fetch.drop_redirect_header("aUtHoRiZaTiOn", true) { ret Failed }
    if !fetch.drop_redirect_header("cOoKiE", true) { ret Failed }
    if !fetch.drop_redirect_header("pRoXy-AuThOrIzAtIoN", true) { ret Failed }
    if !fetch.drop_redirect_header("COOKIE", true) { ret Failed }

    // The original origin keeps caller credentials, and unrelated headers keep
    // flowing after a redirect.
    if fetch.drop_redirect_header("Authorization", false) { ret Failed }
    if fetch.drop_redirect_header("Cookie", false) { ret Failed }
    if fetch.drop_redirect_header("Proxy-Authorization", false) { ret Failed }
    if fetch.drop_redirect_header("X-Preserve", true) { ret Failed }
    ret ok
}
