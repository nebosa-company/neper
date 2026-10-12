// AI (D2236): the app behind the AI icon, a chat with an AI model you bring the key for (bring your own key)
// -- a setup screen (the provider: Anthropic, OpenAI, Google or a local model; the model; the API key typed
// on the on-screen keyboard and shown as stars; Save), and the chat: your messages and the assistant's in
// bubbles, a message box on the keyboard, the reply arriving a little at a time, a button to change the
// provider or the key and one to start a new chat. Dark ground, cream bubbles for the assistant and amber
// for you, like the other apps (appkit.e, taps from the compositor, the five fonts as args[1..5]). A tap on
// the bar at the bottom leaves the app.
// (C141) The replies are real: each message sends the conversation to the provider's API over HTTPS with the key
// typed in setup, and the answer's text is read from the reply; a refused key, a rate limit, no network and the
// rest are said in plain words.
// (C171) The reply is streamed: the request asks for Server-Sent Events and the answer is taken a poll at a time on
// the compositor's ticks (httpstream.e, e.fmt.sse), each piece going into the bubble as it arrives. With a vault
// made by Secure on the disk the API key is kept there, sealed under the master password (a record /v/k<provider>
// next to the logins and codes), is read for one request and wiped once it is sent, and is checked with the
// provider's model list before it is saved. Conversations are kept in /ai (a title and the messages), listed,
// searched, renamed and deleted from the Chats screen; the system prompt, the temperature, the token limit and the
// local server's host are Options. Left (C171): images and files as inputs, highlighted code blocks, tools.
use e.mem
use e.os
use e.gfx.geometry
use e.gfx.paint
use e.gfx.scene
use e.gfx.svg
use e.text.layout
use e.text.shape
use e.fmt.sse as sse
use appkit
use text
use ui
use httpstream
use netproto
use sysettings
use vault
use vaultfs
use e.time

const NONE: usize = 99usize
const MAX_MSGS: usize = 12usize
const MSG_BYTES: usize = 400usize
const MAX_CONVS: usize = 6usize
const SETUP_SCREEN: usize = 0usize
const CHAT_SCREEN: usize = 1usize
const LOCK_SCREEN: usize = 2usize
const HISTORY_SCREEN: usize = 3usize
const OPTIONS_SCREEN: usize = 4usize
// The vault: none on this machine, one on the disk that is still locked, one that is open.
const VAULT_NONE: usize = 0usize
const VAULT_LOCKED: usize = 1usize
const VAULT_OPEN: usize = 2usize
const BODY_CAP: usize = 24576usize
// Ticks (500 ms each) without a byte before a reply is given up.
const SILENT_LIMIT: usize = 120usize

type Msg = struct { mine: bool, body: [400]u8, body_len: usize }

type Conv = struct { used: bool, title: [32]u8, title_len: usize, count: usize, hit: bool }

type State = struct {
    msgs: [12]Msg,
    msg_total: usize,
    screen: usize,
    provider: usize,
    model: usize,
    key: ui.Field,
    key_saved: bool,
    draft: ui.Field,
    typing: bool,
    // The reply being written: the text so far.
    reply: [400]u8,
    reply_len: usize,
    replying: bool,
    // (C148) How much text the clipboard holds (0 when none): the Paste button shows when there is some.
    clip_len: usize,
    hits: ui.Hits,
    // (C171) The request in flight: the incremental reader, the buffer its body lands in, how far the event parser
    // has read, ticks without data, and whether any piece of text has come.
    net: httpstream.Stream,
    body: []u8,
    streaming: bool,
    sse_at: usize,
    silent: usize,
    pieces: usize,
    events: usize,
    // The vault, its key, the master password being typed and the job behind Unlock.
    vault_state: usize,
    vault_key: [32]u8,
    master: ui.Field,
    job: usize,
    message: [48]u8,
    message_len: usize,
    // Options: the system prompt, the local server's host, the temperature in tenths and the token limit.
    system: ui.Field,
    host: ui.Field,
    focus: usize,
    temperature: usize,
    tokens: usize,
    // Conversations: the one open (NONE when it has not been saved yet), the list, the search and the rename.
    conv: usize,
    convs: [6]Conv,
    searching: bool,
    renaming: bool,
    query: ui.Field,
    seed: usize,
}

fn provider_name(p: usize) -> str {
    if p == 0usize { ret "Anthropic" }
    if p == 1usize { ret "OpenAI" }
    if p == 2usize { ret "Google" }
    ret "Local model"
}

fn model_name(p: usize, m: usize) -> str {
    if p == 0usize {
        if m == 0usize { ret "opus" }
        if m == 1usize { ret "sonnet" }
        ret "haiku"
    }
    if p == 1usize {
        if m == 0usize { ret "large" }
        if m == 1usize { ret "small" }
        ret "mini"
    }
    if p == 2usize {
        if m == 0usize { ret "pro" }
        if m == 1usize { ret "flash" }
        ret "nano"
    }
    if m == 0usize { ret "7b" }
    if m == 1usize { ret "3b" }
    ret "1b"
}

fn model_id(p: usize, m: usize) -> str {
    if p == 0usize {
        if m == 0usize { ret "claude-opus-5-5" }
        if m == 1usize { ret "claude-sonnet-5-5" }
        ret "claude-haiku-5-5"
    }
    if p == 1usize {
        if m == 0usize { ret "gpt-5" }
        if m == 1usize { ret "gpt-5-mini" }
        ret "gpt-5-nano"
    }
    if p == 2usize {
        if m == 0usize { ret "gemini-2.5-pro" }
        if m == 1usize { ret "gemini-2.5-flash" }
        ret "gemini-2.5-flash-lite"
    }
    if m == 0usize { ret "llama-7b" }
    if m == 1usize { ret "llama-3b" }
    ret "llama-1b"
}

fn token_limit(index: usize) -> usize {
    if index == 0usize { ret 256usize }
    if index == 1usize { ret 512usize }
    if index == 3usize { ret 2048usize }
    ret 1024usize
}

fn add_msg(s: *State, mine: bool, body: str) {
    if s.msg_total == MAX_MSGS {
        var k = 1usize
        while k < MAX_MSGS {
            s.msgs[k - 1usize] = s.msgs[k]
            k += 1usize
        }
        s.msg_total -= 1usize
    }
    var m: Msg = zero
    var i = 0usize
    while i < body.len && i < MSG_BYTES {
        m.body[i] = body[i]
        i += 1usize
    }
    m.body_len = i
    m.mine = mine
    s.msgs[s.msg_total] = m
    s.msg_total += 1usize
}

fn say_message(s: *State, line: str) {
    var n = 0usize
    while n < line.len && n < 48usize {
        s.message[n] = line[n]
        n += 1usize
    }
    s.message_len = n
}

// ----------------------------------------------------------------------------------------------
// The request body and the reply's text.

// `piece` into `buf` at `at` as the inside of a JSON string; the new end.
fn put_escaped(buf: []u8, at: usize, piece: []const u8, length: usize) -> usize {
    var n = at
    var i = 0usize
    while i < length && n + 6usize < buf.len {
        let c = piece[i]
        if c == 34u8 || c == 92u8 {
            buf[n] = 92u8
            buf[n + 1usize] = c
            n += 2usize
        } else if c == 10u8 {
            buf[n] = 92u8
            buf[n + 1usize] = 110u8
            n += 2usize
        } else if c >= 32u8 {
            buf[n] = c
            n += 1usize
        }
        i += 1usize
    }
    ret n
}

