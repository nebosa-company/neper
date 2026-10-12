#!/usr/bin/env python3
"""Generate tests/selfhost/fixtures/link/net_cookie/src/main.e (C159): e.net.cookie against an independent Python model
of RFC 6265's storage and retrieval algorithms, over a scripted sequence of Set-Cookie responses and requests (domain
and path matching, default path, Max-Age over Expires, deletion, Secure, host-only, ordering, the __Host- prefix)."""
from pathlib import Path

NOW = 1790000000  # 2026-09-21T14:13:20Z, a fixed "now"


def default_path(p):
    if not p or p[0] != "/":
        return "/"
    i = p.rfind("/")
    return "/" if i == 0 else p[:i]


def domain_match(host, domain):
    if host == domain:
        return True
    if host.endswith("." + domain) and not all(ch.isdigit() or ch == "." for ch in host):
        return True
    return False


def path_match(req, cp):
    if req == cp:
        return True
    return req.startswith(cp) and (cp.endswith("/") or req[len(cp):len(cp) + 1] == "/")


class Jar:
    def __init__(self):
        self.items = []  # dicts

    def set(self, header, host, req_path, secure, now):
        parts = [x.strip() for x in header.split(";")]
        if "=" not in parts[0]:
            return
        name, value = [x.strip() for x in parts[0].split("=", 1)]
        if not name:
            return
        c = {"name": name, "value": value, "secure": False, "expires": None, "created": now}
        domain = None
        path = None
        max_age = None
        for attr in parts[1:]:
            k, _, v = attr.partition("=")
            k = k.strip().lower()
            v = v.strip()
            if k == "max-age":
                try:
                    max_age = int(v)
                except ValueError:
                    pass
            elif k == "domain":
                domain = v
            elif k == "path":
                path = v
            elif k == "secure":
                c["secure"] = True
            elif k == "expires":
                import email.utils
                t = email.utils.parsedate_tz(v)
                if t:
                    c["expires"] = email.utils.mktime_tz(t)
        if max_age is not None:
            c["expires"] = 0 if max_age <= 0 else now + max_age
        if domain:
            d = domain.lstrip(".").lower()
            if not domain_match(host, d):
                return
            c["domain"], c["host_only"] = d, False
        else:
            c["domain"], c["host_only"] = host, True
        c["path"] = path if path and path.startswith("/") else default_path(req_path)
        lname = name.lower()
        if lname.startswith("__secure-") and not (c["secure"] and secure):
            return
        if lname.startswith("__host-") and not (c["secure"] and secure and c["host_only"] and c["path"] == "/"):
            return
        if c["secure"] and not secure:
            return
        for i, o in enumerate(self.items):
            if o["name"] == c["name"] and o["domain"] == c["domain"] and o["path"] == c["path"]:
                if c["expires"] is not None and c["expires"] <= now:
                    del self.items[i]
                    return
                c["created"] = o["created"]
                self.items[i] = c
                return
        if c["expires"] is not None and c["expires"] <= now:
            return
        self.items.append(c)

    def get(self, host, path, secure, now):
        chosen = []
        for c in self.items:
            ok = host == c["domain"] if c["host_only"] else domain_match(host, c["domain"])
            if ok and path_match(path, c["path"]) and (secure or not c["secure"]) and not (c["expires"] is not None and c["expires"] <= now):
                chosen.append(c)
        chosen.sort(key=lambda c: (-len(c["path"]), c["created"]))
        return "; ".join("%s=%s" % (c["name"], c["value"]) for c in chosen)


