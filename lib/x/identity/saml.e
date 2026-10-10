// SAML 2.0 service provider, Web Browser SSO profile (L045), after Appdor's `src/identity/saml.js`: the AuthnRequest and
// its HTTP-Redirect (stored-block deflate) or HTTP-POST carrier, XML-DSig verification (SHA-256 digest of the exclusively
// canonicalised referenced element with the enveloped-signature transform, RSA-SHA256 over the canonical SignedInfo, SHA-1
// refused by name), the wrapping defence (one Assertion, and the signature's Reference must name it or an ancestor), the
// eight validation steps in the reference's order, a bounded replay cache, the RSA key out of a certificate, and SP and IdP
// metadata. Every refusal is the reference's greppable token. There is no way to turn verification off.
//
// ponytail: a timestamp without a zone is read as UTC (the reference reads it in the host's zone); `Date.parse`'s legacy
// formats are not read, an unparseable instant is "absent".
//
// Memory: the arena is retained.

use e.algo.formula as f
use e.algo.ir as ir
use e.crypto.hash as hash
use e.fmt.json as json
use e.mem
use e.str
use x.identity.jose as jose
use x.identity.oidc as oidc
use x.identity.xml as xml

type Key = struct { has: bool, n: str, e: str }

type Signed = struct { valid: bool, message: str, id: str, assertion: usize, signed_element: str }

type Assertion = struct { present: bool, id: str, issuer: str, has_name_id: bool, name_id: str, name_id_format: str, session_index: str, authn_instant: str, not_before: str, not_on_or_after: str, audiences: []const str, recipient: str, confirmation_not_on_or_after: str, confirmation_in_response_to: str, attr_names: []const str, attr_values: []const []const str }

type Response = struct { valid: bool, message: str, doc: xml.Doc, id: str, in_response_to: str, destination: str, issue_instant: str, issuer: str, status_present: bool, status_has_value: bool, status_code: str, status_message: str, assertion: Assertion }

type Config = struct { issuer: str, audience: str, acs_url: str, key: Key, expected_in_response_to: str, now: f64, has_skew: bool, skew_ms: f64, seen: []const str }

type Validation = struct { valid: bool, message: str, detail: str, has_detail: bool, assertion_id: str, signed_element: str, assertion: Assertion, expires_at: f64, has_expiry: bool }

type Request = struct { valid: bool, missing: []const str, binding: str, xml: str, form_action: str, saml_request: str, relay_state: str, url: str }

type ReplayCache = struct { ids: []str, expiries: []f64, count: usize }

fn join(a: *mem.Arena, x: str, y: str) -> str { ret f.join(a, x, y) }

fn ns_protocol() -> str { ret "urn:oasis:names:tc:SAML:2.0:protocol" }
fn ns_assertion() -> str { ret "urn:oasis:names:tc:SAML:2.0:assertion" }
fn ns_signature() -> str { ret "http://www.w3.org/2000/09/xmldsig#" }
fn ns_metadata() -> str { ret "urn:oasis:names:tc:SAML:2.0:metadata" }
fn status_success() -> str { ret "urn:oasis:names:tc:SAML:2.0:status:Success" }
fn binding_post() -> str { ret "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST" }
fn binding_redirect() -> str { ret "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect" }
fn nameid_email() -> str { ret "urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress" }

// Standard (padded) base64.
fn to_base64(a: *mem.Arena, bytes: []const u8) -> str {
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    let (out, e) = mem.alloc[u8](a, bytes.len / 3usize * 4usize + 5usize)
    if e != ok { ret "" }
    var n = 0usize
    var i = 0usize
    while i < bytes.len {
        let b0 = u32(bytes[i])
        var b1 = 0u32
        var b2 = 0u32
        let has1 = i + 1usize < bytes.len
        let has2 = i + 2usize < bytes.len
        if has1 { b1 = u32(bytes[i + 1usize]) }
        if has2 { b2 = u32(bytes[i + 2usize]) }
        out[n] = alphabet[usize(b0 >> 2u32)]
        out[n + 1usize] = alphabet[usize(((b0 & 3u32) << 4u32) | (b1 >> 4u32))]
        if has1 {
            out[n + 2usize] = alphabet[usize(((b1 & 15u32) << 2u32) | (b2 >> 6u32))]
        } else {
            out[n + 2usize] = 61u8
        }
        if has2 {
            out[n + 3usize] = alphabet[usize(b2 & 63u32)]
        } else {
            out[n + 3usize] = 61u8
        }
        n += 4usize
        i += 3usize
    }
    ret out[0usize..n]
}

// Standard base64 with the whitespace IdPs insert tolerated.
fn from_base64(a: *mem.Arena, s: str) -> []u8 { ret jose.base64url_decode(a, s) }