// The temperature as "0.7" or "1.0".
fn put_temperature(buf: []u8, at: usize, tenths: usize) -> usize {
    var n = at
    n = httpstream.put_number(buf, n, tenths / 10usize)
    n = httpstream.put(buf, n, ".")
    n = httpstream.put_number(buf, n, tenths % 10usize)
    ret n
}

// The request body for the conversation so far, in the shape of the provider, asking for a stream; the length.
fn build_body(a: *mem.Arena, s: *State, buf: []u8) -> usize {
    var n = 0usize
    let google = s.provider == 2usize
    let system = ui.field_text(a, &s.system)
    if google {
        n = httpstream.put(buf, n, "{\"generationConfig\":{\"temperature\":")
        n = put_temperature(buf, n, s.temperature)
        n = httpstream.put(buf, n, ",\"maxOutputTokens\":")
        n = httpstream.put_number(buf, n, token_limit(s.tokens))
        n = httpstream.put(buf, n, "},")
        if system.len > 0usize {
            n = httpstream.put(buf, n, "\"systemInstruction\":{\"parts\":[{\"text\":\"")
            n = put_escaped(buf, n, system, system.len)
            n = httpstream.put(buf, n, "\"}]},")
        }
        n = httpstream.put(buf, n, "\"contents\":[")
    } else {
        n = httpstream.put(buf, n, "{\"model\":\"")
        n = httpstream.put(buf, n, model_id(s.provider, s.model))
        n = httpstream.put(buf, n, "\",\"stream\":true,")
        if s.provider == 1usize {
            n = httpstream.put(buf, n, "\"max_completion_tokens\":")
            n = httpstream.put_number(buf, n, token_limit(s.tokens))
            n = httpstream.put(buf, n, ",")
        } else {
            n = httpstream.put(buf, n, "\"max_tokens\":")
            n = httpstream.put_number(buf, n, token_limit(s.tokens))
            n = httpstream.put(buf, n, ",\"temperature\":")
            n = put_temperature(buf, n, s.temperature)
            n = httpstream.put(buf, n, ",")
        }
        if s.provider == 0usize && system.len > 0usize {
            n = httpstream.put(buf, n, "\"system\":\"")
            n = put_escaped(buf, n, system, system.len)
            n = httpstream.put(buf, n, "\",")
        }
        n = httpstream.put(buf, n, "\"messages\":[")
    }
    var first = true
    if !google && s.provider != 0usize && system.len > 0usize {
        n = httpstream.put(buf, n, "{\"role\":\"system\",\"content\":\"")
        n = put_escaped(buf, n, system, system.len)
        n = httpstream.put(buf, n, "\"}")
        first = false
    }
    var k = 0usize
    while k < s.msg_total {
        if !first { n = httpstream.put(buf, n, ",") }
        first = false
        var role = "assistant"
        if s.msgs[k].mine { role = "user" }
        if google {
            if !s.msgs[k].mine { role = "model" }
            n = httpstream.put(buf, n, "{\"role\":\"")
            n = httpstream.put(buf, n, role)
            n = httpstream.put(buf, n, "\",\"parts\":[{\"text\":\"")
        } else {
            n = httpstream.put(buf, n, "{\"role\":\"")
            n = httpstream.put(buf, n, role)
            n = httpstream.put(buf, n, "\",\"content\":\"")
        }
        n = put_escaped(buf, n, s.msgs[k].body[0usize..], s.msgs[k].body_len)
        if google { n = httpstream.put(buf, n, "\"}]}") } else { n = httpstream.put(buf, n, "\"}") }
        k += 1usize
    }
    n = httpstream.put(buf, n, "]}")
    ret n
}

fn hex4(body_text: str, at: usize) -> usize {
    var v = 0usize
    var i = 0usize
    while i < 4usize && at + i < body_text.len {
        let d = httpstream.hex_value(body_text[at + i])
        if d == 99usize { ret 0usize }
        v = v * 16usize + d
        i += 1usize
    }
    ret v
}

// Whether `body_text` holds `"key":` at `at`.
fn key_at(body_text: str, at: usize, key: str) -> bool {
    if at + key.len + 3usize > body_text.len { ret false }
    if body_text[at] != 34u8 || body_text[at + 1usize + key.len] != 34u8 || body_text[at + 2usize + key.len] != 58u8 { ret false }
    var i = 0usize
    while i < key.len {
        if body_text[at + 1usize + i] != key[i] { ret false }
        i += 1usize
    }
    ret true
}

// The first JSON string value of `key` in `body_text` into `out`; its length (0 when the key is absent).
fn extract_text(body_text: str, key: str, out: []u8) -> usize {
    var at = 0usize
    var found = false
    while at + key.len + 3usize < body_text.len && !found {
        var next = at + 1usize
        if key_at(body_text, at, key) {
            var v = at + 3usize + key.len
            while v < body_text.len && body_text[v] == 32u8 { v += 1usize }
            if v < body_text.len && body_text[v] == 34u8 {
                next = v + 1usize
                found = true
            }
        }
        at = next
    }
    if !found { ret 0usize }
    var n = 0usize
    var done = false
    while at < body_text.len && !done && n + 4usize < out.len {
        let c = body_text[at]
        if c == 34u8 {
            done = true
        } else if c == 92u8 && at + 1usize < body_text.len {
            let e = body_text[at + 1usize]
            at += 2usize
            if e == 110u8 {
                out[n] = 10u8
                n += 1usize
            } else if e == 116u8 {
                out[n] = 32u8
                n += 1usize
            } else if e == 117u8 && at + 4usize <= body_text.len {
                let cp = hex4(body_text, at)
                at += 4usize
                if cp < 128usize {
                    out[n] = u8(cp)
                    n += 1usize
                } else if cp < 2048usize {
                    out[n] = u8(192usize | (cp >> 6usize))
                    out[n + 1usize] = u8(128usize | (cp & 63usize))
                    n += 2usize
                } else {
                    out[n] = u8(224usize | (cp >> 12usize))
                    out[n + 1usize] = u8(128usize | ((cp >> 6usize) & 63usize))
                    out[n + 2usize] = u8(128usize | (cp & 63usize))
                    n += 3usize
                }
            } else {
                out[n] = e
                n += 1usize
            }
        } else {
            out[n] = c
            n += 1usize
            at += 1usize
        }
    }
    ret n
}

fn set_reply(s: *State, message: str) {
    var i = 0usize
    while i < message.len && i < MSG_BYTES {
        s.reply[i] = message[i]
        i += 1usize
    }
    s.reply_len = i
}

// What a status code means for the person, in plain words.
fn status_words(a: *mem.Arena, s: *State, status: usize) -> str {
    if status == 401usize || status == 403usize { ret "The provider refused the key. Check it in setup." }
    if status == 429usize { ret "The rate limit was reached. Try again in a moment." }
    if status == 404usize { ret "The provider does not know this model." }
    ret ui.join(a, ui.join(a, "The provider answered with status ", ui.number(a, status), "."), "", "")
}

// What a failed connection means, in plain words.
fn connect_words(a: *mem.Arena, s: *State, result: usize) -> str {
    if result == netproto.R_NO_NETWORK { ret "There is no network, so I cannot reach the model." }
    if result == netproto.R_RESOLVE || result == netproto.R_CONNECT { ret ui.join(a, "I could not reach ", provider_name(s.provider), ".") }
    if result == netproto.R_TLS { ret ui.join(a, "The secure connection to ", provider_name(s.provider), " failed.") }
    ret "The reply did not arrive whole."
}

// ----------------------------------------------------------------------------------------------
// The vault (made by Secure): its key from the master password, and the API key sealed in /v/k<provider>.

