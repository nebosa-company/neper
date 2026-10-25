// `e.net.fetch` over a loopback TLS server whose certificate is for example.com: a client that does not trust the issuer, and a
// client that does but reached the server as 127.0.0.1, fail with CertificateError (no trusted roots) and CertificateName (a trusted issuer, another host), not the generic network error.
use e.mem
use e.net
use e.net.fetch as fetch
use e.net.http as http
use e.net.tls
use e.os
use e.str
use e.thread

type Job = struct { listener: net.Socket, config: tls.ServerConfig, accepts: usize }

fn serve(job: *Job) {
    var storage: [524288]u8 = zero
    var arena = mem.arena_from(storage[0..])
    var n = 0usize
    while n < job.accepts {
        n += 1usize
        let (accepted, peer, accept_error) = net.tcp_accept(job.listener)
        if accept_error != ok { ret }
        var connection = accepted
        defer let _ = net.close(connection)
        let source = net.reader(&connection)
        let sink = net.writer(&connection)
        let (secure0, create_error) = tls.server(&arena, source, sink, job.config)
        if create_error == ok {
            var secure = secure0
            let handshake = tls.handshake(&secure)
        }
    }
}

fn request(u: str) -> fetch.Request {
    ret fetch.Request { url: u, method: http.Method.Get, headers: zero, body: zero, redirect: fetch.Redirect.Follow, credentials: fetch.Credentials.Omit, referrer: "" }
}

fn main(a: *mem.Arena, args: []str) -> err {
    let mid_der = "0\x82\x01\x130\x81\xc6\xa0\x03\x02\x01\x02\x02\x01\x020\x05\x06\x03+ep0%1\x130\x11\x06\x03U\x04\x03\x0c\x0aNeper Root1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0*0\x05\x06\x03+ep\x03!\x00\x819w\x0e\xa8}\x17_V\xa3Tf\xc3L~\xcc\xcb\x8d\x8a\x91\xb4\xee7\xa2]\xf6\x0f[\x8f\xc9\xb3\x94\xa3\x130\x110\x0f\x06\x03U\x1d\x13\x01\x01\xff\x04\x050\x03\x01\x01\xff0\x05\x06\x03+ep\x03A\x00R^\x187\xb39[\xa4N\xc4\x83\x10\xde\xfc\x7f\xa0\xbfF[\xa8^\x04S\xa1\xb2\xf8\xbcM\xc7\xfb\xf1t\x89\xa0\x0e\x07\xcc\xbf\x8f6R\x16\x15\xab\x99\x0e\xdd\xc1,\x8d\x8f*\xd4\xaf\x97\xaae\x8b\xab\xe5\x0d\x8e'\x08"
    let leaf_der = "0\x82\x01=0\x81\xf0\xa0\x03\x02\x01\x02\x02\x01\x030\x05\x06\x03+ep0-1\x1b0\x19\x06\x03U\x04\x03\x0c\x12Neper Intermediate1\x0e0\x0c\x06\x03U\x04\x0a\x0c\x05Neper0\x1e\x17\x0d250101000000Z\x17\x0d350101000000Z0\x161\x140\x12\x06\x03U\x04\x03\x0c\x0bexample.com0*0\x05\x06\x03+ep\x03!\x00\xedI(\xc6(\xd1\xc2\xc6\xea\xe9\x038\x90Y\x95a)Y':\\c\xf966\xc1F\x14\xac\x877\xd1\xa3L0J0\x0c\x06\x03U\x1d\x13\x01\x01\xff\x04\x020\x000%\x06\x03U\x1d\x11\x04\x1e0\x1c\x82\x0bexample.com\x82\x0d*.example.org0\x13\x06\x03U\x1d%\x04\x0c0\x0a\x06\x08+\x06\x01\x05\x05\x07\x03\x010\x05\x06\x03+ep\x03A\x00\x84Pf\xea\x11\xb7\xdb-w\xdf\xd2\xa8\xden\xd3\xbey|r`B'h\xfc\x22\x08\xca\x8e%u\xa8\xa7)\xd3\xb3\x15Tc\xc8\x10\xa0\x97\x84C\xaaU4\xf0>\x00\x0f\xfau\xe7\xaa\xb9\xae\x9e\x9br\xe8Bv\x09"
    let leaf_pkcs8 = "0.\x02\x01\x000\x05\x06\x03+ep\x04\x22\x04\x20\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03\x03"
    let (loopback, loopback_error) = net.parse_ip("127.0.0.1")
    if loopback_error != ok { os.exit(1i32) }
    let (listener, listen_error) = net.tcp_listen(net.Endpoint { address: loopback, port: 0u16 }, 2u32)
    if listen_error != ok { os.exit(2i32) }
    let (bound, bound_error) = os.socket_local_address(listener)
    if bound_error != ok { os.exit(3i32) }
    var entropy: [64]u8 = zero
    var at = 0usize
    while at < 64usize {
        entropy[at] = u8(64usize + at)
        at += 1usize
    }
    var none: [1]str = zero
    let config = tls.ServerConfig { certificate_chain: leaf_der, private_key: leaf_pkcs8, alpn: none[0..0], entropy: entropy[0..] }
    var job = Job { listener: listener, config: config, accepts: 2usize }
    let (worker, worker_error) = thread.spawn[Job](serve, &job, 8388608usize)
    if worker_error != ok { os.exit(4i32) }
    let (port_text, pe) = str.concat(a, "https://127.0.0.1:", portn(a, bound.port))
    let (address, ae) = str.concat(a, port_text, "/secure")
    // The issuer is not trusted.
    let (c0, ce0) = fetch.client(a, fetch.default_config(""), 4usize)
    if ce0 != ok { os.exit(5i32) }
    var untrusted = c0
    let (r1, e1) = fetch.fetch(&untrusted, request(address))
    if e1 != fetch.CertificateError { os.exit(6i32) }
    // The issuer is trusted but the certificate names another host.
    let (c1, ce1) = fetch.client(a, fetch.default_config(mid_der), 4usize)
    if ce1 != ok { os.exit(7i32) }
    var wrong_host = c1
    let (r2, e2) = fetch.fetch(&wrong_host, request(address))
    if e2 != fetch.CertificateName { os.exit(8i32) }
    if thread.join(worker) != ok { os.exit(9i32) }
    ret ok
}

fn portn(a: *mem.Arena, p: u16) -> str {
    var digits: [8]u8 = zero
    var at = 8usize
    var v = usize(p)
    if v == 0usize { ret "0" }
    while v > 0usize {
        at -= 1usize
        digits[at] = u8(48usize + v % 10usize)
        v = v / 10usize
    }
    let (out, e) = mem.alloc[u8](a, 8usize - at)
    if e != ok { ret "" }
    mem.copy[u8](out, digits[at..])
    ret out
}