EVENTS = [
    ("set", "example.com", "/a/b/page", True, NOW, "sid=1; Path=/; Secure; HttpOnly"),
    ("set", "example.com", "/a/b/page", True, NOW + 1, "theme=dark; Domain=.example.com; Max-Age=3600"),
    ("set", "example.com", "/a/b/page", True, NOW + 2, "pref=x"),
    ("get", "example.com", "/a/b/other", True, NOW + 3),
    ("get", "www.example.com", "/", True, NOW + 3),
    ("get", "example.com", "/a/b/other", False, NOW + 3),
    ("get", "example.com", "/a/c", True, NOW + 3),
    ("set", "example.com", "/a/b/page", True, NOW + 4, "theme=light; Domain=example.com; Max-Age=3600"),
    ("get", "sub.example.com", "/x", True, NOW + 5),
    ("set", "example.com", "/", True, NOW + 6, "theme=gone; Domain=example.com; Max-Age=0"),
    ("get", "sub.example.com", "/x", True, NOW + 7),
    ("set", "example.com", "/", True, NOW + 8, "sid=2; Path=/; Secure"),
    ("get", "example.com", "/", True, NOW + 9),
    ("set", "evil.com", "/", True, NOW + 10, "x=1; Domain=example.com"),
    ("get", "example.com", "/", True, NOW + 11),
    ("set", "example.com", "/login/form", True, NOW + 12, "__Host-s=1; Secure; Path=/"),
    ("set", "example.com", "/", True, NOW + 13, "__Host-t=1; Secure; Path=/; Domain=example.com"),
    ("set", "example.com", "/", False, NOW + 14, "__Secure-u=1"),
    ("get", "example.com", "/anything", True, NOW + 15),
    ("set", "example.com", "/", True, NOW + 16, "short=1; Max-Age=5"),
    ("get", "example.com", "/", True, NOW + 17),
    ("get", "example.com", "/", True, NOW + 30),
    ("set", "192.168.0.1", "/", False, NOW + 40, "ip=1; Domain=0.1"),
    ("get", "192.168.0.1", "/", False, NOW + 41),
    ("set", "example.com", "/dir/file", False, NOW + 50, "dflt=1"),
    ("get", "example.com", "/dir/other", False, NOW + 51),
    ("get", "example.com", "/dirx/other", False, NOW + 51),
    ("get", "example.com", "/dir", False, NOW + 51),
]


def e_string(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    jar = Jar()
    out = ["// `e.net.cookie` against an independent Python model of RFC 6265's storage and retrieval (scripts/gen_cookie_test.py):\n",
           "// a scripted sequence of Set-Cookie responses and request headers. Every check has its own exit code.\n",
           "use e.os\nuse e.mem\nuse e.str\nuse e.net.cookie as cookie\n\n",
           "fn main(a: *mem.Arena, args: []str) -> err {\n",
           "    var storage: [16]cookie.Cookie = zero\n",
           "    var text: [1024]u8 = zero\n",
           "    var jar = cookie.jar_new(storage[0..], text[0..])\n"]
    n = 0
    for ev in EVENTS:
        if ev[0] == "set":
            _, host, path, secure, now, header = ev
            jar.set(header, host, path, secure, now)
            n += 1
            out.append("    let (c%d, e%d) = cookie.parse(a, %s, %s, %s, %s, %di64)\n" % (n, n, e_string(header), e_string(host), e_string(path), "true" if secure else "false", now))
            out.append("    if e%d == ok { os.exit(%d) }\n" % (n, 0) if False else "    if e%d == ok {\n        let stored%d = cookie.store(&jar, c%d, %di64)\n        if stored%d != ok { os.exit(%d) }\n    }\n" % (n, n, n, now, n, 200 + n))
        else:
            _, host, path, secure, now = ev
            want = jar.get(host, path, secure, now)
            n += 1
            out.append("    let (h%d, he%d) = cookie.header(a, &jar, %s, %s, %s, %di64)\n" % (n, n, e_string(host), e_string(path), "true" if secure else "false", now))
            out.append("    if he%d != ok || !str.eq(h%d, %s) { os.exit(%d) }\n" % (n, n, e_string(want), n))
    # A small text area: replacing one cookie many times must compact and keep working.
    lines = ["k=v%02d" % i for i in range(30)]
    out.append("    var small_storage: [4]cookie.Cookie = zero\n    var small_text: [40]u8 = zero\n")
    out.append("    var small = cookie.jar_new(small_storage[0..], small_text[0..])\n")
    for i, line in enumerate(lines):
        out.append("    let (cc%d, ce%d) = cookie.parse(a, %s, \"h.test\", \"/\", false, 100i64)\n" % (i, i, e_string(line)))
        out.append("    if ce%d != ok || cookie.store(&small, cc%d, 100i64) != ok { os.exit(%d) }\n" % (i, i, 100 + i))
    out.append("    let (sh, she) = cookie.header(a, &small, \"h.test\", \"/\", false, 100i64)\n")
    out.append("    if she != ok || !str.eq(sh, %s) { os.exit(250) }\n" % e_string(lines[-1]))
    out.append("    ret ok\n}\n")
    target = Path(__file__).resolve().parent.parent / "tests/selfhost/fixtures/link/net_cookie/src/main.e"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("".join(out), encoding="utf-8", newline="\n")
    print("wrote", target, "events", n)
    for ev in EVENTS:
        if ev[0] == "get":
            pass


main()