fn key_record(a: *mem.Arena, provider: usize) -> str {
    ret ui.join(a, "k", ui.number(a, provider), "")
}

fn unlock_vault(a: *mem.Arena, s: *State) -> usize {
    var meta: [80]u8 = zero
    let (count, found) = vaultfs.read("/vmeta", mem.address_of(&meta[0usize]), 80usize)
    if !found { ret 2usize }
    let (key, unlock_error) = vault.meta_unlock(meta[0usize..count], ui.field_text(a, &s.master))
    if unlock_error == vault.WrongPassword { ret 1usize }
    if unlock_error != ok { ret 2usize }
    s.vault_key = key
    ret 0usize
}

// The saved key of the current provider into s.key (empty when there is none); whether one was there.
fn load_key(a: *mem.Arena, s: *State) -> bool {
    s.key.len = 0usize
    if s.vault_state != VAULT_OPEN { ret false }
    var record: [160]u8 = zero
    var plain: [128]u8 = zero
    let name = key_record(a, s.provider)
    let (count, found) = vaultfs.read(ui.join(a, "/v/", name, ""), mem.address_of(&record[0usize]), 160usize)
    if !found { ret false }
    let (n, open_error) = vault.open(s.vault_key, name, record[0usize..count], plain[0usize..])
    if open_error != ok || n < 2usize || plain[0] != 3u8 { ret false }
    var k = 0usize
    while k < n - 1usize && k < 100usize {
        ui.field_type(&s.key, plain[1usize + k], false)
        k += 1usize
    }
    ret true
}

// Seal the typed key as the current provider's record; whether the disk took it.
fn store_key(a: *mem.Arena, s: *State) -> bool {
    if s.vault_state != VAULT_OPEN || s.key.len == 0usize || s.key.len > 100usize { ret false }
    var plain: [128]u8 = zero
    plain[0] = 3u8
    var k = 0usize
    while k < s.key.len {
        plain[1usize + k] = s.key.bytes[k]
        k += 1usize
    }
    var nonce: [16]u8 = zero
    if !vaultfs.random(mem.address_of(&nonce[0usize]), 2usize) { ret false }
    var record: [160]u8 = zero
    let name = key_record(a, s.provider)
    let (length, seal_error) = vault.seal(s.vault_key, nonce[0usize..], name, plain[0usize..1usize + s.key.len], record[0usize..])
    if seal_error != ok { ret false }
    let made = vaultfs.mkdir("/v")
    ret vaultfs.write(ui.join(a, "/v/", name, ""), mem.address_of(&record[0usize]), length)
}

// The key is only in memory for a request: forget it.
fn wipe_key(s: *State) {
    var k = 0usize
    while k < s.key.len {
        s.key.bytes[k] = 0u8
        k += 1usize
    }
    s.key.len = 0usize
}

// ----------------------------------------------------------------------------------------------
// The provider client.

// The host, path and extra headers of a request to the current provider (`path_kind` 0 the chat, 1 the model list), and
// the port and whether TLS: a local server named "host:port" is plain TCP at that port.
fn endpoint_host(a: *mem.Arena, s: *State) -> str {
    if s.provider == 0usize { ret "api.anthropic.com" }
    if s.provider == 1usize { ret "api.openai.com" }
    if s.provider == 2usize { ret "generativelanguage.googleapis.com" }
    if s.host.len > 0usize {
        let named = ui.field_text(a, &s.host)
        var k = 0usize
        while k < named.len && named[k] != 58u8 { k += 1usize }
        ret ui.text_of(a, named, k)
    }
    ret "neper.test"
}

fn endpoint_port(s: *State) -> u16 {
    if s.provider == 3usize && s.host.len > 0usize {
        var k = 0usize
        while k < s.host.len && s.host.bytes[k] != 58u8 { k += 1usize }
        if k < s.host.len {
            var port = 0usize
            k += 1usize
            while k < s.host.len && s.host.bytes[k] >= 48u8 && s.host.bytes[k] <= 57u8 {
                port = port * 10usize + usize(s.host.bytes[k] - 48u8)
                k += 1usize
            }
            if port > 0usize && port < 65536usize { ret u16(port) }
        }
    }
    ret 443u16
}

fn endpoint_secure(s: *State) -> bool {
    ret endpoint_port(s) == 443u16
}

fn chat_path(a: *mem.Arena, s: *State, key: str) -> str {
    if s.provider == 0usize { ret "/v1/messages" }
    if s.provider == 2usize { ret ui.join(a, ui.join(a, "/v1beta/models/", model_id(s.provider, s.model), ":streamGenerateContent?alt=sse&key="), key, "") }
    ret "/v1/chat/completions"
}

fn key_headers(a: *mem.Arena, s: *State, key: str) -> str {
    if s.provider == 0usize { ret ui.join(a, ui.join(a, "x-api-key: ", key, "\r\n"), "anthropic-version: 2023-06-01\r\n", "") }
    if s.provider == 1usize || (s.provider == 3usize && key.len > 0usize) { ret ui.join(a, "Authorization: Bearer ", key, "\r\n") }
    ret ""
}

// Start the request for the conversation so far: the request goes out and the key is wiped. True when a reply is
// coming; false with the plain-words reason in s.reply.
fn start_request(a: *mem.Arena, s: *State) -> bool {
    let (buf, buf_error) = mem.alloc[u8](a, 12288usize)
    if buf_error != ok {
        set_reply(s, "I ran out of memory.")
        ret false
    }
    // A vault key is read for this request only.
    if s.vault_state == VAULT_OPEN { let have = load_key(a, s) }
    let body_len = build_body(a, s, buf)
    let key = ui.field_text(a, &s.key)
    httpstream.begin(&s.net, mem.address_of(&s.body[0usize]), s.body.len)
    let result = httpstream.start(a, &s.net, "POST", endpoint_host(a, s), chat_path(a, s, key), key_headers(a, s, key), buf[0usize..body_len], endpoint_port(s), endpoint_secure(s))
    if s.vault_state == VAULT_OPEN { wipe_key(s) }
    if result != netproto.R_OK {
        set_reply(s, connect_words(a, s, result))
        ret false
    }
    s.sse_at = 0usize
    s.silent = 0usize
    s.pieces = 0usize
    s.events = 0usize
    s.reply_len = 0usize
    ret true
}

// A cheap check of a key: the provider's model list. 0 accepted, 1 refused, 2 could not reach it.
fn check_key(a: *mem.Arena, s: *State) -> usize {
    let key = ui.field_text(a, &s.key)
    var path = "/v1/models"
    if s.provider == 2usize { path = ui.join(a, "/v1beta/models?key=", key, "") }
    httpstream.begin(&s.net, mem.address_of(&s.body[0usize]), s.body.len)
    let result = httpstream.start(a, &s.net, "GET", endpoint_host(a, s), path, key_headers(a, s, key), "", endpoint_port(s), endpoint_secure(s))
    if result != netproto.R_OK { ret 2usize }
    // The status line is all that is needed; wait for it, bounded.
    var waited = 0usize
    while s.net.phase == httpstream.PH_HEAD && waited < 400usize {
        let got = httpstream.pump(&s.net)
        if got == netproto.R_EMPTY { waited += 1usize } else if got != netproto.R_OK { waited = 400usize }
    }
    let status = s.net.status
    httpstream.abort(&s.net)
    if s.net.phase != httpstream.PH_DONE || status == 0usize { ret 2usize }
    if status == 401usize || status == 403usize { ret 1usize }
    if status >= 200usize && status < 300usize { ret 0usize }
    ret 2usize
}