fn xml_escape(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len * 6usize + 1usize)
    if e != ok { ret s }
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        var rep = ""
        if c == 38u8 { rep = "&amp;" }
        if c == 60u8 { rep = "&lt;" }
        if c == 62u8 { rep = "&gt;" }
        if c == 34u8 { rep = "&quot;" }
        if rep.len == 0usize {
            out[n] = c
            n += 1usize
        } else {
            var k = 0usize
            while k < rep.len {
                out[n] = rep[k]
                n += 1usize
                k += 1usize
            }
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// Raw DEFLATE in stored blocks: a conformant stream any inflater accepts.
fn deflate_raw_stored(a: *mem.Arena, bytes: []const u8) -> []u8 {
    let blocks = bytes.len / 65535usize + 1usize
    let (out, e) = mem.alloc[u8](a, bytes.len + blocks * 5usize + 8usize)
    if e != ok { ret out }
    var n = 0usize
    var offset = 0usize
    while offset < bytes.len || offset == 0usize {
        var take = bytes.len - offset
        if take > 65535usize { take = 65535usize }
        var last = 0u8
        if offset + 65535usize >= bytes.len { last = 1u8 }
        out[n] = last
        out[n + 1usize] = u8(take & 255usize)
        out[n + 2usize] = u8((take >> 8usize) & 255usize)
        let inverted = 65535usize - take
        out[n + 3usize] = u8(inverted & 255usize)
        out[n + 4usize] = u8((inverted >> 8usize) & 255usize)
        n += 5usize
        var k = 0usize
        while k < take {
            out[n + k] = bytes[offset + k]
            k += 1usize
        }
        n += take
        if last == 1u8 { break }
        offset += 65535usize
    }
    ret out[0usize..n]
}

// `_` and the first 32 hex digits of SHA-256(seed): SAML ids start with a letter or underscore.
fn saml_id(a: *mem.Arena, seed: str) -> str {
    let digest = hash.sha256(seed)
    let hex = "0123456789abcdef"
    let (out, e) = mem.alloc[u8](a, 33usize)
    if e != ok { ret "_" }
    out[0] = 95u8
    var i = 0usize
    while i < 16usize {
        out[1usize + i * 2usize] = hex[usize(digest[i] >> 4u8)]
        out[2usize + i * 2usize] = hex[usize(digest[i] & 15u8)]
        i += 1usize
    }
    ret out[0usize..33usize]
}

fn missing_names(a: *mem.Arena, names: []const str, present: []const bool) -> []const str {
    let (out, e) = mem.alloc[str](a, names.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < names.len {
        if !present[i] {
            out[n] = names[i]
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

// An AuthnRequest and the form or URL that carries it; `force_authn` and `relay_state` are optional.
fn build_authn_request(a: *mem.Arena, id: str, issue_instant: str, destination: str, issuer: str, acs_url: str, name_id_format: str, force_authn: bool, relay_state: str, binding: str) -> Request {
    let names = [5]str{ "id", "issueInstant", "destination", "issuer", "acsUrl" }
    let present = [5]bool{ id.len > 0usize, issue_instant.len > 0usize, destination.len > 0usize, issuer.len > 0usize, acs_url.len > 0usize }
    let missing = missing_names(a, names[0usize..5usize], present[0usize..5usize])
    if missing.len > 0usize { ret Request { valid: false, missing: missing, binding: "", xml: "", form_action: "", saml_request: "", relay_state: "", url: "" } }
    var attrs = "xmlns:samlp=\"urn:oasis:names:tc:SAML:2.0:protocol\" xmlns:saml=\"urn:oasis:names:tc:SAML:2.0:assertion\""
    attrs = join(a, attrs, join(a, " ID=\"", join(a, id, "\"")))
    attrs = join(a, attrs, " Version=\"2.0\"")
    attrs = join(a, attrs, join(a, " IssueInstant=\"", join(a, issue_instant, "\"")))
    attrs = join(a, attrs, join(a, " Destination=\"", join(a, xml_escape(a, destination), "\"")))
    attrs = join(a, attrs, join(a, " AssertionConsumerServiceURL=\"", join(a, xml_escape(a, acs_url), "\"")))
    attrs = join(a, attrs, join(a, " ProtocolBinding=\"", join(a, binding_post(), "\"")))
    if force_authn { attrs = join(a, attrs, " ForceAuthn=\"true\"") }
    var policy = ""
    if name_id_format.len > 0usize {
        policy = join(a, "<samlp:NameIDPolicy Format=\"", join(a, xml_escape(a, name_id_format), "\" AllowCreate=\"true\"/>"))
    }
    var body = join(a, join(a, "<samlp:AuthnRequest ", attrs), ">")
    body = join(a, body, join(a, "<saml:Issuer>", join(a, xml_escape(a, issuer), "</saml:Issuer>")))
    body = join(a, body, policy)
    body = join(a, body, "</samlp:AuthnRequest>")
    if str.eq(binding, binding_post()) {
        ret Request { valid: true, missing: zero, binding: binding, xml: body, form_action: destination, saml_request: to_base64(a, body), relay_state: relay_state, url: "" }
    }
    let encoded = to_base64(a, deflate_raw_stored(a, body))
    var query = join(a, "SAMLRequest=", oidc.form_encode(a, encoded))
    if relay_state.len > 0usize { query = join(a, query, join(a, "&RelayState=", oidc.form_encode(a, relay_state))) }
    var joiner = "?"
    if str.contains(destination, "?") { joiner = "&" }
    ret Request { valid: true, missing: zero, binding: binding, xml: body, form_action: "", saml_request: "", relay_state: "", url: join(a, join(a, destination, joiner), query) }
}

fn split_words(a: *mem.Arena, s: str) -> []const str {
    let (out, e) = mem.alloc[str](a, s.len / 2usize + 2usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        while i < s.len && (s[i] == 32u8 || s[i] == 9u8 || s[i] == 10u8 || s[i] == 13u8) { i += 1usize }
        let from = i
        while i < s.len && !(s[i] == 32u8 || s[i] == 9u8 || s[i] == 10u8 || s[i] == 13u8) { i += 1usize }
        if i > from {
            out[n] = s[from..i]
            n += 1usize
        }
    }
    ret out[0usize..n]
}

fn strip_ws(a: *mem.Arena, s: str) -> str {
    let (out, e) = mem.alloc[u8](a, s.len + 1usize)
    var n = 0usize
    var i = 0usize
    while i < s.len {
        let c = s[i]
        if !(c == 32u8 || c == 9u8 || c == 10u8 || c == 13u8 || c == 11u8 || c == 12u8) {
            out[n] = c
            n += 1usize
        }
        i += 1usize
    }
    ret out[0usize..n]
}

fn trimmed(s: str) -> str {
    var from = 0usize
    var to = s.len
    while from < to && (s[from] == 32u8 || s[from] == 9u8 || s[from] == 10u8 || s[from] == 13u8 || s[from] == 11u8 || s[from] == 12u8) { from += 1usize }
    while to > from && (s[to - 1usize] == 32u8 || s[to - 1usize] == 9u8 || s[to - 1usize] == 10u8 || s[to - 1usize] == 13u8 || s[to - 1usize] == 11u8 || s[to - 1usize] == 12u8) { to -= 1usize }
    ret s[from..to]
}

fn attr_or_undefined(a: *mem.Arena, d: xml.Doc, at: usize, has: bool, name: str) -> str {
    if !has { ret "undefined" }
    let (v, found) = xml.attribute_of(d.nodes[at], name)
    if !found { ret "undefined" }
    ret v
}

fn prefixes_of(a: *mem.Arena, d: xml.Doc, at: usize) -> []const str {
    let (inc, has) = xml.find_element(a, d, at, "http://www.w3.org/2001/10/xml-exc-c14n#", "InclusiveNamespaces")
    if !has { ret zero }
    let (list, found) = xml.attribute_of(d.nodes[inc], "PrefixList")
    if !found || list.len == 0usize { ret zero }
    ret split_words(a, list)
}

fn failed(msg: str) -> Signed { ret Signed { valid: false, message: msg, id: "", assertion: 0usize, signed_element: "" } }

// An enveloped XML signature over the document, against an RSA key; `id` is the Reference's target.
fn verify_xml_signature(a: *mem.Arena, d: xml.Doc, signature: usize, has_signature: bool, key: Key) -> Signed {
    if !has_signature { ret failed("no-signature") }
    let (signed_info, has_si) = xml.find_element(a, d, signature, ns_signature(), "SignedInfo")
    if !has_si { ret failed("no-SignedInfo") }
    let (method, has_method) = xml.find_element(a, d, signed_info, ns_signature(), "SignatureMethod")
    var algorithm = ""
    var has_alg = false
    if has_method {
        let (v, found) = xml.attribute_of(d.nodes[method], "Algorithm")
        algorithm = v
        has_alg = found
    }
    if !has_alg || !str.eq(algorithm, "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256") {
        var shown = "undefined"
        if has_alg { shown = algorithm }
        ret failed(join(a, "unsupported-SignatureMethod: ", shown))
    }
    let (reference, has_ref) = xml.find_element(a, d, signed_info, ns_signature(), "Reference")
    if !has_ref { ret failed("no-Reference") }
    let (uri, has_uri) = xml.attribute_of(d.nodes[reference], "URI")
    var target_uri = ""
    if has_uri { target_uri = uri }
    if !str.starts_with(target_uri, "#") {
        var shown = target_uri
        if shown.len == 0usize { shown = "(empty)" }
        ret failed(join(a, "unsupported-Reference-URI: ", shown))
    }
    let (referenced, has_referenced) = xml.find_by_id(d, d.root, target_uri[1usize..])
    if !has_referenced { ret failed(join(a, "Reference-URI-matches-no-element: ", target_uri)) }
    let (digest_method, has_dm) = xml.find_element(a, d, reference, ns_signature(), "DigestMethod")
    var digest_alg = ""
    var has_digest_alg = false
    if has_dm {
        let (v, found) = xml.attribute_of(d.nodes[digest_method], "Algorithm")
        digest_alg = v
        has_digest_alg = found
    }
    if !has_digest_alg || !str.eq(digest_alg, "http://www.w3.org/2001/04/xmlenc#sha256") {
        var shown = "undefined"
        if has_digest_alg { shown = digest_alg }
        ret failed(join(a, "unsupported-DigestMethod: ", shown))
    }
    let (digest_value, has_dv) = xml.find_element(a, d, reference, ns_signature(), "DigestValue")
    if !has_dv { ret failed("no-DigestValue") }
    let (stripped, apex) = xml.without_signature(a, d, referenced)
    let canonical = xml.canonicalize(a, stripped, apex, prefixes_of(a, d, reference))
    let canonical_digest = hash.sha256(canonical)
    let actual = to_base64(a, canonical_digest[0usize..32usize])
    let expected = strip_ws(a, d.nodes[digest_value].text)
    if !str.eq(actual, expected) { ret failed("digest-mismatch") }
    let canonical_info = xml.canonicalize(a, d, signed_info, prefixes_of(a, d, signed_info))
    let (sig_value, has_sv) = xml.find_element(a, d, signature, ns_signature(), "SignatureValue")
    if !has_sv { ret failed("no-SignatureValue") }
    let sig_bytes = from_base64(a, d.nodes[sig_value].text)
    var good = false
    if key.has && key.n.len > 0usize && key.e.len > 0usize {
        good = jose.verify_rs256(a, canonical_info, sig_bytes, key.n, key.e)
    }
    if !good { ret failed("SignatureValue-mismatch") }
    ret Signed { valid: true, message: "", id: target_uri[1usize..], assertion: 0usize, signed_element: "" }
}

// The one Assertion the response's signature covers.
fn extract_signed_assertion(a: *mem.Arena, d: xml.Doc, key: Key) -> Signed {
    let assertions = xml.find_elements(a, d, d.root, ns_assertion(), "Assertion")
    if assertions.len == 0usize { ret failed("no-Assertion") }
    if assertions.len > 1usize { ret failed("multiple-Assertions") }
    let signatures = xml.find_elements(a, d, d.root, ns_signature(), "Signature")
    if signatures.len == 0usize { ret failed("response-not-signed") }
    var last = "no-signature-covers-assertion"
    var i = 0usize
    while i < signatures.len {
        let r = verify_xml_signature(a, d, signatures[i], true, key)
        i += 1usize
        if !r.valid {
            last = r.message
            continue
        }
        let (covered, has_cov) = xml.find_by_id(d, d.root, r.id)
        var cur = i64(assertions[0])
        while cur >= 0i64 {
            if has_cov && usize(cur) == covered {
                ret Signed { valid: true, message: "", id: "", assertion: assertions[0], signed_element: d.nodes[covered].local }
            }
            cur = d.nodes[usize(cur)].parent
        }
        last = "signature-covers-unrelated-element"
    }
    ret failed(last)
}

fn empty_assertion() -> Assertion {
    let none: []const str = zero
    let nones: []const []const str = zero
    ret Assertion {
        present: false, id: "", issuer: "", has_name_id: false, name_id: "", name_id_format: "", session_index: "", authn_instant: "",
        not_before: "", not_on_or_after: "", audiences: none, recipient: "", confirmation_not_on_or_after: "", confirmation_in_response_to: "",
        attr_names: none, attr_values: nones,
    }
}

fn attr_text(d: xml.Doc, at: usize, name: str) -> str {
    let (v, found) = xml.attribute_of(d.nodes[at], name)
    if found { ret v }
    ret ""
}

fn bad_response(a: *mem.Arena, message: str) -> Response {
    ret Response {
        valid: false, message: message, doc: zero, id: "", in_response_to: "", destination: "", issue_instant: "", issuer: "",
        status_present: false, status_has_value: false, status_code: "", status_message: "", assertion: empty_assertion(),
    }
}

fn starts_with_markup(s: str) -> bool {
    var i = 0usize
    while i < s.len && (s[i] == 32u8 || s[i] == 9u8 || s[i] == 10u8 || s[i] == 13u8 || s[i] == 11u8 || s[i] == 12u8) { i += 1usize }
    ret i < s.len && s[i] == 60u8
}

// A response message (the XML itself or its base64) read into fields, with no validation.
fn parse_saml_response(a: *mem.Arena, encoded: str) -> Response {
    var source = encoded
    if !starts_with_markup(encoded) { source = from_base64(a, encoded) }
    let d = xml.parse_xml(a, source)
    if !d.valid { ret bad_response(a, d.message) }
    let root = d.root
    if !str.eq(d.nodes[root].local, "Response") { ret bad_response(a, join(a, "not-a-Response: ", d.nodes[root].local)) }
    let (status, has_status) = xml.find_element(a, d, root, ns_protocol(), "StatusCode")
    var status_value = ""
    var status_has_value = false
    if has_status {
        let (v, found) = xml.attribute_of(d.nodes[status], "Value")
        status_value = v
        status_has_value = found
    }
    let (assertion, has_assertion) = xml.find_element(a, d, root, ns_assertion(), "Assertion")
    var asn = empty_assertion()
    if has_assertion {
        asn.present = true
        asn.id = attr_text(d, assertion, "ID")
        let (issuer, has_issuer) = xml.find_element(a, d, assertion, ns_assertion(), "Issuer")
        if has_issuer { asn.issuer = trimmed(d.nodes[issuer].text) }
        let (subject, has_subject) = xml.find_element(a, d, assertion, ns_assertion(), "Subject")
        if has_subject {
            let (name_id, has_nid) = xml.find_element(a, d, subject, ns_assertion(), "NameID")
            if has_nid {
                asn.has_name_id = true
                asn.name_id = trimmed(d.nodes[name_id].text)
                asn.name_id_format = attr_text(d, name_id, "Format")
            }
            let (conf, has_conf) = xml.find_element(a, d, subject, ns_assertion(), "SubjectConfirmationData")
            if has_conf {
                asn.recipient = attr_text(d, conf, "Recipient")
                asn.confirmation_not_on_or_after = attr_text(d, conf, "NotOnOrAfter")
                asn.confirmation_in_response_to = attr_text(d, conf, "InResponseTo")
            }
        }
        let (conditions, has_conditions) = xml.find_element(a, d, assertion, ns_assertion(), "Conditions")
        if has_conditions {
            asn.not_before = attr_text(d, conditions, "NotBefore")
            asn.not_on_or_after = attr_text(d, conditions, "NotOnOrAfter")
            let auds = xml.find_elements(a, d, conditions, ns_assertion(), "Audience")
            let (out, e) = mem.alloc[str](a, auds.len + 1usize)
            var i = 0usize
            while i < auds.len {
                out[i] = trimmed(d.nodes[auds[i]].text)
                i += 1usize
            }
            asn.audiences = out[0usize..auds.len]
        }
        let (authn, has_authn) = xml.find_element(a, d, assertion, ns_assertion(), "AuthnStatement")
        if has_authn {
            asn.session_index = attr_text(d, authn, "SessionIndex")
            asn.authn_instant = attr_text(d, authn, "AuthnInstant")
        }
        let attrs = xml.find_elements(a, d, assertion, ns_assertion(), "Attribute")
        let (names, ne) = mem.alloc[str](a, attrs.len + 1usize)
        let (values, ve) = mem.alloc[[]const str](a, attrs.len + 1usize)
        var count = 0usize
        var i = 0usize
        while i < attrs.len {
            var name = attr_text(d, attrs[i], "Name")
            if name.len == 0usize { name = attr_text(d, attrs[i], "FriendlyName") }
            i += 1usize
            if name.len == 0usize { continue }
            let vals = xml.find_elements(a, d, attrs[i - 1usize], ns_assertion(), "AttributeValue")
            let (list, le) = mem.alloc[str](a, vals.len + 1usize)
            var k = 0usize
            while k < vals.len {
                list[k] = trimmed(d.nodes[vals[k]].text)
                k += 1usize
            }
            var at = count
            var q = 0usize
            while q < count {
                if str.eq(names[q], name) { at = q }
                q += 1usize
            }
            names[at] = name
            values[at] = list[0usize..vals.len]
            if at == count { count += 1usize }
        }
        asn.attr_names = names[0usize..count]
        asn.attr_values = values[0usize..count]
    }
    var issuer = ""
    let (top_issuer, has_top_issuer) = xml.find_element(a, d, root, ns_assertion(), "Issuer")
    if has_top_issuer { issuer = trimmed(d.nodes[top_issuer].text) }
    var message = ""
    let (sm, has_sm) = xml.find_element(a, d, root, ns_protocol(), "StatusMessage")
    if has_sm { message = trimmed(d.nodes[sm].text) }
    ret Response {
        valid: true, message: "", doc: d, id: attr_text(d, root, "ID"), in_response_to: attr_text(d, root, "InResponseTo"),
        destination: attr_text(d, root, "Destination"), issue_instant: attr_text(d, root, "IssueInstant"), issuer: issuer,
        status_present: has_status, status_has_value: status_has_value, status_code: status_value, status_message: message, assertion: asn,
    }
}

fn days_from_civil(y_in: i64, m: i64, d: i64) -> i64 {
    var y = y_in
    if m <= 2i64 { y -= 1i64 }
    var era = y / 400i64
    if y < 0i64 { era = (y - 399i64) / 400i64 }
    let yoe = y - era * 400i64
    var mp = m + 9i64
    if m > 2i64 { mp = m - 3i64 }
    let doy = (153i64 * mp + 2i64) / 5i64 + d - 1i64
    let doe = yoe * 365i64 + yoe / 4i64 - yoe / 100i64 + doy
    ret era * 146097i64 + doe - 719468i64
}

fn digits(s: str, at: usize, n: usize) -> (i64, bool) {
    if at + n > s.len { ret (0i64, false) }
    var v = 0i64
    var i = 0usize
    while i < n {
        let c = s[at + i]
        if c < 48u8 || c > 57u8 { ret (0i64, false) }
        v = v * 10i64 + i64(c - 48u8)
        i += 1usize
    }
    ret (v, true)
}

// An ISO 8601 instant in milliseconds since the epoch: `YYYY-MM-DD`, optionally `THH:MM[:SS[.fff]]` and `Z` or `+HH:MM`.
fn parse_instant(s: str) -> (f64, bool) {
    let (y, ok_y) = digits(s, 0usize, 4usize)
    if !ok_y || s.len < 10usize || s[4] != 45u8 || s[7] != 45u8 { ret (0.0f64, false) }
    let (mo, ok_m) = digits(s, 5usize, 2usize)
    let (dd, ok_d) = digits(s, 8usize, 2usize)
    if !ok_m || !ok_d || mo < 1i64 || mo > 12i64 || dd < 1i64 || dd > 31i64 { ret (0.0f64, false) }
    var ms = 0i64
    var hour = 0i64
    var minute = 0i64
    var second = 0i64
    var at = 10usize
    var offset_minutes = 0i64
    if at < s.len {
        if s[at] != 84u8 && s[at] != 32u8 { ret (0.0f64, false) }
        let (hh, ok_h) = digits(s, at + 1usize, 2usize)
        if !ok_h || at + 3usize >= s.len || s[at + 3usize] != 58u8 { ret (0.0f64, false) }
        let (mi, ok_mi) = digits(s, at + 4usize, 2usize)
        if !ok_mi || hh > 24i64 || mi > 59i64 { ret (0.0f64, false) }
        hour = hh
        minute = mi
        at += 6usize
        if at < s.len && s[at] == 58u8 {
            let (ss, ok_s) = digits(s, at + 1usize, 2usize)
            if !ok_s || ss > 59i64 { ret (0.0f64, false) }
            second = ss
            at += 3usize
            if at < s.len && s[at] == 46u8 {
                var frac = 0i64
                var places = 0usize
                at += 1usize
                while at < s.len && s[at] >= 48u8 && s[at] <= 57u8 {
                    if places < 3usize {
                        frac = frac * 10i64 + i64(s[at] - 48u8)
                        places += 1usize
                    }
                    at += 1usize
                }
                if places == 0usize { ret (0.0f64, false) }
                while places < 3usize {
                    frac *= 10i64
                    places += 1usize
                }
                ms = frac
            }
        }
        if at < s.len {
            if s[at] == 90u8 {
                at += 1usize
            } else if s[at] == 43u8 || s[at] == 45u8 {
                let (oh, ok_oh) = digits(s, at + 1usize, 2usize)
                if !ok_oh || at + 3usize >= s.len || s[at + 3usize] != 58u8 { ret (0.0f64, false) }
                let (om, ok_om) = digits(s, at + 4usize, 2usize)
                if !ok_om { ret (0.0f64, false) }
                offset_minutes = oh * 60i64 + om
                if s[at] == 45u8 { offset_minutes = 0i64 - offset_minutes }
                at += 6usize
            } else {
                ret (0.0f64, false)
            }
        }
        if at != s.len { ret (0.0f64, false) }
    }
    let days = days_from_civil(y, mo, dd)
    let total = ((days * 24i64 + hour) * 60i64 + minute - offset_minutes) * 60i64 + second
    ret (f64(total) * 1000.0f64 + f64(ms), true)
}

fn none_validation(msg: str) -> Validation {
    ret Validation { valid: false, message: msg, detail: "", has_detail: false, assertion_id: "", signed_element: "", assertion: empty_assertion(), expires_at: 0.0f64, has_expiry: false }
}

fn contains_text(xs: []const str, v: str) -> bool {
    var i = 0usize
    while i < xs.len {
        if str.eq(xs[i], v) { ret true }
        i += 1usize
    }
    ret false
}

fn join_list(a: *mem.Arena, xs: []const str) -> str {
    var out = ""
    var i = 0usize
    while i < xs.len {
        if i > 0usize { out = join(a, out, ", ") }
        out = join(a, out, xs[i])
        i += 1usize
    }
    ret out
}

// A parsed response against the SP's configuration, in the reference's order of checks.
fn validate_saml_response(a: *mem.Arena, parsed: Response, c: Config) -> Validation {
    if !parsed.valid { ret none_validation(parsed.message) }
    var skew = 60000.0f64
    if c.has_skew { skew = c.skew_ms }
    let now = c.now
    if !c.key.has { ret none_validation("no-IdP-key-configured") }
    let signed = extract_signed_assertion(a, parsed.doc, c.key)
    if !signed.valid { ret none_validation(signed.message) }
    var status = "none"
    if parsed.status_present && parsed.status_has_value && parsed.status_code.len > 0usize { status = parsed.status_code }
    if !(parsed.status_present && parsed.status_has_value && str.eq(parsed.status_code, status_success())) {
        var v = none_validation(join(a, "IdP-status: ", status))
        v.detail = parsed.status_message
        v.has_detail = parsed.status_message.len > 0usize
        ret v
    }
    let asn = parsed.assertion
    if !asn.present { ret none_validation("assertion-missing") }
    var issuer = asn.issuer
    if issuer.len == 0usize { issuer = parsed.issuer }
    if c.issuer.len == 0usize || !str.eq(issuer, c.issuer) {
        var shown = issuer
        if shown.len == 0usize { shown = "null" }
        ret none_validation(join(a, "issuer-mismatch: ", shown))
    }
    let (not_before, has_nb) = parse_instant(asn.not_before)
    let (not_on_or_after, has_na) = parse_instant(asn.not_on_or_after)
    if has_nb && now + skew < not_before { ret none_validation("assertion-not-yet-valid") }
    if has_na && now - skew >= not_on_or_after { ret none_validation("assertion-expired") }
    if asn.audiences.len > 0usize && c.audience.len > 0usize && !contains_text(asn.audiences, c.audience) {
        ret none_validation(join(a, "audience-mismatch: ", join_list(a, asn.audiences)))
    }
    if asn.audiences.len == 0usize { ret none_validation("no-AudienceRestriction") }
    let (conf_expiry, has_conf) = parse_instant(asn.confirmation_not_on_or_after)
    if has_conf && now - skew >= conf_expiry { ret none_validation("subject-confirmation-expired") }
    if asn.recipient.len > 0usize && c.acs_url.len > 0usize && !str.eq(asn.recipient, c.acs_url) {
        ret none_validation(join(a, "recipient-mismatch: ", asn.recipient))
    }
    if c.expected_in_response_to.len > 0usize {
        var echoed = asn.confirmation_in_response_to
        if echoed.len == 0usize { echoed = parsed.in_response_to }
        if !str.eq(echoed, c.expected_in_response_to) {
            var shown = echoed
            if shown.len == 0usize { shown = "null" }
            ret none_validation(join(a, "InResponseTo-mismatch: ", shown))
        }
    }
    if parsed.destination.len > 0usize && c.acs_url.len > 0usize && !str.eq(parsed.destination, c.acs_url) {
        ret none_validation(join(a, "destination-mismatch: ", parsed.destination))
    }
    if asn.id.len > 0usize && contains_text(c.seen, asn.id) { ret none_validation("assertion-replayed") }
    ret Validation { valid: true, message: "", detail: "", has_detail: false, assertion_id: asn.id, signed_element: signed.signed_element, assertion: asn, expires_at: not_on_or_after, has_expiry: has_na }
}

// A replay cache whose entries expire with their assertions; `now` is the caller's clock.
fn new_replay_cache(a: *mem.Arena, capacity: usize) -> ReplayCache {
    let (ids, e1) = mem.alloc[str](a, capacity + 1usize)
    let (exp, e2) = mem.alloc[f64](a, capacity + 1usize)
    ret ReplayCache { ids: ids, expiries: exp, count: 0usize }
}

fn replay_prune(c: *ReplayCache, now: f64) {
    var w = 0usize
    var i = 0usize
    while i < c.count {
        if c.expiries[i] > now {
            c.ids[w] = c.ids[i]
            c.expiries[w] = c.expiries[i]
            w += 1usize
        }
        i += 1usize
    }
    c.count = w
}

fn replay_has(c: *ReplayCache, id: str, now: f64) -> bool {
    replay_prune(c, now)
    var i = 0usize
    while i < c.count {
        if str.eq(c.ids[i], id) { ret true }
        i += 1usize
    }
    ret false
}

fn replay_remember(c: *ReplayCache, id: str, expires_at: f64, has_expiry: bool, now: f64) {
    var expiry = now + 600000.0f64
    if has_expiry && expires_at != 0.0f64 { expiry = expires_at }
    var i = 0usize
    while i < c.count {
        if str.eq(c.ids[i], id) {
            c.expiries[i] = expiry
            ret
        }
        i += 1usize
    }
    if c.count < c.ids.len {
        c.ids[c.count] = id
        c.expiries[c.count] = expiry
        c.count += 1usize
    }
}

fn replay_size(c: *ReplayCache, now: f64) -> usize {
    replay_prune(c, now)
    ret c.count
}

type Length = struct { length: usize, offset: usize, good: bool }

fn read_length(der: []const u8, index: usize) -> Length {
    if index >= der.len { ret Length { length: 0usize, offset: 0usize, good: false } }
    let first = usize(der[index])
    if first < 128usize { ret Length { length: first, offset: index + 1usize, good: true } }
    let count = first & 127usize
    if count == 0usize || count > 4usize { ret Length { length: 0usize, offset: 0usize, good: false } }
    var length = 0usize
    var i = 0usize
    while i < count {
        var b = 0usize
        if index + 1usize + i < der.len { b = usize(der[index + 1usize + i]) }
        length = (length << 8usize) | b
        i += 1usize
    }
    ret Length { length: length, offset: index + 1usize + count, good: true }
}

type RsaKey = struct { found: bool, modulus: []const u8, exponent: []const u8 }

// The RSA modulus and exponent out of a DER certificate: the BIT STRING that wraps a SEQUENCE of two INTEGERs.
fn extract_rsa_public_key(der: []const u8) -> RsaKey {
    let none: []const u8 = zero
    var i = 0usize
    while i + 1usize < der.len {
        if der[i] != 3u8 {
            i += 1usize
            continue
        }
        let header = read_length(der, i + 1usize)
        i += 1usize
        if !header.good { continue }
        let content_start = header.offset + 1usize
        if content_start >= der.len || der[content_start] != 48u8 { continue }
        let sequence = read_length(der, content_start + 1usize)
        if !sequence.good { continue }
        var cursor = sequence.offset
        if cursor >= der.len || der[cursor] != 2u8 { continue }
        let modulus_length = read_length(der, cursor + 1usize)
        if !modulus_length.good { continue }
        var m_from = modulus_length.offset
        var m_to = modulus_length.offset + modulus_length.length
        if m_to > der.len { m_to = der.len }
        if m_from > m_to { m_from = m_to }
        while m_from < m_to && der[m_from] == 0u8 { m_from += 1usize }
        cursor = modulus_length.offset + modulus_length.length
        if cursor >= der.len || der[cursor] != 2u8 { continue }
        let exponent_length = read_length(der, cursor + 1usize)
        if !exponent_length.good { continue }
        var e_from = exponent_length.offset
        var e_to = exponent_length.offset + exponent_length.length
        if e_to > der.len { e_to = der.len }
        if e_from > e_to { e_from = e_to }
        if m_to - m_from < 64usize { continue }
        ret RsaKey { found: true, modulus: der[m_from..m_to], exponent: der[e_from..e_to] }
    }
    ret RsaKey { found: false, modulus: none, exponent: none }
}

// A PEM or bare-base64 certificate's RSA key as base64url modulus and exponent.
fn certificate_to_jwk(a: *mem.Arena, certificate: str) -> (Key, bool) {
    var body = ""
    var i = 0usize
    var start = 0usize
    // remove `-----BEGIN ...-----` and `-----END ...-----` lines
    while i < certificate.len {
        if starts_dashes(certificate, i) {
            body = join(a, body, certificate[start..i])
            var j = i + 5usize
            while j < certificate.len && certificate[j] != 45u8 { j += 1usize }
            if j + 5usize <= certificate.len && starts_dashes(certificate, j) {
                i = j + 5usize
            } else {
                i = j
            }
            start = i
            continue
        }
        i += 1usize
    }
    body = join(a, body, certificate[start..])
    let der = from_base64(a, strip_ws(a, body))
    let key = extract_rsa_public_key(der)
    if !key.found { ret (Key { has: false, n: "", e: "" }, false) }
    ret (Key { has: true, n: jose.base64url_encode(a, key.modulus), e: jose.base64url_encode(a, key.exponent) }, true)
}

fn starts_dashes(s: str, at: usize) -> bool {
    if at + 5usize > s.len { ret false }
    var i = 0usize
    while i < 5usize {
        if s[at + i] != 45u8 { ret false }
        i += 1usize
    }
    ret true
}

// The SP metadata an IdP is configured from; empty `sloUrl` has no logout service.
fn build_sp_metadata(a: *mem.Arena, entity_id: str, acs_url: str, slo_url: str, name_id_format: str, want_signed: bool) -> (str, []const str) {
    let names = [2]str{ "entityId", "acsUrl" }
    let present = [2]bool{ entity_id.len > 0usize, acs_url.len > 0usize }
    let missing = missing_names(a, names[0usize..2usize], present[0usize..2usize])
    if missing.len > 0usize { ret ("", missing) }
    var logout = ""
    if slo_url.len > 0usize {
        logout = join(a, join(a, "<md:SingleLogoutService Binding=\"", binding_redirect()), join(a, "\" Location=\"", join(a, xml_escape(a, slo_url), "\"/>")))
    }
    var signed = "false"
    if want_signed { signed = "true" }
    var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    out = join(a, out, join(a, "<md:EntityDescriptor xmlns:md=\"", join(a, ns_metadata(), join(a, "\" entityID=\"", join(a, xml_escape(a, entity_id), "\">")))))
    out = join(a, out, join(a, "<md:SPSSODescriptor AuthnRequestsSigned=\"false\" WantAssertionsSigned=\"", join(a, signed, "\"")))
    out = join(a, out, " protocolSupportEnumeration=\"urn:oasis:names:tc:SAML:2.0:protocol\">")
    out = join(a, out, logout)
    out = join(a, out, join(a, "<md:NameIDFormat>", join(a, xml_escape(a, name_id_format), "</md:NameIDFormat>")))
    out = join(a, out, join(a, "<md:AssertionConsumerService Binding=\"", join(a, binding_post(), join(a, "\" Location=\"", join(a, xml_escape(a, acs_url), "\" index=\"0\" isDefault=\"true\"/>")))))
    out = join(a, out, "</md:SPSSODescriptor></md:EntityDescriptor>")
    ret (out, zero)
}

type IdpMetadata = struct { valid: bool, message: str, entity_id: str, sso_url: str, post_url: str, certificates: []const str }

// An IdP metadata document read into the entity id, the sign-on URLs and the certificates.
fn parse_idp_metadata(a: *mem.Arena, source: str) -> IdpMetadata {
    let none: []const str = zero
    let d = xml.parse_xml(a, source)
    if !d.valid { ret IdpMetadata { valid: false, message: d.message, entity_id: "", sso_url: "", post_url: "", certificates: none } }
    let (descriptor, has) = xml.find_element(a, d, d.root, ns_metadata(), "IDPSSODescriptor")
    if !has { ret IdpMetadata { valid: false, message: "no-IDPSSODescriptor", entity_id: "", sso_url: "", post_url: "", certificates: none } }
    let services = xml.find_elements(a, d, descriptor, ns_metadata(), "SingleSignOnService")
    var sso = ""
    var post = ""
    var first = ""
    var have_redirect = false
    var have_post = false
    var i = 0usize
    while i < services.len {
        let binding = attr_text(d, services[i], "Binding")
        let location = attr_text(d, services[i], "Location")
        if i == 0usize { first = location }
        if !have_redirect && str.eq(binding, binding_redirect()) {
            sso = location
            have_redirect = true
        }
        if !have_post && str.eq(binding, binding_post()) {
            post = location
            have_post = true
        }
        i += 1usize
    }
    if !have_redirect { sso = first }
    let certs = xml.find_elements(a, d, descriptor, ns_signature(), "X509Certificate")
    let (out, e) = mem.alloc[str](a, certs.len + 1usize)
    i = 0usize
    while i < certs.len {
        out[i] = strip_ws(a, d.nodes[certs[i]].text)
        i += 1usize
    }
    ret IdpMetadata { valid: true, message: "", entity_id: attr_text(d, d.root, "entityID"), sso_url: sso, post_url: post, certificates: out[0usize..certs.len] }
}