fn append_reply(s: *State, piece: []const u8, length: usize) {
    var i = 0usize
    while i < length && s.reply_len < MSG_BYTES {
        s.reply[s.reply_len] = piece[i]
        s.reply_len += 1usize
        i += 1usize
    }
}

// ----------------------------------------------------------------------------------------------
// Conversations in /ai.

fn conv_path(a: *mem.Arena, i: usize) -> str {
    ret ui.join(a, "/ai/c", ui.number(a, i), "")
}

fn title_of(a: *mem.Arena, s: *State, i: usize) -> str {
    ret ui.text_of(a, s.convs[i].title[0usize..], s.convs[i].title_len)
}

// The file of the open conversation: a length byte and the title, a count, and each message as its role (1 mine), a
// two-byte length and its bytes.
fn save_conv(a: *mem.Arena, s: *State) {
    if s.msg_total == 0usize { ret }
    let (buf, buf_error) = mem.alloc[u8](a, 5200usize)
    if buf_error != ok { ret }
    if s.conv == NONE {
        var i = 0usize
        while i < MAX_CONVS && s.conv == NONE {
            let (reachable, exists) = vaultfs.probe(conv_path(a, i))
            if !reachable { ret }
            if !exists { s.conv = i }
            i += 1usize
        }
        if s.conv == NONE { ret }
        let made = vaultfs.mkdir("/ai")
        // The title is the start of the first message.
        var t = 0usize
        while t < 24usize && t < s.msgs[0].body_len {
            s.convs[s.conv].title[t] = s.msgs[0].body[t]
            t += 1usize
        }
        s.convs[s.conv].title_len = t
        s.convs[s.conv].used = true
    }
    let c = s.conv
    var n = 0usize
    buf[n] = u8(s.convs[c].title_len)
    n += 1usize
    var k = 0usize
    while k < s.convs[c].title_len {
        buf[n] = s.convs[c].title[k]
        n += 1usize
        k += 1usize
    }
    buf[n] = u8(s.msg_total)
    n += 1usize
    k = 0usize
    while k < s.msg_total {
        if s.msgs[k].mine { buf[n] = 1u8 } else { buf[n] = 0u8 }
        buf[n + 1usize] = u8(s.msgs[k].body_len & 255usize)
        buf[n + 2usize] = u8(s.msgs[k].body_len >> 8usize)
        n += 3usize
        var b = 0usize
        while b < s.msgs[k].body_len {
            buf[n] = s.msgs[k].body[b]
            n += 1usize
            b += 1usize
        }
        k += 1usize
    }
    if vaultfs.write_big(conv_path(a, c), mem.address_of(&buf[0usize]), n) {
        ui.say("ai saved chat ")
        ui.say_num(c)
        ui.say("\n")
    }
}

// Read conversation `i`: its title and message count into the list, and with `into_chat` its messages into the chat.
fn read_conv(a: *mem.Arena, s: *State, i: usize, into_chat: bool) -> bool {
    let (buf, buf_error) = mem.alloc[u8](a, 5200usize)
    if buf_error != ok { ret false }
    let (n, found) = vaultfs.read_big(conv_path(a, i), mem.address_of(&buf[0usize]), 5200usize)
    if !found || n < 2usize { ret false }
    let title_len = usize(buf[0])
    if title_len > 32usize || 2usize + title_len > n { ret false }
    var k = 0usize
    while k < title_len {
        s.convs[i].title[k] = buf[1usize + k]
        k += 1usize
    }
    s.convs[i].title_len = title_len
    let count = usize(buf[1usize + title_len])
    s.convs[i].count = count
    s.convs[i].used = true
    if !into_chat { ret true }
    s.msg_total = 0usize
    var at = 2usize + title_len
    var m = 0usize
    while m < count && at + 3usize <= n {
        let mine = buf[at] == 1u8
        let length = usize(buf[at + 1usize]) | (usize(buf[at + 2usize]) << 8usize)
        at += 3usize
        if at + length > n { ret true }
        add_msg(s, mine, ui.text_of(a, buf[at..], length))
        at += length
        m += 1usize
    }
    ret true
}

// Whether `needle` is in `hay`, ignoring case.
fn has_text(hay: str, needle: str) -> bool {
    if needle.len == 0usize { ret true }
    var at = 0usize
    while at + needle.len <= hay.len {
        var same = true
        var k = 0usize
        while k < needle.len {
            var x = hay[at + k]
            var y = needle[k]
            if x >= 65u8 && x <= 90u8 { x += 32u8 }
            if y >= 65u8 && y <= 90u8 { y += 32u8 }
            if x != y { same = false }
            k += 1usize
        }
        if same { ret true }
        at += 1usize
    }
    ret false
}

// List the conversations on the disk (titles, counts) and mark the ones holding the query; how many are listed.
fn list_convs(a: *mem.Arena, s: *State) -> usize {
    var listed = 0usize
    var i = 0usize
    while i < MAX_CONVS {
        s.convs[i].used = false
        s.convs[i].hit = true
        let (reachable, exists) = vaultfs.probe(conv_path(a, i))
        if reachable && exists && read_conv(a, s, i, false) {
            listed += 1usize
            if s.query.len > 0usize {
                // The title or any message holds the query.
                var found = has_text(title_of(a, s, i), ui.field_text(a, &s.query))
                if !found {
                    let (buf, buf_error) = mem.alloc[u8](a, 5200usize)
                    if buf_error == ok {
                        let (n, read_ok) = vaultfs.read_big(conv_path(a, i), mem.address_of(&buf[0usize]), 5200usize)
                        if read_ok { found = has_text(ui.text_of(a, buf[0usize..], n), ui.field_text(a, &s.query)) }
                    }
                }
                s.convs[i].hit = found
            }
        }
        i += 1usize
    }
    ret listed
}

fn rename_conv(a: *mem.Arena, s: *State, title: str) {
    if s.conv == NONE || title.len == 0usize { ret }
    var t = 0usize
    while t < title.len && t < 32usize {
        s.convs[s.conv].title[t] = title[t]
        t += 1usize
    }
    s.convs[s.conv].title_len = t
    save_conv(a, s)
    ui.say("ai renamed ")
    ui.say_text(title)
    ui.say("\n")
}

// ----------------------------------------------------------------------------------------------
// Settings in /ai/settings: provider, model, temperature, token limit, the system prompt and the host.

fn save_settings(a: *mem.Arena, s: *State) {
    var buf: [400]u8 = zero
    buf[0] = u8(s.provider)
    buf[1] = u8(s.model)
    buf[2] = u8(s.temperature)
    buf[3] = u8(s.tokens)
    buf[4] = u8(s.system.len)
    var n = 5usize
    var k = 0usize
    while k < s.system.len && k < 160usize {
        buf[n] = s.system.bytes[k]
        n += 1usize
        k += 1usize
    }
    buf[n] = u8(s.host.len)
    n += 1usize
    k = 0usize
    while k < s.host.len && k < 100usize {
        buf[n] = s.host.bytes[k]
        n += 1usize
        k += 1usize
    }
    let made = vaultfs.mkdir("/ai")
    if vaultfs.write_big("/ai/settings", mem.address_of(&buf[0usize]), n) { ui.say("ai settings saved\n") }
}

fn load_settings(a: *mem.Arena, s: *State) {
    var buf: [400]u8 = zero
    let (n, found) = vaultfs.read("/ai/settings", mem.address_of(&buf[0usize]), 400usize)
    if !found || n < 6usize { ret }
    s.provider = usize(buf[0]) % 4usize
    s.model = usize(buf[1]) % 3usize
    s.temperature = usize(buf[2])
    if s.temperature > 10usize { s.temperature = 7usize }
    s.tokens = usize(buf[3]) % 4usize
    let sys_len = usize(buf[4])
    var at = 5usize
    s.system.len = 0usize
    var k = 0usize
    while k < sys_len && at < n {
        ui.field_type(&s.system, buf[at], false)
        at += 1usize
        k += 1usize
    }
    if at < n {
        let host_len = usize(buf[at])
        at += 1usize
        s.host.len = 0usize
        k = 0usize
        while k < host_len && at < n {
            ui.field_type(&s.host, buf[at], false)
            at += 1usize
            k += 1usize
        }
    }
    ui.say("ai settings loaded\n")
}

// ----------------------------------------------------------------------------------------------
// Drawing.

fn star_icon() -> str {
    ret "<svg viewBox='0 0 24 24'><path d='M12 2c1 6 4 9 10 10-6 1-9 4-10 10-1-6-4-9-10-10 6-1 9-4 10-10z' fill='currentColor'/></svg>"
}

fn masked(a: *mem.Arena, count: usize) -> str {
    var out = ""
    var i = 0usize
    while i < count && i < 30usize {
        out = ui.join(a, out, "*", "")
        i += 1usize
    }
    ret out
}

fn draw_lock(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, star_icon(), geometry.rect(20.0, 22.0, 26.0, 26.0), ui.amber())
    try ui.put(a, builder, faces.jost_bold, 24.0, "AI", 56.0, 18.0, ui.light())
    var prompt = "Unlock Secure for your saved keys"
    if s.job != 0usize { prompt = "Working on the key..." }
    try ui.centred(a, builder, faces.jost, 17.0, prompt, 206.0, 150.0, ui.light())
    try ui.card(a, builder, 14.0, 210.0, 384.0, 56.0, 18.0, ui.amber())
    try ui.card(a, builder, 16.0, 212.0, 380.0, 52.0, 16.0, ui.cream())
    try ui.put(a, builder, faces.jost, 22.0, masked(a, s.master.len), 32.0, 224.0, ui.ink())
    if s.message_len > 0usize { try ui.centred(a, builder, faces.jost, 15.0, s.message[0usize..s.message_len], 206.0, 290.0, ui.loss()) }
    try ui.pill(a, builder, &s.hits, faces, 170usize, 16.0, 340.0, 186.0, 46.0, "Skip", ui.soft(), 17.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Unlock")
    ret ok
}

fn draw_setup(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "Set up AI", 24.0, 10.0, ui.light())
    var tagline = "Bring your own key: it stays on this device"
    if s.vault_state == VAULT_OPEN { tagline = "Your key is kept in Secure, sealed" }
    try ui.put(a, builder, faces.grotesk, 12.0, tagline, 24.0, 48.0, ui.light_muted())
    var p = 0usize
    while p < 4usize {
        var fill = ui.soft()
        if p == s.provider { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 100usize + p, 16.0 + f32(p % 2usize) * 196.0, 76.0 + f32(p / 2usize) * 48.0, 184.0, 40.0, provider_name(p), fill, 16.0)
        p += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "Model", 24.0, 184.0, ui.light_muted())
    var m = 0usize
    while m < 3usize {
        var fill = ui.soft()
        if m == s.model { fill = ui.amber() }
        try ui.pill(a, builder, &s.hits, faces, 110usize + m, 16.0 + f32(m) * 130.0, 204.0, 120.0, 36.0, model_name(s.provider, m), fill, 15.0)
        m += 1usize
    }
    try ui.put(a, builder, faces.grotesk, 12.0, "API key", 24.0, 260.0, ui.light_muted())
    try ui.card(a, builder, 14.0, 278.0, 384.0, 48.0, 16.0, ui.amber())
    try ui.card(a, builder, 16.0, 280.0, 380.0, 44.0, 14.0, ui.cream())
    if s.key.len == 0usize { try ui.put(a, builder, faces.jost, 17.0, "Paste or type your key", 30.0, 291.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 18.0, masked(a, s.key.len), 30.0, 290.0, 340.0, ui.ink()) }
    try ui.pill(a, builder, &s.hits, faces, 120usize, 16.0, 346.0, 186.0, 46.0, "Save key", ui.amber(), 17.0)
    var other = "Skip for now"
    if s.key_saved { other = "Back to chat" }
    try ui.pill(a, builder, &s.hits, faces, 121usize, 210.0, 346.0, 186.0, 46.0, other, ui.soft(), 17.0)
    try ui.pill(a, builder, &s.hits, faces, 122usize, 16.0, 404.0, 186.0, 40.0, "Options", ui.soft(), 15.0)
    if s.message_len > 0usize { try ui.put(a, builder, faces.jost, 14.0, s.message[0usize..s.message_len], 214.0, 414.0, ui.light()) }
    try ui.keyboard(a, builder, &s.hits, faces, "Save")
    ret ok
}

fn draw_options(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try ui.put(a, builder, faces.jost_bold, 28.0, "Options", 24.0, 10.0, ui.light())
    try ui.put(a, builder, faces.grotesk, 12.0, "System prompt", 24.0, 58.0, ui.light_muted())
    var edge = ui.soft()
    if s.focus == 0usize { edge = ui.amber() }
    try ui.card(a, builder, 14.0, 76.0, 384.0, 48.0, 16.0, edge)
    try ui.card(a, builder, 16.0, 78.0, 380.0, 44.0, 14.0, ui.cream())
    if s.system.len == 0usize { try ui.put(a, builder, faces.jost, 16.0, "How the model should answer", 30.0, 89.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 17.0, ui.field_text(a, &s.system), 30.0, 88.0, 340.0, ui.ink()) }
    ui.hit(&s.hits, 130usize, 14.0, 76.0, 384.0, 48.0)
    try ui.put(a, builder, faces.grotesk, 12.0, "Local server (host or host:port)", 24.0, 134.0, ui.light_muted())
    edge = ui.soft()
    if s.focus == 1usize { edge = ui.amber() }
    try ui.card(a, builder, 14.0, 152.0, 384.0, 48.0, 16.0, edge)
    try ui.card(a, builder, 16.0, 154.0, 380.0, 44.0, 14.0, ui.cream())
    if s.host.len == 0usize { try ui.put(a, builder, faces.jost, 16.0, "neper.test", 30.0, 165.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 17.0, ui.field_text(a, &s.host), 30.0, 164.0, 340.0, ui.ink()) }
    ui.hit(&s.hits, 131usize, 14.0, 152.0, 384.0, 48.0)
    try ui.put(a, builder, faces.grotesk, 12.0, "Temperature", 24.0, 214.0, ui.light_muted())
    try ui.pill(a, builder, &s.hits, faces, 132usize, 16.0, 234.0, 56.0, 40.0, "-", ui.soft(), 18.0)
    try ui.centred(a, builder, faces.jost_bold, 20.0, ui.join(a, ui.join(a, ui.number(a, s.temperature / 10usize), ".", ""), ui.number(a, s.temperature % 10usize), ""), 160.0, 241.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, 133usize, 228.0, 234.0, 56.0, 40.0, "+", ui.soft(), 18.0)
    try ui.pill(a, builder, &s.hits, faces, 134usize, 16.0, 290.0, 240.0, 40.0, ui.join(a, "Up to ", ui.number(a, token_limit(s.tokens)), " tokens"), ui.soft(), 15.0)
    try ui.pill(a, builder, &s.hits, faces, 135usize, 268.0, 290.0, 128.0, 40.0, "Done", ui.amber(), 16.0)
    try ui.keyboard(a, builder, &s.hits, faces, "Next")
    ret ok
}

fn draw_history(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, ui.back_icon(), geometry.rect(18.0, 24.0, 28.0, 28.0), ui.light())
    ui.hit(&s.hits, 140usize, 0.0, 10.0, 66.0, 56.0)
    try ui.put(a, builder, faces.jost_bold, 24.0, "Chats", 62.0, 20.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, 141usize, 190.0, 18.0, 96.0, 36.0, "Search", ui.soft(), 14.0)
    if s.conv != NONE { try ui.pill(a, builder, &s.hits, faces, 142usize, 296.0, 18.0, 100.0, 36.0, "Rename", ui.soft(), 14.0) }
    var shown = 0usize
    var i = 0usize
    while i < MAX_CONVS {
        if s.convs[i].used && s.convs[i].hit {
            let y: f32 = 76.0 + f32(shown) * 72.0
            try ui.card(a, builder, 16.0, y, 380.0, 64.0, 18.0, ui.cream())
            try ui.put(a, builder, faces.jost, 18.0, title_of(a, s, i), 32.0, y + 10.0, ui.ink())
            try ui.put(a, builder, faces.grotesk, 12.0, ui.join(a, ui.number(a, s.convs[i].count), " messages", ""), 32.0, y + 38.0, ui.muted())
            ui.hit(&s.hits, 150usize + i, 16.0, y, 300.0, 64.0)
            try ui.pill(a, builder, &s.hits, faces, 160usize + i, 326.0, y + 14.0, 60.0, 36.0, "Del", ui.soft(), 13.0)
            shown += 1usize
        }
        i += 1usize
    }
    if shown == 0usize {
        var empty = "No chats yet"
        if s.query.len > 0usize { empty = "Nothing matches" }
        try ui.centred(a, builder, faces.jost, 18.0, empty, 206.0, 240.0, ui.light_muted())
    }
    if s.searching || s.renaming {
        var label = "Find"
        var shown_field = &s.query
        if s.renaming {
            label = "New title"
            shown_field = &s.draft
        }
        try ui.card(a, builder, 14.0, 430.0, 384.0, 48.0, 16.0, ui.amber())
        try ui.card(a, builder, 16.0, 432.0, 380.0, 44.0, 14.0, ui.cream())
        try ui.clipped(a, builder, faces.jost, 18.0, ui.field_text(a, shown_field), 30.0, 442.0, 340.0, ui.ink())
        try ui.keyboard(a, builder, &s.hits, faces, label)
    }
    ret ok
}

fn draw_chat(a: *mem.Arena, builder: *scene.Builder, s: *State, faces: text.Faces) -> err {
    try svg.draw(a, builder, star_icon(), geometry.rect(20.0, 22.0, 26.0, 26.0), ui.amber())
    try ui.put(a, builder, faces.jost_bold, 24.0, "AI", 56.0, 18.0, ui.light())
    try ui.pill(a, builder, &s.hits, faces, 200usize, 104.0, 18.0, 132.0, 34.0, ui.join(a, ui.join(a, provider_name(s.provider), " ", ""), model_name(s.provider, s.model), ""), ui.soft(), 12.0)
    try ui.pill(a, builder, &s.hits, faces, 202usize, 242.0, 18.0, 80.0, 34.0, "Chats", ui.soft(), 13.0)
    try ui.pill(a, builder, &s.hits, faces, 201usize, 328.0, 18.0, 68.0, 34.0, "New", ui.soft(), 13.0)
    try ui.put(a, builder, faces.grotesk, 11.0, "Your messages go to the provider you chose", 24.0, 60.0, ui.light_muted())
    // The messages from the bottom up.
    var bottom: f32 = 780.0
    if s.typing { bottom = 440.0 }
    var y = bottom
    var shown = 0usize
    var k = s.msg_total
    var room = true
    // The reply being written is the last bubble.
    if s.replying {
        var part = ui.text_of(a, s.reply[0usize..], s.reply_len)
        if s.reply_len == 0usize { part = "..." }
        let (placed, placed_error) = text.lay_out(a, faces.jost, 16.0, part, 270.0, 0u32, layout.Align.Start)
        var h: f32 = 24.0
        if placed_error == ok { h = placed.bounds.height }
        y -= h + 24.0
        try ui.card(a, builder, 16.0, y, 300.0, h + 18.0, 16.0, ui.cream())
        let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, part, 30.0, y + 9.0, 270.0, 0u32, ui.ink())
        if box_error != ok { ret box_error }
        y -= 8.0
    }
    while room && k > 0usize {
        k -= 1usize
        let m = s.msgs[k]
        let body_text = ui.text_of(a, m.body[0usize..], m.body_len)
        let (placed, placed_error) = text.lay_out(a, faces.jost, 16.0, body_text, 270.0, 0u32, layout.Align.Start)
        var h: f32 = 24.0
        var w: f32 = 270.0
        if placed_error == ok {
            h = placed.bounds.height
            w = placed.bounds.width
        }
        y -= h + 24.0
        if y < 84.0 {
            room = false
        } else {
            if m.mine {
                try ui.card(a, builder, 396.0 - w - 28.0, y, w + 28.0, h + 18.0, 16.0, ui.amber())
                let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, body_text, 396.0 - w - 14.0, y + 9.0, 270.0, 0u32, ui.ink())
                if box_error != ok { ret box_error }
            } else {
                try ui.card(a, builder, 16.0, y, 300.0, h + 18.0, 16.0, ui.cream())
                let (box, box_error) = ui.wrapped(a, builder, faces.jost, 16.0, body_text, 30.0, y + 9.0, 270.0, 0u32, ui.ink())
                if box_error != ok { ret box_error }
            }
            y -= 8.0
            shown += 1usize
        }
    }
    if s.msg_total == 0usize && !s.replying { try ui.centred(a, builder, faces.jost, 18.0, "Ask me anything", 206.0, 260.0, ui.light_muted()) }
    var box_y: f32 = 800.0
    if s.typing { box_y = 446.0 }
    if s.clip_len > 0usize { try ui.pill(a, builder, &s.hits, faces, 212usize, 16.0, box_y - 44.0, 96.0, 36.0, "Paste", ui.soft(), 14.0) }
    try ui.card(a, builder, 16.0, box_y, 322.0, 46.0, 23.0, ui.cream())
    if s.draft.len == 0usize { try ui.put(a, builder, faces.jost, 16.0, "Message", 34.0, box_y + 13.0, ui.muted()) } else { try ui.clipped(a, builder, faces.jost, 16.0, ui.field_text(a, &s.draft), 34.0, box_y + 13.0, 290.0, ui.ink()) }
    ui.hit(&s.hits, 210usize, 16.0, box_y, 322.0, 46.0)
    var send_fill = ui.soft()
    if s.draft.len > 0usize { send_fill = ui.amber() }
    try ui.disc(a, builder, 368.0, box_y + 23.0, 24.0, send_fill)
    try ui.centred(a, builder, faces.jost_bold, 16.0, ">", 368.0, box_y + 13.0, ui.ink())
    ui.hit(&s.hits, 211usize, 340.0, box_y, 56.0, 46.0)
    if s.typing { try ui.keyboard(a, builder, &s.hits, faces, "Send") }
    ret ok
}

// The wall-clock second now, 0 when there is no clock.
fn wall_seconds() -> usize {
    let (wall, wall_error) = time.now()
    if wall_error != ok || wall.nanos < 0i64 { ret 0usize }
    ret usize(wall.nanos / 1000000000i64)
}

fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {
    s.hits.total = 0usize
    var clip_bytes: [32]u8 = zero
    let (clip_length, clip_owner) = sysettings.clip_get(wall_seconds(), clip_bytes[0usize..])
    s.clip_len = clip_length
    let faces = kit.faces
    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)
    if s.screen == SETUP_SCREEN { try draw_setup(a, builder, s, faces) }
    if s.screen == CHAT_SCREEN { try draw_chat(a, builder, s, faces) }
    if s.screen == LOCK_SCREEN { try draw_lock(a, builder, s, faces) }
    if s.screen == HISTORY_SCREEN { try draw_history(a, builder, s, faces) }
    if s.screen == OPTIONS_SCREEN { try draw_options(a, builder, s, faces) }
    try ui.handle(a, builder)
    ret ok
}

fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {
    let (next, next_error) = appkit.begin(a, kit)
    if next_error != ok { ret false }
    var builder = next
    if draw(a, &builder, kit, s) != ok { ret false }
    ret appkit.present(kit, &builder)
}

// ----------------------------------------------------------------------------------------------
// Behaviour.

// The reply is whole (or failed): it becomes a bubble, the conversation is kept.
fn finish_reply(a: *mem.Arena, s: *State, ok_reply: bool) {
    s.streaming = false
    s.replying = false
    if ok_reply {
        ui.say("ai text ")
        ui.say_text(ui.text_of(a, s.reply[0usize..], s.reply_len))
        ui.say("\n")
    } else {
        ui.say("ai failed ")
        ui.say_text(ui.text_of(a, s.reply[0usize..], s.reply_len))
        ui.say("\n")
    }
    add_msg(s, false, ui.text_of(a, s.reply[0usize..], s.reply_len))
    if ok_reply { save_conv(a, s) }
    ui.say("ai sent\n")
    ui.say("ai reply\n")
}

// One tick of a reply in flight: take what has arrived, read the events it completes, show their text. True when
// the screen changed.
fn stream_step(a: *mem.Arena, s: *State) -> bool {
    var changed = false
    var polls = 0usize
    var got_any = false
    while polls < 6usize && s.net.phase != httpstream.PH_DONE {
        let before = s.net.body_len
        let before_head = s.net.head_len
        let got = httpstream.pump(&s.net)
        if got == netproto.R_EMPTY {
            polls = 6usize
        } else {
            polls += 1usize
            if s.net.body_len != before || s.net.head_len != before_head { got_any = true }
        }
    }
    if got_any { s.silent = 0usize } else { s.silent += 1usize }
    // A status other than 200 ends the reply at once.
    if s.net.phase != httpstream.PH_HEAD && s.net.status != 200usize && s.net.status != 0usize {
        httpstream.abort(&s.net)
        set_reply(s, status_words(a, s, s.net.status))
        finish_reply(a, s, false)
        ret true
    }
    if s.net.failed && s.net.body_len == 0usize {
        httpstream.abort(&s.net)
        set_reply(s, "The reply did not arrive whole.")
        finish_reply(a, s, false)
        ret true
    }
    // The events the body completes.
    var key = "content"
    if s.provider == 0usize || s.provider == 2usize { key = "text" }
    var done = false
    var failed_event = false
    var more = s.net.body_len > s.sse_at
    while more && !done {
        let (event, next_at, whole, sse_error) = sse.next(a, s.body[0usize..s.net.body_len], s.sse_at)
        if sse_error != ok || !whole {
            more = false
        } else {
            s.sse_at = next_at
            s.events += 1usize
            if ui.same(event.data, "[DONE]") || ui.same(event.kind, "message_stop") {
                done = true
            } else if ui.same(event.kind, "error") {
                failed_event = true
                done = true
            } else {
                var piece: [400]u8 = zero
                let n = extract_text(event.data, key, piece[0usize..])
                if n > 0usize {
                    append_reply(s, piece[0usize..], n)
                    s.pieces += 1usize
                    changed = true
                    ui.say("ai stream part ")
                    ui.say_num(s.reply_len)
                    ui.say("\n")
                }
            }
        }
    }
    if failed_event {
        httpstream.abort(&s.net)
        set_reply(s, "The provider reported an error.")
        finish_reply(a, s, false)
        ret true
    }
    if done || s.net.phase == httpstream.PH_DONE {
        httpstream.abort(&s.net)
        if s.reply_len == 0usize && s.net.body_len > 0usize {
            // No stream came: the whole answer as one JSON document, as before.
            let n = extract_text(ui.text_of(a, s.body[0usize..], s.net.body_len), key, s.reply[0usize..])
            s.reply_len = n
        }
        if s.reply_len == 0usize {
            set_reply(s, "The reply held no text.")
            finish_reply(a, s, false)
        } else {
            finish_reply(a, s, true)
        }
        ret true
    }
    if s.silent > SILENT_LIMIT {
        httpstream.abort(&s.net)
        set_reply(s, "The reply took too long.")
        finish_reply(a, s, false)
        ret true
    }
    ret changed
}

fn send(a: *mem.Arena, s: *State) {
    if s.draft.len == 0usize || s.streaming { ret }
    let message = ui.field_text(a, &s.draft)
    add_msg(s, true, message)
    s.draft.len = 0usize
    if start_request(a, s) {
        s.streaming = true
        s.replying = true
        ui.say("ai stream start\n")
    } else {
        finish_reply(a, s, false)
    }
}

// Save the typed key: checked against the provider first, then sealed in the vault when there is one.
fn save_key(a: *mem.Arena, s: *State) {
    s.message_len = 0usize
    s.key_saved = s.key.len > 0usize || s.provider == 3usize
    if !s.key_saved { ret }
    if s.key.len > 0usize {
        let verdict = check_key(a, s)
        if verdict == 1usize {
            s.key_saved = false
            say_message(s, "The provider refused this key")
            ui.say("ai key refused\n")
            ret
        }
        if verdict == 0usize { ui.say("ai key checked\n") } else { ui.say("ai key not checked\n") }
        if s.vault_state == VAULT_OPEN {
            if store_key(a, s) {
                ui.say("ai key stored in secure\n")
                wipe_key(s)
            } else {
                ui.say("ai key store failed\n")
            }
        }
    }
    s.screen = CHAT_SCREEN
    // The provider and model chosen are kept with the options, so the next start asks the vault for the right key.
    if s.vault_state == VAULT_OPEN { save_settings(a, s) }
    ui.say("ai key saved\n")
}

fn open_history(a: *mem.Arena, s: *State) {
    s.query.len = 0usize
    s.searching = false
    s.renaming = false
    let listed = list_convs(a, s)
    s.screen = HISTORY_SCREEN
    ui.say("ai chats ")
    ui.say_num(listed)
    ui.say("\n")
}

fn act(a: *mem.Arena, s: *State, id: usize) -> bool {
    if s.job != 0usize || s.streaming { ret false }
    if s.screen == LOCK_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.master.len == 0usize { ret true }
                s.job = 1usize
                ui.say("ai unlocking\n")
                ret true
            }
            s.message_len = 0usize
            ret ui.field_key(&s.master, id, false)
        }
        if id == 170usize {
            s.screen = SETUP_SCREEN
            s.master.len = 0usize
            ret true
        }
        ret false
    }
    if s.screen == OPTIONS_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.focus == 0usize { s.focus = 1usize } else {
                    save_settings(a, s)
                    s.screen = SETUP_SCREEN
                }
                ret true
            }
            if s.focus == 0usize { ret ui.field_key(&s.system, id, false) }
            ret ui.field_key(&s.host, id, false)
        }
        if id == 130usize || id == 131usize {
            s.focus = id - 130usize
            ret true
        }
        if id == 132usize {
            if s.temperature > 0usize { s.temperature -= 1usize }
            ret true
        }
        if id == 133usize {
            if s.temperature < 10usize { s.temperature += 1usize }
            ret true
        }
        if id == 134usize {
            s.tokens = (s.tokens + 1usize) % 4usize
            ret true
        }
        if id == 135usize {
            save_settings(a, s)
            s.screen = SETUP_SCREEN
            ret true
        }
        ret false
    }
    if s.screen == HISTORY_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                if s.renaming {
                    rename_conv(a, s, ui.field_text(a, &s.draft))
                    s.draft.len = 0usize
                    s.renaming = false
                } else {
                    s.searching = false
                }
                let listed = list_convs(a, s)
                ui.say("ai chats ")
                ui.say_num(listed)
                ui.say("\n")
                ret true
            }
            if s.renaming { ret ui.field_key(&s.draft, id, false) }
            ret ui.field_key(&s.query, id, false)
        }
        if id == 140usize {
            s.screen = CHAT_SCREEN
            ret true
        }
        if id == 141usize {
            s.searching = true
            s.renaming = false
            s.query.len = 0usize
            ret true
        }
        if id == 142usize {
            s.renaming = true
            s.searching = false
            s.draft.len = 0usize
            ret true
        }
        if id >= 150usize && id < 150usize + MAX_CONVS {
            let c = id - 150usize
            if read_conv(a, s, c, true) {
                s.conv = c
                s.screen = CHAT_SCREEN
                s.typing = false
                ui.say("ai opened chat ")
                ui.say_text(title_of(a, s, c))
                ui.say("\n")
            }
            ret true
        }
        if id >= 160usize && id < 160usize + MAX_CONVS {
            let c = id - 160usize
            if vaultfs.remove(conv_path(a, c)) {
                if s.conv == c {
                    s.conv = NONE
                    s.msg_total = 0usize
                }
                ui.say("ai deleted chat ")
                ui.say_num(c)
                ui.say("\n")
            }
            let listed = list_convs(a, s)
            ret true
        }
        ret false
    }
    if s.screen == SETUP_SCREEN {
        if ui.is_key(id) {
            if id == 1205usize {
                save_key(a, s)
                ret true
            }
            ret ui.field_key(&s.key, id, false)
        }
        if id >= 100usize && id < 104usize {
            s.provider = id - 100usize
            s.model = 0usize
            s.message_len = 0usize
            ui.say("ai provider ")
            ui.say(provider_name(s.provider))
            ui.say("\n")
            if s.vault_state == VAULT_OPEN {
                if load_key(a, s) { ui.say("ai key from secure\n") }
            }
            ret true
        }
        if id >= 110usize && id < 113usize {
            s.model = id - 110usize
            ret true
        }
        if id == 120usize {
            save_key(a, s)
            ret true
        }
        if id == 121usize {
            s.screen = CHAT_SCREEN
            ret true
        }
        if id == 122usize {
            s.screen = OPTIONS_SCREEN
            s.focus = 0usize
            ret true
        }
        ret false
    }
    if id == 200usize {
        s.screen = SETUP_SCREEN
        ret true
    }
    if id == 201usize {
        s.msg_total = 0usize
        s.replying = false
        s.conv = NONE
        ui.say("ai new chat\n")
        ret true
    }
    if id == 202usize {
        open_history(a, s)
        ret true
    }
    if id == 210usize {
        s.typing = true
        ret true
    }
    if id == 212usize {
        var clip_bytes: [32]u8 = zero
        let (clip_length, clip_owner) = sysettings.clip_get(wall_seconds(), clip_bytes[0usize..])
        if clip_length == 0usize { ret true }
        let pasted = ui.field_paste(&s.draft, clip_bytes[0usize..], clip_length)
        s.typing = true
        ui.say("ai pasted ")
        ui.say_num(pasted)
        ui.say(" bytes\n")
        ret true
    }
    if id == 211usize {
        send(a, s)
        ret true
    }
    if ui.is_key(id) {
        if id == 1205usize {
            send(a, s)
            ret true
        }
        if id == 1206usize {
            // The keyboard's Paste key (C175).
            let before = s.draft.len
            let did = ui.field_key(&s.draft, id, true)
            ui.say("ai keyboard pasted ")
            ui.say_num(s.draft.len - before)
            ui.say(" bytes\n")
            ret did
        }
        ret ui.field_key(&s.draft, id, true)
    }
    ret false
}

// The work behind Unlock, done on a tick so the screen can say it is working first.
fn run_job(a: *mem.Arena, s: *State) {
    s.job = 0usize
    let opened = unlock_vault(a, s)
    s.master.len = 0usize
    if opened == 0usize {
        s.vault_state = VAULT_OPEN
        s.message_len = 0usize
        s.screen = SETUP_SCREEN
        ui.say("ai unlocked\n")
        if load_key(a, s) {
            ui.say("ai key from secure\n")
        }
    } else if opened == 1usize {
        say_message(s, "Wrong password. Try again.")
        ui.say("ai wrong password\n")
    } else {
        say_message(s, "The vault could not be read")
        ui.say("ai vault unreadable\n")
    }
}

fn main(a: *mem.Arena, args: []str) -> err {
    // The buffer a reply's body is decoded into outlives the frames, so it is taken before the kit's frame mark.
    let (body_store, body_error) = mem.alloc[u8](a, BODY_CAP)
    if body_error != ok {
        ui.say("ai open failed\n")
        ret ok
    }
    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "ai")
    if kit_error != ok {
        ui.say("ai open failed\n")
        ret ok
    }
    var kit = kit_value
    if !kit.has_fonts {
        ui.say("ai fonts absent\n")
        ret ok
    }
    var s: State = zero
    s.screen = SETUP_SCREEN
    s.conv = NONE
    s.temperature = 7usize
    s.tokens = 2usize
    s.body = body_store
    // Storage and a vault made by Secure: with the filesystem reachable the settings come back, and a vault asks
    // for its master password before anything else.
    let (reachable, has_vault) = vaultfs.probe("/vmeta")
    if reachable {
        load_settings(a, &s)
        if has_vault {
            s.vault_state = VAULT_LOCKED
            s.screen = LOCK_SCREEN
            ui.say("ai vault locked\n")
        }
    }
    if !show(a, &kit, &s) {
        ui.say("ai present failed\n")
        ret ok
    }
    ui.say("ai shown\n")
    var running = true
    while running {
        let tap = appkit.next_tap(&kit)
        if tap.ended {
            running = false
        } else if tap.tick {
            if s.job != 0usize {
                run_job(a, &s)
                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
            } else if s.streaming {
                // The reply arrives a poll at a time, on the compositor's ticks.
                if stream_step(a, &s) {
                    if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }
                } else {
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        } else if tap.y >= 896.0 {
            if s.streaming { httpstream.abort(&s.net) }
            wipe_key(&s)
            ui.say("ai home\n")
            appkit.leave()
            running = false
        } else {
            let id = ui.hit_at(&s.hits, tap.x, tap.y)
            if id != ui.NONE && act(a, &s, id) {
                if !show(a, &kit, &s) {
                    ui.say("ai present failed\n")
                    appkit.answer(appkit.ANSWER_NONE)
                }
            } else {
                appkit.answer(appkit.ANSWER_NONE)
            }
        }
    }
    ret ok
}
