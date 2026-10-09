// e.fmt.soap against Python's xml.etree (L080, D2270; scripts/soap_reference.py writes this file): canned
// SOAP 1.1 and 1.2 documents compared with an ElementTree-based reference, the envelope and fault builder
// compared with the reference serialisation and parsed back, canned WSDL 1.1 documents, and the XSD built-in
// type mapping. A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.fmt.soap
use e.fmt.xml

fn same(a: str, b: str) -> bool {
    if a.len != b.len { ret false }
    var i = 0usize
    while i < a.len {
        if a[i] != b[i] { ret false }
        i += 1usize
    }
    ret true
}

fn slice_text(w: *io.SliceWriter) -> str { ret w.data[..w.off] }

fn report(table: str, index: usize) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var n = index
    if n == 0usize {
        digits[0usize] = 0u8
        count = 1usize
    }
    while n > 0usize {
        digits[count] = u8(n % 10usize)
        n /= 10usize
        count += 1usize
    }
    let glyphs = "0123456789"
    try io.print("soap mismatch in ")
    try io.print(table)
    try io.print(" at ")
    var i = count
    while i > 0usize {
        i -= 1usize
        try io.print(glyphs[usize(digits[i])..usize(digits[i]) + 1usize])
    }
    try io.print("\n")
    os.exit(1)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let ns11 = soap.namespace(.Soap11)
    let ns12 = soap.namespace(.Soap12)
    if !same(ns11, "http://schemas.xmlsoap.org/soap/envelope/") || !same(ns12, "http://www.w3.org/2003/05/soap-envelope") { try report("namespaces", 0usize) }
    let doc_0 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Header><t:Trans xmlns:t=\"urn:t\" s:mustUnderstand=\"1\">5</t:Trans><t:Other xmlns:t=\"urn:t\" s:mustUnderstand=\"0\"/></s:Header><s:Body><m:GetPrice xmlns:m=\"urn:prices\"><m:Item>Apples</m:Item></m:GetPrice></s:Body></s:Envelope>"
    let (env_0, err_0) = soap.parse(a, doc_0)
    if err_0 != ok || env_0.version != .Soap11 { try report("doc-version-req11", 0usize) }
    if (env_0.header != 4294967295u32) != true { try report("doc-header-req11", 0usize) }
    let payload_0 = soap.payload(&env_0)
    let (pu_0, pl_0, pe_0) = soap.expand(&env_0.document, payload_0)
    if payload_0 == 4294967295u32 || pe_0 != ok || !same(pu_0, "urn:prices") || !same(pl_0, "GetPrice") { try report("doc-payload-req11", 0usize) }
    if soap.is_fault(&env_0) != false { try report("doc-isfault-req11", 0usize) }
    var must_ids_0: [8]u32 = zero
    let (must_0, must_error_0) = soap.must_understand_blocks(a, &env_0, must_ids_0[..])
    if must_error_0 != ok || must_0 != 1usize { try report("doc-must-req11", 0usize) }
    let (mu_0_0, ml_0_0, me_0_0) = soap.expand(&env_0.document, must_ids_0[0usize])
    if me_0_0 != ok || !same(ml_0_0, "Trans") { try report("doc-must-name-req11", 0usize) }
    let (_, not_fault_error_0) = soap.parse_fault(a, &env_0)
    if not_fault_error_0 != soap.Invalid { try report("not-a-fault-req11", 0usize) }
    let doc_1 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><m:GetPriceResponse xmlns:m=\"urn:prices\"><m:Price>1.5</m:Price></m:GetPriceResponse></s:Body></s:Envelope>"
    let (env_1, err_1) = soap.parse(a, doc_1)
    if err_1 != ok || env_1.version != .Soap11 { try report("doc-version-resp11", 1usize) }
    if (env_1.header != 4294967295u32) != false { try report("doc-header-resp11", 1usize) }
    let payload_1 = soap.payload(&env_1)
    let (pu_1, pl_1, pe_1) = soap.expand(&env_1.document, payload_1)
    if payload_1 == 4294967295u32 || pe_1 != ok || !same(pu_1, "urn:prices") || !same(pl_1, "GetPriceResponse") { try report("doc-payload-resp11", 1usize) }
    if soap.is_fault(&env_1) != false { try report("doc-isfault-resp11", 1usize) }
    var must_ids_1: [8]u32 = zero
    let (must_1, must_error_1) = soap.must_understand_blocks(a, &env_1, must_ids_1[..])
    if must_error_1 != ok || must_1 != 0usize { try report("doc-must-resp11", 1usize) }
    let (_, not_fault_error_1) = soap.parse_fault(a, &env_1)
    if not_fault_error_1 != soap.Invalid { try report("not-a-fault-resp11", 1usize) }
    let doc_2 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>Bad  input &amp; more</faultstring><faultactor>http://x.example/actor</faultactor><detail><e:Err xmlns:e=\"urn:e\">42</e:Err></detail></s:Fault></s:Body></s:Envelope>"
    let (env_2, err_2) = soap.parse(a, doc_2)
    if err_2 != ok || env_2.version != .Soap11 { try report("doc-version-fault11", 2usize) }
    if (env_2.header != 4294967295u32) != false { try report("doc-header-fault11", 2usize) }
    let payload_2 = soap.payload(&env_2)
    let (pu_2, pl_2, pe_2) = soap.expand(&env_2.document, payload_2)
    if payload_2 == 4294967295u32 || pe_2 != ok || !same(pu_2, "http://schemas.xmlsoap.org/soap/envelope/") || !same(pl_2, "Fault") { try report("doc-payload-fault11", 2usize) }
    if soap.is_fault(&env_2) != true { try report("doc-isfault-fault11", 2usize) }
    var must_ids_2: [8]u32 = zero
    let (must_2, must_error_2) = soap.must_understand_blocks(a, &env_2, must_ids_2[..])
    if must_error_2 != ok || must_2 != 0usize { try report("doc-must-fault11", 2usize) }
    let (fault_2, fault_error_2) = soap.parse_fault(a, &env_2)
    if fault_error_2 != ok { try report("fault-error-fault11", 2usize) }
    if fault_2.code != .Sender { try report("fault-code-fault11", 2usize) }
    if !same(fault_2.code_text, "s:Client") { try report("fault-code-text-fault11", 2usize) }
    if !same(fault_2.reason, "Bad  input & more") { try report("fault-reason-fault11", 2usize) }
    if !same(fault_2.actor, "http://x.example/actor") { try report("fault-actor-fault11", 2usize) }
    if !same(fault_2.subcode, "") { try report("fault-subcode-fault11", 2usize) }
    if !same(fault_2.language, "") { try report("fault-lang-fault11", 2usize) }
    if (fault_2.detail != 4294967295u32) != true { try report("fault-detail-fault11", 2usize) }
    let typed_2 = soap.fault_error(fault_2.code)
    if typed_2 != soap.Sender { try report("fault-typed-fault11", 2usize) }
    let doc_3 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:Server</faultcode><faultstring>down</faultstring></s:Fault></s:Body></s:Envelope>"
    let (env_3, err_3) = soap.parse(a, doc_3)
    if err_3 != ok || env_3.version != .Soap11 { try report("doc-version-fault11-server", 3usize) }
    if (env_3.header != 4294967295u32) != false { try report("doc-header-fault11-server", 3usize) }
    let payload_3 = soap.payload(&env_3)
    let (pu_3, pl_3, pe_3) = soap.expand(&env_3.document, payload_3)
    if payload_3 == 4294967295u32 || pe_3 != ok || !same(pu_3, "http://schemas.xmlsoap.org/soap/envelope/") || !same(pl_3, "Fault") { try report("doc-payload-fault11-server", 3usize) }
    if soap.is_fault(&env_3) != true { try report("doc-isfault-fault11-server", 3usize) }
    var must_ids_3: [8]u32 = zero
    let (must_3, must_error_3) = soap.must_understand_blocks(a, &env_3, must_ids_3[..])
    if must_error_3 != ok || must_3 != 0usize { try report("doc-must-fault11-server", 3usize) }
    let (fault_3, fault_error_3) = soap.parse_fault(a, &env_3)
    if fault_error_3 != ok { try report("fault-error-fault11-server", 3usize) }
    if fault_3.code != .Receiver { try report("fault-code-fault11-server", 3usize) }
    if !same(fault_3.code_text, "s:Server") { try report("fault-code-text-fault11-server", 3usize) }
    if !same(fault_3.reason, "down") { try report("fault-reason-fault11-server", 3usize) }
    if !same(fault_3.actor, "") { try report("fault-actor-fault11-server", 3usize) }
    if !same(fault_3.subcode, "") { try report("fault-subcode-fault11-server", 3usize) }
    if !same(fault_3.language, "") { try report("fault-lang-fault11-server", 3usize) }
    if (fault_3.detail != 4294967295u32) != false { try report("fault-detail-fault11-server", 3usize) }
    let typed_3 = soap.fault_error(fault_3.code)
    if typed_3 != soap.Receiver { try report("fault-typed-fault11-server", 3usize) }
    let doc_4 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:VersionMismatch</faultcode><faultstring>v</faultstring></s:Fault></s:Body></s:Envelope>"
    let (env_4, err_4) = soap.parse(a, doc_4)
    if err_4 != ok || env_4.version != .Soap11 { try report("doc-version-fault11-vm", 4usize) }
    if (env_4.header != 4294967295u32) != false { try report("doc-header-fault11-vm", 4usize) }
    let payload_4 = soap.payload(&env_4)
    let (pu_4, pl_4, pe_4) = soap.expand(&env_4.document, payload_4)
    if payload_4 == 4294967295u32 || pe_4 != ok || !same(pu_4, "http://schemas.xmlsoap.org/soap/envelope/") || !same(pl_4, "Fault") { try report("doc-payload-fault11-vm", 4usize) }
    if soap.is_fault(&env_4) != true { try report("doc-isfault-fault11-vm", 4usize) }
    var must_ids_4: [8]u32 = zero
    let (must_4, must_error_4) = soap.must_understand_blocks(a, &env_4, must_ids_4[..])
    if must_error_4 != ok || must_4 != 0usize { try report("doc-must-fault11-vm", 4usize) }
    let (fault_4, fault_error_4) = soap.parse_fault(a, &env_4)
    if fault_error_4 != ok { try report("fault-error-fault11-vm", 4usize) }
    if fault_4.code != .VersionMismatch { try report("fault-code-fault11-vm", 4usize) }
    if !same(fault_4.code_text, "s:VersionMismatch") { try report("fault-code-text-fault11-vm", 4usize) }
    if !same(fault_4.reason, "v") { try report("fault-reason-fault11-vm", 4usize) }
    if !same(fault_4.actor, "") { try report("fault-actor-fault11-vm", 4usize) }
    if !same(fault_4.subcode, "") { try report("fault-subcode-fault11-vm", 4usize) }
    if !same(fault_4.language, "") { try report("fault-lang-fault11-vm", 4usize) }
    if (fault_4.detail != 4294967295u32) != false { try report("fault-detail-fault11-vm", 4usize) }
    let typed_4 = soap.fault_error(fault_4.code)
    if typed_4 != soap.VersionMismatch { try report("fault-typed-fault11-vm", 4usize) }
    let doc_5 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode> s:MustUnderstand </faultcode><faultstring>m</faultstring></s:Fault></s:Body></s:Envelope>"
    let (env_5, err_5) = soap.parse(a, doc_5)
    if err_5 != ok || env_5.version != .Soap11 { try report("doc-version-fault11-mu", 5usize) }
    if (env_5.header != 4294967295u32) != false { try report("doc-header-fault11-mu", 5usize) }
    let payload_5 = soap.payload(&env_5)
    let (pu_5, pl_5, pe_5) = soap.expand(&env_5.document, payload_5)
    if payload_5 == 4294967295u32 || pe_5 != ok || !same(pu_5, "http://schemas.xmlsoap.org/soap/envelope/") || !same(pl_5, "Fault") { try report("doc-payload-fault11-mu", 5usize) }
    if soap.is_fault(&env_5) != true { try report("doc-isfault-fault11-mu", 5usize) }
    var must_ids_5: [8]u32 = zero
    let (must_5, must_error_5) = soap.must_understand_blocks(a, &env_5, must_ids_5[..])
    if must_error_5 != ok || must_5 != 0usize { try report("doc-must-fault11-mu", 5usize) }
    let (fault_5, fault_error_5) = soap.parse_fault(a, &env_5)
    if fault_error_5 != ok { try report("fault-error-fault11-mu", 5usize) }
    if fault_5.code != .MustUnderstand { try report("fault-code-fault11-mu", 5usize) }
    if !same(fault_5.code_text, "s:MustUnderstand") { try report("fault-code-text-fault11-mu", 5usize) }
    if !same(fault_5.reason, "m") { try report("fault-reason-fault11-mu", 5usize) }
    if !same(fault_5.actor, "") { try report("fault-actor-fault11-mu", 5usize) }
    if !same(fault_5.subcode, "") { try report("fault-subcode-fault11-mu", 5usize) }
    if !same(fault_5.language, "") { try report("fault-lang-fault11-mu", 5usize) }
    if (fault_5.detail != 4294967295u32) != false { try report("fault-detail-fault11-mu", 5usize) }
    let typed_5 = soap.fault_error(fault_5.code)
    if typed_5 != soap.MustUnderstand { try report("fault-typed-fault11-mu", 5usize) }
    let doc_6 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:app=\"urn:app\"><s:Body><s:Fault><faultcode>app:Quota</faultcode><faultstring>q</faultstring></s:Fault></s:Body></s:Envelope>"
    let (env_6, err_6) = soap.parse(a, doc_6)
    if err_6 != ok || env_6.version != .Soap11 { try report("doc-version-fault11-custom", 6usize) }
    if (env_6.header != 4294967295u32) != false { try report("doc-header-fault11-custom", 6usize) }
    let payload_6 = soap.payload(&env_6)
    let (pu_6, pl_6, pe_6) = soap.expand(&env_6.document, payload_6)
    if payload_6 == 4294967295u32 || pe_6 != ok || !same(pu_6, "http://schemas.xmlsoap.org/soap/envelope/") || !same(pl_6, "Fault") { try report("doc-payload-fault11-custom", 6usize) }
    if soap.is_fault(&env_6) != true { try report("doc-isfault-fault11-custom", 6usize) }
    var must_ids_6: [8]u32 = zero
    let (must_6, must_error_6) = soap.must_understand_blocks(a, &env_6, must_ids_6[..])
    if must_error_6 != ok || must_6 != 0usize { try report("doc-must-fault11-custom", 6usize) }
    let (fault_6, fault_error_6) = soap.parse_fault(a, &env_6)
    if fault_error_6 != ok { try report("fault-error-fault11-custom", 6usize) }
    if fault_6.code != .Other { try report("fault-code-fault11-custom", 6usize) }
    if !same(fault_6.code_text, "app:Quota") { try report("fault-code-text-fault11-custom", 6usize) }
    if !same(fault_6.reason, "q") { try report("fault-reason-fault11-custom", 6usize) }
    if !same(fault_6.actor, "") { try report("fault-actor-fault11-custom", 6usize) }
    if !same(fault_6.subcode, "") { try report("fault-subcode-fault11-custom", 6usize) }
    if !same(fault_6.language, "") { try report("fault-lang-fault11-custom", 6usize) }
    if (fault_6.detail != 4294967295u32) != false { try report("fault-detail-fault11-custom", 6usize) }
    let typed_6 = soap.fault_error(fault_6.code)
    if typed_6 != soap.OtherFault { try report("fault-typed-fault11-custom", 6usize) }
    let doc_7 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:Client.Auth</faultcode><faultstring>a</faultstring></s:Fault></s:Body></s:Envelope>"
    let (env_7, err_7) = soap.parse(a, doc_7)
    if err_7 != ok || env_7.version != .Soap11 { try report("doc-version-fault11-dotted", 7usize) }
    if (env_7.header != 4294967295u32) != false { try report("doc-header-fault11-dotted", 7usize) }
    let payload_7 = soap.payload(&env_7)
    let (pu_7, pl_7, pe_7) = soap.expand(&env_7.document, payload_7)
    if payload_7 == 4294967295u32 || pe_7 != ok || !same(pu_7, "http://schemas.xmlsoap.org/soap/envelope/") || !same(pl_7, "Fault") { try report("doc-payload-fault11-dotted", 7usize) }
    if soap.is_fault(&env_7) != true { try report("doc-isfault-fault11-dotted", 7usize) }
    var must_ids_7: [8]u32 = zero
    let (must_7, must_error_7) = soap.must_understand_blocks(a, &env_7, must_ids_7[..])
    if must_error_7 != ok || must_7 != 0usize { try report("doc-must-fault11-dotted", 7usize) }
    let (fault_7, fault_error_7) = soap.parse_fault(a, &env_7)
    if fault_error_7 != ok { try report("fault-error-fault11-dotted", 7usize) }
    if fault_7.code != .Other { try report("fault-code-fault11-dotted", 7usize) }
    if !same(fault_7.code_text, "s:Client.Auth") { try report("fault-code-text-fault11-dotted", 7usize) }
    if !same(fault_7.reason, "a") { try report("fault-reason-fault11-dotted", 7usize) }
    if !same(fault_7.actor, "") { try report("fault-actor-fault11-dotted", 7usize) }
    if !same(fault_7.subcode, "") { try report("fault-subcode-fault11-dotted", 7usize) }
    if !same(fault_7.language, "") { try report("fault-lang-fault11-dotted", 7usize) }
    if (fault_7.detail != 4294967295u32) != false { try report("fault-detail-fault11-dotted", 7usize) }
    let typed_7 = soap.fault_error(fault_7.code)
    if typed_7 != soap.OtherFault { try report("fault-typed-fault11-dotted", 7usize) }
    let doc_8 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:Client</faultcode></s:Fault></s:Body></s:Envelope>"
    let (env_8, err_8) = soap.parse(a, doc_8)
    if err_8 != ok || env_8.version != .Soap11 { try report("doc-version-fault11-incomplete", 8usize) }
    if (env_8.header != 4294967295u32) != false { try report("doc-header-fault11-incomplete", 8usize) }
    let payload_8 = soap.payload(&env_8)
    let (pu_8, pl_8, pe_8) = soap.expand(&env_8.document, payload_8)
    if payload_8 == 4294967295u32 || pe_8 != ok || !same(pu_8, "http://schemas.xmlsoap.org/soap/envelope/") || !same(pl_8, "Fault") { try report("doc-payload-fault11-incomplete", 8usize) }
    if soap.is_fault(&env_8) != true { try report("doc-isfault-fault11-incomplete", 8usize) }
    var must_ids_8: [8]u32 = zero
    let (must_8, must_error_8) = soap.must_understand_blocks(a, &env_8, must_ids_8[..])
    if must_error_8 != ok || must_8 != 0usize { try report("doc-must-fault11-incomplete", 8usize) }
    let (fault_8, fault_error_8) = soap.parse_fault(a, &env_8)
    if fault_error_8 != soap.Invalid { try report("fault-invalid-fault11-incomplete", 8usize) }
    let doc_9 = "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\"><env:Header><n:alert xmlns:n=\"urn:n\" env:mustUnderstand=\"true\" env:role=\"http://example.org/r\">x</n:alert></env:Header><env:Body><p:Op xmlns:p=\"urn:p\"/></env:Body></env:Envelope>"
    let (env_9, err_9) = soap.parse(a, doc_9)
    if err_9 != ok || env_9.version != .Soap12 { try report("doc-version-req12", 9usize) }
    if (env_9.header != 4294967295u32) != true { try report("doc-header-req12", 9usize) }
    let payload_9 = soap.payload(&env_9)
    let (pu_9, pl_9, pe_9) = soap.expand(&env_9.document, payload_9)
    if payload_9 == 4294967295u32 || pe_9 != ok || !same(pu_9, "urn:p") || !same(pl_9, "Op") { try report("doc-payload-req12", 9usize) }
    if soap.is_fault(&env_9) != false { try report("doc-isfault-req12", 9usize) }
    var must_ids_9: [8]u32 = zero
    let (must_9, must_error_9) = soap.must_understand_blocks(a, &env_9, must_ids_9[..])
    if must_error_9 != ok || must_9 != 1usize { try report("doc-must-req12", 9usize) }
    let (mu_9_0, ml_9_0, me_9_0) = soap.expand(&env_9.document, must_ids_9[0usize])
    if me_9_0 != ok || !same(ml_9_0, "alert") { try report("doc-must-name-req12", 9usize) }
    let (_, not_fault_error_9) = soap.parse_fault(a, &env_9)
    if not_fault_error_9 != soap.Invalid { try report("not-a-fault-req12", 9usize) }
    let doc_10 = "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\" xmlns:rpc=\"http://www.w3.org/2003/05/soap-rpc\"><env:Body><env:Fault><env:Code><env:Value>env:Sender</env:Value><env:Subcode><env:Value>rpc:BadArguments</env:Value></env:Subcode></env:Code><env:Reason><env:Text xml:lang=\"en\">Processing error</env:Text><env:Text xml:lang=\"cs\">Chyba</env:Text></env:Reason><env:Role>urn:role</env:Role><env:Detail><e:x xmlns:e=\"urn:e\"/></env:Detail></env:Fault></env:Body></env:Envelope>"
    let (env_10, err_10) = soap.parse(a, doc_10)
    if err_10 != ok || env_10.version != .Soap12 { try report("doc-version-fault12", 10usize) }
    if (env_10.header != 4294967295u32) != false { try report("doc-header-fault12", 10usize) }
    let payload_10 = soap.payload(&env_10)
    let (pu_10, pl_10, pe_10) = soap.expand(&env_10.document, payload_10)
    if payload_10 == 4294967295u32 || pe_10 != ok || !same(pu_10, "http://www.w3.org/2003/05/soap-envelope") || !same(pl_10, "Fault") { try report("doc-payload-fault12", 10usize) }
    if soap.is_fault(&env_10) != true { try report("doc-isfault-fault12", 10usize) }
    var must_ids_10: [8]u32 = zero
    let (must_10, must_error_10) = soap.must_understand_blocks(a, &env_10, must_ids_10[..])
    if must_error_10 != ok || must_10 != 0usize { try report("doc-must-fault12", 10usize) }
    let (fault_10, fault_error_10) = soap.parse_fault(a, &env_10)
    if fault_error_10 != ok { try report("fault-error-fault12", 10usize) }
    if fault_10.code != .Sender { try report("fault-code-fault12", 10usize) }
    if !same(fault_10.code_text, "env:Sender") { try report("fault-code-text-fault12", 10usize) }
    if !same(fault_10.reason, "Processing error") { try report("fault-reason-fault12", 10usize) }
    if !same(fault_10.actor, "urn:role") { try report("fault-actor-fault12", 10usize) }
    if !same(fault_10.subcode, "rpc:BadArguments") { try report("fault-subcode-fault12", 10usize) }
    if !same(fault_10.language, "en") { try report("fault-lang-fault12", 10usize) }
    if (fault_10.detail != 4294967295u32) != true { try report("fault-detail-fault12", 10usize) }
    let typed_10 = soap.fault_error(fault_10.code)
    if typed_10 != soap.Sender { try report("fault-typed-fault12", 10usize) }
    let doc_11 = "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\"><env:Body><env:Fault><env:Code><env:Value>env:Receiver</env:Value></env:Code><env:Reason><env:Text>boom</env:Text></env:Reason></env:Fault></env:Body></env:Envelope>"
    let (env_11, err_11) = soap.parse(a, doc_11)
    if err_11 != ok || env_11.version != .Soap12 { try report("doc-version-fault12-receiver", 11usize) }
    if (env_11.header != 4294967295u32) != false { try report("doc-header-fault12-receiver", 11usize) }
    let payload_11 = soap.payload(&env_11)
    let (pu_11, pl_11, pe_11) = soap.expand(&env_11.document, payload_11)
    if payload_11 == 4294967295u32 || pe_11 != ok || !same(pu_11, "http://www.w3.org/2003/05/soap-envelope") || !same(pl_11, "Fault") { try report("doc-payload-fault12-receiver", 11usize) }
    if soap.is_fault(&env_11) != true { try report("doc-isfault-fault12-receiver", 11usize) }
    var must_ids_11: [8]u32 = zero
    let (must_11, must_error_11) = soap.must_understand_blocks(a, &env_11, must_ids_11[..])
    if must_error_11 != ok || must_11 != 0usize { try report("doc-must-fault12-receiver", 11usize) }
    let (fault_11, fault_error_11) = soap.parse_fault(a, &env_11)
    if fault_error_11 != ok { try report("fault-error-fault12-receiver", 11usize) }
    if fault_11.code != .Receiver { try report("fault-code-fault12-receiver", 11usize) }
    if !same(fault_11.code_text, "env:Receiver") { try report("fault-code-text-fault12-receiver", 11usize) }
    if !same(fault_11.reason, "boom") { try report("fault-reason-fault12-receiver", 11usize) }
    if !same(fault_11.actor, "") { try report("fault-actor-fault12-receiver", 11usize) }
    if !same(fault_11.subcode, "") { try report("fault-subcode-fault12-receiver", 11usize) }
    if !same(fault_11.language, "") { try report("fault-lang-fault12-receiver", 11usize) }
    if (fault_11.detail != 4294967295u32) != false { try report("fault-detail-fault12-receiver", 11usize) }
    let typed_11 = soap.fault_error(fault_11.code)
    if typed_11 != soap.Receiver { try report("fault-typed-fault12-receiver", 11usize) }
    let doc_12 = "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\"><env:Body><env:Fault><env:Code><env:Value>env:DataEncodingUnknown</env:Value></env:Code><env:Reason><env:Text xml:lang=\"de\">k</env:Text></env:Reason></env:Fault></env:Body></env:Envelope>"
    let (env_12, err_12) = soap.parse(a, doc_12)
    if err_12 != ok || env_12.version != .Soap12 { try report("doc-version-fault12-dataenc", 12usize) }
    if (env_12.header != 4294967295u32) != false { try report("doc-header-fault12-dataenc", 12usize) }
    let payload_12 = soap.payload(&env_12)
    let (pu_12, pl_12, pe_12) = soap.expand(&env_12.document, payload_12)
    if payload_12 == 4294967295u32 || pe_12 != ok || !same(pu_12, "http://www.w3.org/2003/05/soap-envelope") || !same(pl_12, "Fault") { try report("doc-payload-fault12-dataenc", 12usize) }
    if soap.is_fault(&env_12) != true { try report("doc-isfault-fault12-dataenc", 12usize) }
    var must_ids_12: [8]u32 = zero
    let (must_12, must_error_12) = soap.must_understand_blocks(a, &env_12, must_ids_12[..])
    if must_error_12 != ok || must_12 != 0usize { try report("doc-must-fault12-dataenc", 12usize) }
    let (fault_12, fault_error_12) = soap.parse_fault(a, &env_12)
    if fault_error_12 != ok { try report("fault-error-fault12-dataenc", 12usize) }
    if fault_12.code != .DataEncodingUnknown { try report("fault-code-fault12-dataenc", 12usize) }
    if !same(fault_12.code_text, "env:DataEncodingUnknown") { try report("fault-code-text-fault12-dataenc", 12usize) }
    if !same(fault_12.reason, "k") { try report("fault-reason-fault12-dataenc", 12usize) }
    if !same(fault_12.actor, "") { try report("fault-actor-fault12-dataenc", 12usize) }
    if !same(fault_12.subcode, "") { try report("fault-subcode-fault12-dataenc", 12usize) }
    if !same(fault_12.language, "de") { try report("fault-lang-fault12-dataenc", 12usize) }
    if (fault_12.detail != 4294967295u32) != false { try report("fault-detail-fault12-dataenc", 12usize) }
    let typed_12 = soap.fault_error(fault_12.code)
    if typed_12 != soap.DataEncodingUnknown { try report("fault-typed-fault12-dataenc", 12usize) }
    let doc_13 = "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\"><env:Body><env:Fault><env:Code><env:Value>env:Client</env:Value></env:Code><env:Reason><env:Text>c</env:Text></env:Reason></env:Fault></env:Body></env:Envelope>"
    let (env_13, err_13) = soap.parse(a, doc_13)
    if err_13 != ok || env_13.version != .Soap12 { try report("doc-version-fault12-client-is-other", 13usize) }
    if (env_13.header != 4294967295u32) != false { try report("doc-header-fault12-client-is-other", 13usize) }
    let payload_13 = soap.payload(&env_13)
    let (pu_13, pl_13, pe_13) = soap.expand(&env_13.document, payload_13)
    if payload_13 == 4294967295u32 || pe_13 != ok || !same(pu_13, "http://www.w3.org/2003/05/soap-envelope") || !same(pl_13, "Fault") { try report("doc-payload-fault12-client-is-other", 13usize) }
    if soap.is_fault(&env_13) != true { try report("doc-isfault-fault12-client-is-other", 13usize) }
    var must_ids_13: [8]u32 = zero
    let (must_13, must_error_13) = soap.must_understand_blocks(a, &env_13, must_ids_13[..])
    if must_error_13 != ok || must_13 != 0usize { try report("doc-must-fault12-client-is-other", 13usize) }
    let (fault_13, fault_error_13) = soap.parse_fault(a, &env_13)
    if fault_error_13 != ok { try report("fault-error-fault12-client-is-other", 13usize) }
    if fault_13.code != .Other { try report("fault-code-fault12-client-is-other", 13usize) }
    if !same(fault_13.code_text, "env:Client") { try report("fault-code-text-fault12-client-is-other", 13usize) }
    if !same(fault_13.reason, "c") { try report("fault-reason-fault12-client-is-other", 13usize) }
    if !same(fault_13.actor, "") { try report("fault-actor-fault12-client-is-other", 13usize) }
    if !same(fault_13.subcode, "") { try report("fault-subcode-fault12-client-is-other", 13usize) }
    if !same(fault_13.language, "") { try report("fault-lang-fault12-client-is-other", 13usize) }
    if (fault_13.detail != 4294967295u32) != false { try report("fault-detail-fault12-client-is-other", 13usize) }
    let typed_13 = soap.fault_error(fault_13.code)
    if typed_13 != soap.OtherFault { try report("fault-typed-fault12-client-is-other", 13usize) }
    let doc_14 = "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\"><env:Body><env:Fault><env:Code><env:Value>env:Sender</env:Value></env:Code></env:Fault></env:Body></env:Envelope>"
    let (env_14, err_14) = soap.parse(a, doc_14)
    if err_14 != ok || env_14.version != .Soap12 { try report("doc-version-fault12-incomplete", 14usize) }
    if (env_14.header != 4294967295u32) != false { try report("doc-header-fault12-incomplete", 14usize) }
    let payload_14 = soap.payload(&env_14)
    let (pu_14, pl_14, pe_14) = soap.expand(&env_14.document, payload_14)
    if payload_14 == 4294967295u32 || pe_14 != ok || !same(pu_14, "http://www.w3.org/2003/05/soap-envelope") || !same(pl_14, "Fault") { try report("doc-payload-fault12-incomplete", 14usize) }
    if soap.is_fault(&env_14) != true { try report("doc-isfault-fault12-incomplete", 14usize) }
    var must_ids_14: [8]u32 = zero
    let (must_14, must_error_14) = soap.must_understand_blocks(a, &env_14, must_ids_14[..])
    if must_error_14 != ok || must_14 != 0usize { try report("doc-must-fault12-incomplete", 14usize) }
    let (fault_14, fault_error_14) = soap.parse_fault(a, &env_14)
    if fault_error_14 != soap.Invalid { try report("fault-invalid-fault12-incomplete", 14usize) }
    let doc_15 = "<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\"><SOAP-ENV:Body><x:Y xmlns:x=\"urn:x\"/></SOAP-ENV:Body></SOAP-ENV:Envelope>"
    let (env_15, err_15) = soap.parse(a, doc_15)
    if err_15 != ok || env_15.version != .Soap11 { try report("doc-version-prefix-soapenv", 15usize) }
    if (env_15.header != 4294967295u32) != false { try report("doc-header-prefix-soapenv", 15usize) }
    let payload_15 = soap.payload(&env_15)
    let (pu_15, pl_15, pe_15) = soap.expand(&env_15.document, payload_15)
    if payload_15 == 4294967295u32 || pe_15 != ok || !same(pu_15, "urn:x") || !same(pl_15, "Y") { try report("doc-payload-prefix-soapenv", 15usize) }
    if soap.is_fault(&env_15) != false { try report("doc-isfault-prefix-soapenv", 15usize) }
    var must_ids_15: [8]u32 = zero
    let (must_15, must_error_15) = soap.must_understand_blocks(a, &env_15, must_ids_15[..])
    if must_error_15 != ok || must_15 != 0usize { try report("doc-must-prefix-soapenv", 15usize) }
    let (_, not_fault_error_15) = soap.parse_fault(a, &env_15)
    if not_fault_error_15 != soap.Invalid { try report("not-a-fault-prefix-soapenv", 15usize) }
    let doc_16 = "<Envelope xmlns=\"http://schemas.xmlsoap.org/soap/envelope/\"><Header/><Body><Ping xmlns=\"urn:ping\"/></Body></Envelope>"
    let (env_16, err_16) = soap.parse(a, doc_16)
    if err_16 != ok || env_16.version != .Soap11 { try report("doc-version-default-ns", 16usize) }
    if (env_16.header != 4294967295u32) != true { try report("doc-header-default-ns", 16usize) }
    let payload_16 = soap.payload(&env_16)
    let (pu_16, pl_16, pe_16) = soap.expand(&env_16.document, payload_16)
    if payload_16 == 4294967295u32 || pe_16 != ok || !same(pu_16, "urn:ping") || !same(pl_16, "Ping") { try report("doc-payload-default-ns", 16usize) }
    if soap.is_fault(&env_16) != false { try report("doc-isfault-default-ns", 16usize) }
    var must_ids_16: [8]u32 = zero
    let (must_16, must_error_16) = soap.must_understand_blocks(a, &env_16, must_ids_16[..])
    if must_error_16 != ok || must_16 != 0usize { try report("doc-must-default-ns", 16usize) }
    let (_, not_fault_error_16) = soap.parse_fault(a, &env_16)
    if not_fault_error_16 != soap.Invalid { try report("not-a-fault-default-ns", 16usize) }
    let doc_17 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body/></s:Envelope>"
    let (env_17, err_17) = soap.parse(a, doc_17)
    if err_17 != ok || env_17.version != .Soap11 { try report("doc-version-empty-body", 17usize) }
    if (env_17.header != 4294967295u32) != false { try report("doc-header-empty-body", 17usize) }
    let payload_17 = soap.payload(&env_17)
    if payload_17 != 4294967295u32 { try report("doc-payload-empty-body", 17usize) }
    if soap.is_fault(&env_17) != false { try report("doc-isfault-empty-body", 17usize) }
    var must_ids_17: [8]u32 = zero
    let (must_17, must_error_17) = soap.must_understand_blocks(a, &env_17, must_ids_17[..])
    if must_error_17 != ok || must_17 != 0usize { try report("doc-must-empty-body", 17usize) }
    let (_, not_fault_error_17) = soap.parse_fault(a, &env_17)
    if not_fault_error_17 != soap.Invalid { try report("not-a-fault-empty-body", 17usize) }
    let doc_18 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\">\n <!-- c -->\n <s:Body>\n  <m:Q xmlns:m=\"urn:q\"/>\n </s:Body>\n</s:Envelope>"
    let (env_18, err_18) = soap.parse(a, doc_18)
    if err_18 != ok || env_18.version != .Soap11 { try report("doc-version-comments-and-space", 18usize) }
    if (env_18.header != 4294967295u32) != false { try report("doc-header-comments-and-space", 18usize) }
    let payload_18 = soap.payload(&env_18)
    let (pu_18, pl_18, pe_18) = soap.expand(&env_18.document, payload_18)
    if payload_18 == 4294967295u32 || pe_18 != ok || !same(pu_18, "urn:q") || !same(pl_18, "Q") { try report("doc-payload-comments-and-space", 18usize) }
    if soap.is_fault(&env_18) != false { try report("doc-isfault-comments-and-space", 18usize) }
    var must_ids_18: [8]u32 = zero
    let (must_18, must_error_18) = soap.must_understand_blocks(a, &env_18, must_ids_18[..])
    if must_error_18 != ok || must_18 != 0usize { try report("doc-must-comments-and-space", 18usize) }
    let (_, not_fault_error_18) = soap.parse_fault(a, &env_18)
    if not_fault_error_18 != soap.Invalid { try report("not-a-fault-comments-and-space", 18usize) }
    let doc_19 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><m:Q xmlns:m=\"urn:q\"/></s:Body><x:Extra xmlns:x=\"urn:x\"/></s:Envelope>"
    let (env_19, err_19) = soap.parse(a, doc_19)
    if err_19 != ok || env_19.version != .Soap11 { try report("doc-version-trailing11", 19usize) }
    if (env_19.header != 4294967295u32) != false { try report("doc-header-trailing11", 19usize) }
    let payload_19 = soap.payload(&env_19)
    let (pu_19, pl_19, pe_19) = soap.expand(&env_19.document, payload_19)
    if payload_19 == 4294967295u32 || pe_19 != ok || !same(pu_19, "urn:q") || !same(pl_19, "Q") { try report("doc-payload-trailing11", 19usize) }
    if soap.is_fault(&env_19) != false { try report("doc-isfault-trailing11", 19usize) }
    var must_ids_19: [8]u32 = zero
    let (must_19, must_error_19) = soap.must_understand_blocks(a, &env_19, must_ids_19[..])
    if must_error_19 != ok || must_19 != 0usize { try report("doc-must-trailing11", 19usize) }
    let (_, not_fault_error_19) = soap.parse_fault(a, &env_19)
    if not_fault_error_19 != soap.Invalid { try report("not-a-fault-trailing11", 19usize) }
    let doc_20 = "<s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"><s:Body><m:Q xmlns:m=\"urn:q\"/></s:Body><x:Extra xmlns:x=\"urn:x\"/></s:Envelope>"
    let (env_20, err_20) = soap.parse(a, doc_20)
    if err_20 != soap.Invalid { try report("doc-error-trailing12", 20usize) }
    let doc_21 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Header><t:T xmlns:t=\"urn:t\" xmlns:o=\"urn:other\" o:mustUnderstand=\"1\"/></s:Header><s:Body/></s:Envelope>"
    let (env_21, err_21) = soap.parse(a, doc_21)
    if err_21 != ok || env_21.version != .Soap11 { try report("doc-version-mu-wrong-ns", 21usize) }
    if (env_21.header != 4294967295u32) != true { try report("doc-header-mu-wrong-ns", 21usize) }
    let payload_21 = soap.payload(&env_21)
    if payload_21 != 4294967295u32 { try report("doc-payload-mu-wrong-ns", 21usize) }
    if soap.is_fault(&env_21) != false { try report("doc-isfault-mu-wrong-ns", 21usize) }
    var must_ids_21: [8]u32 = zero
    let (must_21, must_error_21) = soap.must_understand_blocks(a, &env_21, must_ids_21[..])
    if must_error_21 != ok || must_21 != 0usize { try report("doc-must-mu-wrong-ns", 21usize) }
    let (_, not_fault_error_21) = soap.parse_fault(a, &env_21)
    if not_fault_error_21 != soap.Invalid { try report("not-a-fault-mu-wrong-ns", 21usize) }
    let doc_22 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Header><a:A xmlns:a=\"urn:a\" s:mustUnderstand=\"1\"/><a:B xmlns:a=\"urn:a\" s:mustUnderstand=\"true\"/><a:C xmlns:a=\"urn:a\"/></s:Header><s:Body/></s:Envelope>"
    let (env_22, err_22) = soap.parse(a, doc_22)
    if err_22 != ok || env_22.version != .Soap11 { try report("doc-version-two-must", 22usize) }
    if (env_22.header != 4294967295u32) != true { try report("doc-header-two-must", 22usize) }
    let payload_22 = soap.payload(&env_22)
    if payload_22 != 4294967295u32 { try report("doc-payload-two-must", 22usize) }
    if soap.is_fault(&env_22) != false { try report("doc-isfault-two-must", 22usize) }
    var must_ids_22: [8]u32 = zero
    let (must_22, must_error_22) = soap.must_understand_blocks(a, &env_22, must_ids_22[..])
    if must_error_22 != ok || must_22 != 2usize { try report("doc-must-two-must", 22usize) }
    let (mu_22_0, ml_22_0, me_22_0) = soap.expand(&env_22.document, must_ids_22[0usize])
    if me_22_0 != ok || !same(ml_22_0, "A") { try report("doc-must-name-two-must", 22usize) }
    let (mu_22_1, ml_22_1, me_22_1) = soap.expand(&env_22.document, must_ids_22[1usize])
    if me_22_1 != ok || !same(ml_22_1, "B") { try report("doc-must-name-two-must", 22usize) }
    let (_, not_fault_error_22) = soap.parse_fault(a, &env_22)
    if not_fault_error_22 != soap.Invalid { try report("not-a-fault-two-must", 22usize) }
    let doc_23 = "<s:Envelope xmlns:s=\"http://example.org/soap/9\"><s:Body/></s:Envelope>"
    let (env_23, err_23) = soap.parse(a, doc_23)
    if err_23 != soap.VersionMismatch { try report("doc-error-version-mismatch", 23usize) }
    let doc_24 = "<html><body>hi</body></html>"
    let (env_24, err_24) = soap.parse(a, doc_24)
    if err_24 != soap.NotSoap { try report("doc-error-not-soap", 24usize) }
    let doc_25 = "<s:Envelopes xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body/></s:Envelopes>"
    let (env_25, err_25) = soap.parse(a, doc_25)
    if err_25 != soap.NotSoap { try report("doc-error-wrong-root-ns", 25usize) }
    let doc_26 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Header/></s:Envelope>"
    let (env_26, err_26) = soap.parse(a, doc_26)
    if err_26 != soap.Invalid { try report("doc-error-missing-body", 26usize) }
    let doc_27 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body/><s:Body/></s:Envelope>"
    let (env_27, err_27) = soap.parse(a, doc_27)
    if err_27 != soap.Invalid { try report("doc-error-duplicate-body", 27usize) }
    let doc_28 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body/><s:Header/></s:Envelope>"
    let (env_28, err_28) = soap.parse(a, doc_28)
    if err_28 != soap.Invalid { try report("doc-error-header-after-body", 28usize) }
    let doc_29 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Header/><s:Header/><s:Body/></s:Envelope>"
    let (env_29, err_29) = soap.parse(a, doc_29)
    if err_29 != soap.Invalid { try report("doc-error-two-headers", 29usize) }
    let doc_30 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><x:Pre xmlns:x=\"urn:x\"/><s:Body/></s:Envelope>"
    let (env_30, err_30) = soap.parse(a, doc_30)
    if err_30 != soap.Invalid { try report("doc-error-stray-before-body", 30usize) }
    let doc_31 = "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"/>"
    let (env_31, err_31) = soap.parse(a, doc_31)
    if err_31 != soap.Invalid { try report("doc-error-empty-envelope", 31usize) }
    let bad_xml_0 = "<s:Envelope"
    let (_, bad_xml_error_0) = soap.parse(a, bad_xml_0)
    if bad_xml_error_0 == ok { try report("malformed-xml", 0usize) }
    let bad_xml_1 = "<a><b></a>"
    let (_, bad_xml_error_1) = soap.parse(a, bad_xml_1)
    if bad_xml_error_1 == ok { try report("malformed-xml", 1usize) }
    let bad_xml_2 = ""
    let (_, bad_xml_error_2) = soap.parse(a, bad_xml_2)
    if bad_xml_error_2 == ok { try report("malformed-xml", 2usize) }
    let bad_xml_3 = "<s:Envelope xmlns:s=\"x\"><s:Body></s:Envelope>"
    let (_, bad_xml_error_3) = soap.parse(a, bad_xml_3)
    if bad_xml_error_3 == ok { try report("malformed-xml", 3usize) }
    var capacity: [4096]u8 = zero
    var sink_state = io.SliceWriter { data: capacity[..], off: 0usize }
    let op_attr = [1]xml.Attribute{ xml.Attribute { name: "xmlns:m", value: "urn:m" } }
    let mu_value_attr = [2]xml.Attribute{ xml.Attribute { name: "xmlns:t", value: "urn:t" }, xml.Attribute { name: "s:mustUnderstand", value: "1" } }
    var sink_0 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_0_made, b_0_error) = soap.builder(a, io.slice_writer(&sink_0), .Soap11, "soapenv")
    var b_0 = b_0_made
    if b_0_error != ok { try report("builder", 0usize) }
    var failed_0 = false
    if soap.begin(&b_0) != ok { failed_0 = true }
    if soap.body_start(&b_0) != ok { failed_0 = true }
    if xml.start(&b_0.w, "m:Op", op_attr[..]) != ok { failed_0 = true }
    if xml.text(&b_0.w, "a & b") != ok { failed_0 = true }
    if xml.end(&b_0.w, "m:Op") != ok { failed_0 = true }
    if soap.finish(&b_0) != ok { failed_0 = true }
    if failed_0 || !same(slice_text(&sink_0), "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\"><soapenv:Body><m:Op xmlns:m=\"urn:m\">a &amp; b</m:Op></soapenv:Body></soapenv:Envelope>") { try report("build-plain11", 0usize) }
    var sink_1 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_1_made, b_1_error) = soap.builder(a, io.slice_writer(&sink_1), .Soap12, "s")
    var b_1 = b_1_made
    if b_1_error != ok { try report("builder", 1usize) }
    var failed_1 = false
    if soap.begin(&b_1) != ok { failed_1 = true }
    if soap.body_start(&b_1) != ok { failed_1 = true }
    if xml.start(&b_1.w, "m:Op", op_attr[..]) != ok { failed_1 = true }
    if xml.end(&b_1.w, "m:Op") != ok { failed_1 = true }
    if soap.finish(&b_1) != ok { failed_1 = true }
    if failed_1 || !same(slice_text(&sink_1), "<s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"><s:Body><m:Op xmlns:m=\"urn:m\"></m:Op></s:Body></s:Envelope>") { try report("build-plain12", 1usize) }
    var mu_made_2: xml.Attribute = zero
    var sink_2 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_2_made, b_2_error) = soap.builder(a, io.slice_writer(&sink_2), .Soap11, "s")
    var b_2 = b_2_made
    if b_2_error != ok { try report("builder", 2usize) }
    var failed_2 = false
    if soap.begin(&b_2) != ok { failed_2 = true }
    if soap.header_start(&b_2) != ok { failed_2 = true }
    let (mu_attr_2, mu_attr_error_2) = soap.must_understand_attribute(&b_2)
    if mu_attr_error_2 != ok || !same(mu_attr_2.name, "s:mustUnderstand") || !same(mu_attr_2.value, "1") { try report("mu-attribute", 2usize) }
    let mu_attrs_2 = [2]xml.Attribute{ xml.Attribute { name: "xmlns:t", value: "urn:t" }, mu_attr_2 }
    if xml.start(&b_2.w, "t:Tx", mu_attrs_2[..]) != ok { failed_2 = true }
    if xml.text(&b_2.w, "9") != ok { failed_2 = true }
    if xml.end(&b_2.w, "t:Tx") != ok { failed_2 = true }
    if soap.header_end(&b_2) != ok { failed_2 = true }
    if soap.body_start(&b_2) != ok { failed_2 = true }
    if xml.start(&b_2.w, "m:Op", op_attr[..]) != ok { failed_2 = true }
    if xml.end(&b_2.w, "m:Op") != ok { failed_2 = true }
    if soap.finish(&b_2) != ok { failed_2 = true }
    if failed_2 || !same(slice_text(&sink_2), "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Header><t:Tx xmlns:t=\"urn:t\" s:mustUnderstand=\"1\">9</t:Tx></s:Header><s:Body><m:Op xmlns:m=\"urn:m\"></m:Op></s:Body></s:Envelope>") { try report("build-header-mu11", 2usize) }
    var sink_3 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_3_made, b_3_error) = soap.builder(a, io.slice_writer(&sink_3), .Soap12, "env")
    var b_3 = b_3_made
    if b_3_error != ok { try report("builder", 3usize) }
    var failed_3 = false
    if soap.begin(&b_3) != ok { failed_3 = true }
    if soap.header_start(&b_3) != ok { failed_3 = true }
    let (mu_attr_3, mu_attr_error_3) = soap.must_understand_attribute(&b_3)
    let mu_attrs_3 = [2]xml.Attribute{ xml.Attribute { name: "xmlns:t", value: "urn:t" }, mu_attr_3 }
    if mu_attr_error_3 != ok { failed_3 = true }
    if xml.start(&b_3.w, "t:Tx", mu_attrs_3[..]) != ok { failed_3 = true }
    if xml.text(&b_3.w, "9") != ok { failed_3 = true }
    if xml.end(&b_3.w, "t:Tx") != ok { failed_3 = true }
    if soap.header_end(&b_3) != ok { failed_3 = true }
    if soap.body_start(&b_3) != ok { failed_3 = true }
    if xml.start(&b_3.w, "m:Op", op_attr[..]) != ok { failed_3 = true }
    if xml.end(&b_3.w, "m:Op") != ok { failed_3 = true }
    if soap.finish(&b_3) != ok { failed_3 = true }
    if failed_3 || !same(slice_text(&sink_3), "<env:Envelope xmlns:env=\"http://www.w3.org/2003/05/soap-envelope\"><env:Header><t:Tx xmlns:t=\"urn:t\" env:mustUnderstand=\"1\">9</t:Tx></env:Header><env:Body><m:Op xmlns:m=\"urn:m\"></m:Op></env:Body></env:Envelope>") { try report("build-header-mu12", 3usize) }
    var sink_4 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_4_made, b_4_error) = soap.builder(a, io.slice_writer(&sink_4), .Soap11, "s")
    var b_4 = b_4_made
    if b_4_error != ok { try report("builder", 4usize) }
    var failed_4 = false
    if soap.begin(&b_4) != ok { failed_4 = true }
    if soap.body_start(&b_4) != ok { failed_4 = true }
    if soap.fault_write(&b_4, soap.FaultOut { code: .Sender, reason: "Bad <input>", language: "", actor: "http://actor", detail: "oops & more", subcode: "" }) != ok { failed_4 = true }
    if soap.finish(&b_4) != ok { failed_4 = true }
    if failed_4 || !same(slice_text(&sink_4), "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>Bad &lt;input&gt;</faultstring><faultactor>http://actor</faultactor><detail>oops &amp; more</detail></s:Fault></s:Body></s:Envelope>") { try report("build-f11-client", 4usize) }
    let (round_4, round_error_4) = soap.parse(a, slice_text(&sink_4))
    if round_error_4 != ok || !soap.is_fault(&round_4) { try report("build-roundtrip", 4usize) }
    let (round_fault_4, round_fault_error_4) = soap.parse_fault(a, &round_4)
    if round_fault_error_4 != ok { try report("build-roundtrip-fault", 4usize) }
    var sink_5 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_5_made, b_5_error) = soap.builder(a, io.slice_writer(&sink_5), .Soap11, "s")
    var b_5 = b_5_made
    if b_5_error != ok { try report("builder", 5usize) }
    var failed_5 = false
    if soap.begin(&b_5) != ok { failed_5 = true }
    if soap.body_start(&b_5) != ok { failed_5 = true }
    if soap.fault_write(&b_5, soap.FaultOut { code: .Receiver, reason: "down", language: "", actor: "", detail: "", subcode: "" }) != ok { failed_5 = true }
    if soap.finish(&b_5) != ok { failed_5 = true }
    if failed_5 || !same(slice_text(&sink_5), "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:Server</faultcode><faultstring>down</faultstring></s:Fault></s:Body></s:Envelope>") { try report("build-f11-server", 5usize) }
    let (round_5, round_error_5) = soap.parse(a, slice_text(&sink_5))
    if round_error_5 != ok || !soap.is_fault(&round_5) { try report("build-roundtrip", 5usize) }
    let (round_fault_5, round_fault_error_5) = soap.parse_fault(a, &round_5)
    if round_fault_error_5 != ok { try report("build-roundtrip-fault", 5usize) }
    var sink_6 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_6_made, b_6_error) = soap.builder(a, io.slice_writer(&sink_6), .Soap11, "s")
    var b_6 = b_6_made
    if b_6_error != ok { try report("builder", 6usize) }
    var failed_6 = false
    if soap.begin(&b_6) != ok { failed_6 = true }
    if soap.body_start(&b_6) != ok { failed_6 = true }
    if soap.fault_write(&b_6, soap.FaultOut { code: .VersionMismatch, reason: "v", language: "", actor: "", detail: "", subcode: "" }) != ok { failed_6 = true }
    if soap.finish(&b_6) != ok { failed_6 = true }
    if failed_6 || !same(slice_text(&sink_6), "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\"><s:Body><s:Fault><faultcode>s:VersionMismatch</faultcode><faultstring>v</faultstring></s:Fault></s:Body></s:Envelope>") { try report("build-f11-vm", 6usize) }
    let (round_6, round_error_6) = soap.parse(a, slice_text(&sink_6))
    if round_error_6 != ok || !soap.is_fault(&round_6) { try report("build-roundtrip", 6usize) }
    let (round_fault_6, round_fault_error_6) = soap.parse_fault(a, &round_6)
    if round_fault_error_6 != ok { try report("build-roundtrip-fault", 6usize) }
    var sink_7 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_7_made, b_7_error) = soap.builder(a, io.slice_writer(&sink_7), .Soap12, "s")
    var b_7 = b_7_made
    if b_7_error != ok { try report("builder", 7usize) }
    var failed_7 = false
    if soap.begin(&b_7) != ok { failed_7 = true }
    if soap.body_start(&b_7) != ok { failed_7 = true }
    if soap.fault_write(&b_7, soap.FaultOut { code: .Sender, reason: "bad", language: "", actor: "urn:role", detail: "why", subcode: "app:Code" }) != ok { failed_7 = true }
    if soap.finish(&b_7) != ok { failed_7 = true }
    if failed_7 || !same(slice_text(&sink_7), "<s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"><s:Body><s:Fault><s:Code><s:Value>s:Sender</s:Value><s:Subcode><s:Value>app:Code</s:Value></s:Subcode></s:Code><s:Reason><s:Text xml:lang=\"en\">bad</s:Text></s:Reason><s:Role>urn:role</s:Role><s:Detail>why</s:Detail></s:Fault></s:Body></s:Envelope>") { try report("build-f12-sender", 7usize) }
    let (round_7, round_error_7) = soap.parse(a, slice_text(&sink_7))
    if round_error_7 != ok || !soap.is_fault(&round_7) { try report("build-roundtrip", 7usize) }
    let (round_fault_7, round_fault_error_7) = soap.parse_fault(a, &round_7)
    if round_fault_error_7 != ok { try report("build-roundtrip-fault", 7usize) }
    var sink_8 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_8_made, b_8_error) = soap.builder(a, io.slice_writer(&sink_8), .Soap12, "e")
    var b_8 = b_8_made
    if b_8_error != ok { try report("builder", 8usize) }
    var failed_8 = false
    if soap.begin(&b_8) != ok { failed_8 = true }
    if soap.body_start(&b_8) != ok { failed_8 = true }
    if soap.fault_write(&b_8, soap.FaultOut { code: .Receiver, reason: "kaputt", language: "de", actor: "", detail: "", subcode: "" }) != ok { failed_8 = true }
    if soap.finish(&b_8) != ok { failed_8 = true }
    if failed_8 || !same(slice_text(&sink_8), "<e:Envelope xmlns:e=\"http://www.w3.org/2003/05/soap-envelope\"><e:Body><e:Fault><e:Code><e:Value>e:Receiver</e:Value></e:Code><e:Reason><e:Text xml:lang=\"de\">kaputt</e:Text></e:Reason></e:Fault></e:Body></e:Envelope>") { try report("build-f12-receiver-de", 8usize) }
    let (round_8, round_error_8) = soap.parse(a, slice_text(&sink_8))
    if round_error_8 != ok || !soap.is_fault(&round_8) { try report("build-roundtrip", 8usize) }
    let (round_fault_8, round_fault_error_8) = soap.parse_fault(a, &round_8)
    if round_fault_error_8 != ok { try report("build-roundtrip-fault", 8usize) }
    var sink_9 = io.SliceWriter { data: capacity[..], off: 0usize }
    let (b_9_made, b_9_error) = soap.builder(a, io.slice_writer(&sink_9), .Soap12, "s")
    var b_9 = b_9_made
    if b_9_error != ok { try report("builder", 9usize) }
    var failed_9 = false
    if soap.begin(&b_9) != ok { failed_9 = true }
    if soap.body_start(&b_9) != ok { failed_9 = true }
    if soap.fault_write(&b_9, soap.FaultOut { code: .DataEncodingUnknown, reason: "enc", language: "", actor: "", detail: "", subcode: "" }) != ok { failed_9 = true }
    if soap.finish(&b_9) != ok { failed_9 = true }
    if failed_9 || !same(slice_text(&sink_9), "<s:Envelope xmlns:s=\"http://www.w3.org/2003/05/soap-envelope\"><s:Body><s:Fault><s:Code><s:Value>s:DataEncodingUnknown</s:Value></s:Code><s:Reason><s:Text xml:lang=\"en\">enc</s:Text></s:Reason></s:Fault></s:Body></s:Envelope>") { try report("build-f12-dataenc", 9usize) }
    let (round_9, round_error_9) = soap.parse(a, slice_text(&sink_9))
    if round_error_9 != ok || !soap.is_fault(&round_9) { try report("build-roundtrip", 9usize) }
    let (round_fault_9, round_fault_error_9) = soap.parse_fault(a, &round_9)
    if round_fault_error_9 != ok { try report("build-roundtrip-fault", 9usize) }
    var sink_x = io.SliceWriter { data: capacity[..], off: 0usize }
    let (bx_made, bx_error) = soap.builder(a, io.slice_writer(&sink_x), .Soap11, "s")
    var bx = bx_made
    if soap.fault_write(&bx, soap.FaultOut { code: .DataEncodingUnknown, reason: "r", language: "", actor: "", detail: "", subcode: "" }) != soap.Invalid { try report("fault-refusal", 0usize) }
    if soap.fault_write(&bx, soap.FaultOut { code: .Other, reason: "r", language: "", actor: "", detail: "", subcode: "" }) != soap.Invalid { try report("fault-refusal", 1usize) }
    if soap.fault_write(&bx, soap.FaultOut { code: .Sender, reason: "", language: "", actor: "", detail: "", subcode: "" }) != soap.Invalid { try report("fault-refusal", 2usize) }
    let (_, empty_prefix_error) = soap.builder(a, io.slice_writer(&sink_x), .Soap11, "")
    if empty_prefix_error != soap.Invalid { try report("builder-prefix", 0usize) }
    let (ct11, ct11_error) = soap.content_type(a, .Soap11, "urn:act")
    let (ct12, ct12_error) = soap.content_type(a, .Soap12, "urn:act")
    let (ct12_bare, ct12_bare_error) = soap.content_type(a, .Soap12, "")
    if ct11_error != ok || ct12_error != ok || ct12_bare_error != ok || !same(ct11, "text/xml; charset=utf-8") || !same(ct12, "application/soap+xml; charset=utf-8; action=\"urn:act\"") || !same(ct12_bare, "application/soap+xml; charset=utf-8") { try report("content-type", 0usize) }
    let wsdl_0 = "<?xml version=\"1.0\"?><wsdl:definitions xmlns:wsdl=\"http://schemas.xmlsoap.org/wsdl/\" xmlns:soap=\"http://schemas.xmlsoap.org/wsdl/soap/\" xmlns:tns=\"urn:calc\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" targetNamespace=\"urn:calc\"><wsdl:message name=\"AddRequest\"><wsdl:part name=\"a\" type=\"xsd:int\"/><wsdl:part name=\"b\" type=\"xsd:int\"/></wsdl:message><wsdl:message name=\"AddResponse\"><wsdl:part name=\"sum\" type=\"xsd:long\"/></wsdl:message><wsdl:message name=\"NameRequest\"><wsdl:part name=\"body\" element=\"tns:Name\"/></wsdl:message><wsdl:message name=\"NameResponse\"><wsdl:part name=\"body\" element=\"tns:NameReply\"/></wsdl:message><wsdl:portType name=\"Calc\"><wsdl:operation name=\"Add\"><wsdl:input message=\"tns:AddRequest\"/><wsdl:output message=\"tns:AddResponse\"/></wsdl:operation><wsdl:operation name=\"Name\"><wsdl:input message=\"tns:NameRequest\"/><wsdl:output message=\"tns:NameResponse\"/></wsdl:operation><wsdl:operation name=\"Ping\"><wsdl:input message=\"tns:NameRequest\"/></wsdl:operation></wsdl:portType><wsdl:binding name=\"CalcBinding\" type=\"tns:Calc\"><soap:binding style=\"document\" transport=\"http://schemas.xmlsoap.org/soap/http\"/><wsdl:operation name=\"Add\"><soap:operation soapAction=\"urn:calc/Add\"/></wsdl:operation><wsdl:operation name=\"Name\"><soap:operation soapAction=\"urn:calc/Name\" style=\"rpc\"/></wsdl:operation></wsdl:binding><wsdl:service name=\"CalcService\"><wsdl:port name=\"CalcPort\" binding=\"tns:CalcBinding\"><soap:address location=\"http://calc.example/soap\"/></wsdl:port></wsdl:service></wsdl:definitions>"
    let (wd_0, wd_error_0) = soap.wsdl_parse(a, wsdl_0)
    if wd_error_0 != ok || !same(wd_0.target_namespace, "urn:calc") || !same(wd_0.location, "http://calc.example/soap") || wd_0.soap != .Soap11 || wd_0.operations.len != 3usize { try report("wsdl-header", 0usize) }
    if !same(wd_0.operations[0usize].name, "Add") || !same(wd_0.operations[0usize].action, "urn:calc/Add") || !same(wd_0.operations[0usize].style, "document") || !same(wd_0.operations[0usize].input, "AddRequest") || !same(wd_0.operations[0usize].output, "AddResponse") { try report("wsdl-operation", 0usize) }
    if wd_0.operations[0usize].input_parts.len != 2usize { try report("wsdl-parts-count", 0usize) }
    if !same(wd_0.operations[0usize].input_parts[0usize].name, "a") || !same(wd_0.operations[0usize].input_parts[0usize].type_name, "xsd:int") || !same(wd_0.operations[0usize].input_parts[0usize].element, "") { try report("wsdl-part", 0usize) }
    if !same(wd_0.operations[0usize].input_parts[1usize].name, "b") || !same(wd_0.operations[0usize].input_parts[1usize].type_name, "xsd:int") || !same(wd_0.operations[0usize].input_parts[1usize].element, "") { try report("wsdl-part", 0usize) }
    if wd_0.operations[0usize].output_parts.len != 1usize { try report("wsdl-parts-count", 0usize) }
    if !same(wd_0.operations[0usize].output_parts[0usize].name, "sum") || !same(wd_0.operations[0usize].output_parts[0usize].type_name, "xsd:long") || !same(wd_0.operations[0usize].output_parts[0usize].element, "") { try report("wsdl-part", 0usize) }
    if !same(wd_0.operations[1usize].name, "Name") || !same(wd_0.operations[1usize].action, "urn:calc/Name") || !same(wd_0.operations[1usize].style, "rpc") || !same(wd_0.operations[1usize].input, "NameRequest") || !same(wd_0.operations[1usize].output, "NameResponse") { try report("wsdl-operation", 1usize) }
    if wd_0.operations[1usize].input_parts.len != 1usize { try report("wsdl-parts-count", 1usize) }
    if !same(wd_0.operations[1usize].input_parts[0usize].name, "body") || !same(wd_0.operations[1usize].input_parts[0usize].type_name, "") || !same(wd_0.operations[1usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 1usize) }
    if wd_0.operations[1usize].output_parts.len != 1usize { try report("wsdl-parts-count", 1usize) }
    if !same(wd_0.operations[1usize].output_parts[0usize].name, "body") || !same(wd_0.operations[1usize].output_parts[0usize].type_name, "") || !same(wd_0.operations[1usize].output_parts[0usize].element, "tns:NameReply") { try report("wsdl-part", 1usize) }
    if !same(wd_0.operations[2usize].name, "Ping") || !same(wd_0.operations[2usize].action, "") || !same(wd_0.operations[2usize].style, "document") || !same(wd_0.operations[2usize].input, "NameRequest") || !same(wd_0.operations[2usize].output, "") { try report("wsdl-operation", 2usize) }
    if wd_0.operations[2usize].input_parts.len != 1usize { try report("wsdl-parts-count", 2usize) }
    if !same(wd_0.operations[2usize].input_parts[0usize].name, "body") || !same(wd_0.operations[2usize].input_parts[0usize].type_name, "") || !same(wd_0.operations[2usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 2usize) }
    if wd_0.operations[2usize].output_parts.len != 0usize { try report("wsdl-parts-count", 2usize) }
    let wsdl_1 = "<?xml version=\"1.0\"?><wsdl:definitions xmlns:wsdl=\"http://schemas.xmlsoap.org/wsdl/\" xmlns:soap=\"http://schemas.xmlsoap.org/wsdl/soap12/\" xmlns:tns=\"urn:calc\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" targetNamespace=\"urn:calc\"><wsdl:message name=\"AddRequest\"><wsdl:part name=\"a\" type=\"xsd:int\"/><wsdl:part name=\"b\" type=\"xsd:int\"/></wsdl:message><wsdl:message name=\"AddResponse\"><wsdl:part name=\"sum\" type=\"xsd:long\"/></wsdl:message><wsdl:message name=\"NameRequest\"><wsdl:part name=\"body\" element=\"tns:Name\"/></wsdl:message><wsdl:message name=\"NameResponse\"><wsdl:part name=\"body\" element=\"tns:NameReply\"/></wsdl:message><wsdl:portType name=\"Calc\"><wsdl:operation name=\"Add\"><wsdl:input message=\"tns:AddRequest\"/><wsdl:output message=\"tns:AddResponse\"/></wsdl:operation><wsdl:operation name=\"Name\"><wsdl:input message=\"tns:NameRequest\"/><wsdl:output message=\"tns:NameResponse\"/></wsdl:operation><wsdl:operation name=\"Ping\"><wsdl:input message=\"tns:NameRequest\"/></wsdl:operation></wsdl:portType><wsdl:binding name=\"CalcBinding\" type=\"tns:Calc\"><soap:binding style=\"document\" transport=\"http://schemas.xmlsoap.org/soap/http\"/><wsdl:operation name=\"Add\"><soap:operation soapAction=\"urn:calc/Add\"/></wsdl:operation><wsdl:operation name=\"Name\"><soap:operation soapAction=\"urn:calc/Name\" style=\"rpc\"/></wsdl:operation></wsdl:binding><wsdl:service name=\"CalcService\"><wsdl:port name=\"CalcPort\" binding=\"tns:CalcBinding\"><soap:address location=\"http://calc.example/soap\"/></wsdl:port></wsdl:service></wsdl:definitions>"
    let (wd_1, wd_error_1) = soap.wsdl_parse(a, wsdl_1)
    if wd_error_1 != ok || !same(wd_1.target_namespace, "urn:calc") || !same(wd_1.location, "http://calc.example/soap") || wd_1.soap != .Soap12 || wd_1.operations.len != 3usize { try report("wsdl-header", 1usize) }
    if !same(wd_1.operations[0usize].name, "Add") || !same(wd_1.operations[0usize].action, "urn:calc/Add") || !same(wd_1.operations[0usize].style, "document") || !same(wd_1.operations[0usize].input, "AddRequest") || !same(wd_1.operations[0usize].output, "AddResponse") { try report("wsdl-operation", 10usize) }
    if wd_1.operations[0usize].input_parts.len != 2usize { try report("wsdl-parts-count", 10usize) }
    if !same(wd_1.operations[0usize].input_parts[0usize].name, "a") || !same(wd_1.operations[0usize].input_parts[0usize].type_name, "xsd:int") || !same(wd_1.operations[0usize].input_parts[0usize].element, "") { try report("wsdl-part", 10usize) }
    if !same(wd_1.operations[0usize].input_parts[1usize].name, "b") || !same(wd_1.operations[0usize].input_parts[1usize].type_name, "xsd:int") || !same(wd_1.operations[0usize].input_parts[1usize].element, "") { try report("wsdl-part", 10usize) }
    if wd_1.operations[0usize].output_parts.len != 1usize { try report("wsdl-parts-count", 10usize) }
    if !same(wd_1.operations[0usize].output_parts[0usize].name, "sum") || !same(wd_1.operations[0usize].output_parts[0usize].type_name, "xsd:long") || !same(wd_1.operations[0usize].output_parts[0usize].element, "") { try report("wsdl-part", 10usize) }
    if !same(wd_1.operations[1usize].name, "Name") || !same(wd_1.operations[1usize].action, "urn:calc/Name") || !same(wd_1.operations[1usize].style, "rpc") || !same(wd_1.operations[1usize].input, "NameRequest") || !same(wd_1.operations[1usize].output, "NameResponse") { try report("wsdl-operation", 11usize) }
    if wd_1.operations[1usize].input_parts.len != 1usize { try report("wsdl-parts-count", 11usize) }
    if !same(wd_1.operations[1usize].input_parts[0usize].name, "body") || !same(wd_1.operations[1usize].input_parts[0usize].type_name, "") || !same(wd_1.operations[1usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 11usize) }
    if wd_1.operations[1usize].output_parts.len != 1usize { try report("wsdl-parts-count", 11usize) }
    if !same(wd_1.operations[1usize].output_parts[0usize].name, "body") || !same(wd_1.operations[1usize].output_parts[0usize].type_name, "") || !same(wd_1.operations[1usize].output_parts[0usize].element, "tns:NameReply") { try report("wsdl-part", 11usize) }
    if !same(wd_1.operations[2usize].name, "Ping") || !same(wd_1.operations[2usize].action, "") || !same(wd_1.operations[2usize].style, "document") || !same(wd_1.operations[2usize].input, "NameRequest") || !same(wd_1.operations[2usize].output, "") { try report("wsdl-operation", 12usize) }
    if wd_1.operations[2usize].input_parts.len != 1usize { try report("wsdl-parts-count", 12usize) }
    if !same(wd_1.operations[2usize].input_parts[0usize].name, "body") || !same(wd_1.operations[2usize].input_parts[0usize].type_name, "") || !same(wd_1.operations[2usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 12usize) }
    if wd_1.operations[2usize].output_parts.len != 0usize { try report("wsdl-parts-count", 12usize) }
    let wsdl_2 = "<?xml version=\"1.0\"?><wsdl:definitions xmlns:wsdl=\"http://schemas.xmlsoap.org/wsdl/\" xmlns:soap=\"http://schemas.xmlsoap.org/wsdl/soap/\" xmlns:tns=\"urn:calc\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" targetNamespace=\"urn:calc\"><wsdl:message name=\"AddRequest\"><wsdl:part name=\"a\" type=\"xsd:int\"/><wsdl:part name=\"b\" type=\"xsd:int\"/></wsdl:message><wsdl:message name=\"AddResponse\"><wsdl:part name=\"sum\" type=\"xsd:long\"/></wsdl:message><wsdl:message name=\"NameRequest\"><wsdl:part name=\"body\" element=\"tns:Name\"/></wsdl:message><wsdl:message name=\"NameResponse\"><wsdl:part name=\"body\" element=\"tns:NameReply\"/></wsdl:message><wsdl:portType name=\"Calc\"><wsdl:operation name=\"Add\"><wsdl:input message=\"tns:AddRequest\"/><wsdl:output message=\"tns:AddResponse\"/></wsdl:operation><wsdl:operation name=\"Name\"><wsdl:input message=\"tns:NameRequest\"/><wsdl:output message=\"tns:NameResponse\"/></wsdl:operation><wsdl:operation name=\"Ping\"><wsdl:input message=\"tns:NameRequest\"/></wsdl:operation></wsdl:portType><wsdl:binding name=\"CalcBinding\" type=\"tns:Calc\"><soap:binding style=\"rpc\" transport=\"http://schemas.xmlsoap.org/soap/http\"/><wsdl:operation name=\"Add\"><soap:operation soapAction=\"urn:calc/Add\"/></wsdl:operation><wsdl:operation name=\"Name\"><soap:operation soapAction=\"urn:calc/Name\" style=\"document\"/></wsdl:operation></wsdl:binding><wsdl:service name=\"CalcService\"><wsdl:port name=\"CalcPort\" binding=\"tns:CalcBinding\"><soap:address location=\"http://calc.example/soap\"/></wsdl:port></wsdl:service></wsdl:definitions>"
    let (wd_2, wd_error_2) = soap.wsdl_parse(a, wsdl_2)
    if wd_error_2 != ok || !same(wd_2.target_namespace, "urn:calc") || !same(wd_2.location, "http://calc.example/soap") || wd_2.soap != .Soap11 || wd_2.operations.len != 3usize { try report("wsdl-header", 2usize) }
    if !same(wd_2.operations[0usize].name, "Add") || !same(wd_2.operations[0usize].action, "urn:calc/Add") || !same(wd_2.operations[0usize].style, "rpc") || !same(wd_2.operations[0usize].input, "AddRequest") || !same(wd_2.operations[0usize].output, "AddResponse") { try report("wsdl-operation", 20usize) }
    if wd_2.operations[0usize].input_parts.len != 2usize { try report("wsdl-parts-count", 20usize) }
    if !same(wd_2.operations[0usize].input_parts[0usize].name, "a") || !same(wd_2.operations[0usize].input_parts[0usize].type_name, "xsd:int") || !same(wd_2.operations[0usize].input_parts[0usize].element, "") { try report("wsdl-part", 20usize) }
    if !same(wd_2.operations[0usize].input_parts[1usize].name, "b") || !same(wd_2.operations[0usize].input_parts[1usize].type_name, "xsd:int") || !same(wd_2.operations[0usize].input_parts[1usize].element, "") { try report("wsdl-part", 20usize) }
    if wd_2.operations[0usize].output_parts.len != 1usize { try report("wsdl-parts-count", 20usize) }
    if !same(wd_2.operations[0usize].output_parts[0usize].name, "sum") || !same(wd_2.operations[0usize].output_parts[0usize].type_name, "xsd:long") || !same(wd_2.operations[0usize].output_parts[0usize].element, "") { try report("wsdl-part", 20usize) }
    if !same(wd_2.operations[1usize].name, "Name") || !same(wd_2.operations[1usize].action, "urn:calc/Name") || !same(wd_2.operations[1usize].style, "document") || !same(wd_2.operations[1usize].input, "NameRequest") || !same(wd_2.operations[1usize].output, "NameResponse") { try report("wsdl-operation", 21usize) }
    if wd_2.operations[1usize].input_parts.len != 1usize { try report("wsdl-parts-count", 21usize) }
    if !same(wd_2.operations[1usize].input_parts[0usize].name, "body") || !same(wd_2.operations[1usize].input_parts[0usize].type_name, "") || !same(wd_2.operations[1usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 21usize) }
    if wd_2.operations[1usize].output_parts.len != 1usize { try report("wsdl-parts-count", 21usize) }
    if !same(wd_2.operations[1usize].output_parts[0usize].name, "body") || !same(wd_2.operations[1usize].output_parts[0usize].type_name, "") || !same(wd_2.operations[1usize].output_parts[0usize].element, "tns:NameReply") { try report("wsdl-part", 21usize) }
    if !same(wd_2.operations[2usize].name, "Ping") || !same(wd_2.operations[2usize].action, "") || !same(wd_2.operations[2usize].style, "document") || !same(wd_2.operations[2usize].input, "NameRequest") || !same(wd_2.operations[2usize].output, "") { try report("wsdl-operation", 22usize) }
    if wd_2.operations[2usize].input_parts.len != 1usize { try report("wsdl-parts-count", 22usize) }
    if !same(wd_2.operations[2usize].input_parts[0usize].name, "body") || !same(wd_2.operations[2usize].input_parts[0usize].type_name, "") || !same(wd_2.operations[2usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 22usize) }
    if wd_2.operations[2usize].output_parts.len != 0usize { try report("wsdl-parts-count", 22usize) }
    let wsdl_3 = "<?xml version=\"1.0\"?><wsdl:definitions xmlns:wsdl=\"http://schemas.xmlsoap.org/wsdl/\" xmlns:soap=\"http://schemas.xmlsoap.org/wsdl/soap12/\" xmlns:tns=\"urn:calc\" xmlns:xsd=\"http://www.w3.org/2001/XMLSchema\" targetNamespace=\"urn:calc\"><wsdl:message name=\"AddRequest\"><wsdl:part name=\"a\" type=\"xsd:int\"/><wsdl:part name=\"b\" type=\"xsd:int\"/></wsdl:message><wsdl:message name=\"AddResponse\"><wsdl:part name=\"sum\" type=\"xsd:long\"/></wsdl:message><wsdl:message name=\"NameRequest\"><wsdl:part name=\"body\" element=\"tns:Name\"/></wsdl:message><wsdl:message name=\"NameResponse\"><wsdl:part name=\"body\" element=\"tns:NameReply\"/></wsdl:message><wsdl:portType name=\"Calc\"><wsdl:operation name=\"Add\"><wsdl:input message=\"tns:AddRequest\"/><wsdl:output message=\"tns:AddResponse\"/></wsdl:operation><wsdl:operation name=\"Name\"><wsdl:input message=\"tns:NameRequest\"/><wsdl:output message=\"tns:NameResponse\"/></wsdl:operation><wsdl:operation name=\"Ping\"><wsdl:input message=\"tns:NameRequest\"/></wsdl:operation></wsdl:portType><wsdl:binding name=\"CalcBinding\" type=\"tns:Calc\"><soap:binding style=\"rpc\" transport=\"http://schemas.xmlsoap.org/soap/http\"/><wsdl:operation name=\"Add\"><soap:operation soapAction=\"urn:calc/Add\"/></wsdl:operation><wsdl:operation name=\"Name\"><soap:operation soapAction=\"urn:calc/Name\" style=\"document\"/></wsdl:operation></wsdl:binding><wsdl:service name=\"CalcService\"><wsdl:port name=\"CalcPort\" binding=\"tns:CalcBinding\"><soap:address location=\"http://calc.example/soap\"/></wsdl:port></wsdl:service></wsdl:definitions>"
    let (wd_3, wd_error_3) = soap.wsdl_parse(a, wsdl_3)
    if wd_error_3 != ok || !same(wd_3.target_namespace, "urn:calc") || !same(wd_3.location, "http://calc.example/soap") || wd_3.soap != .Soap12 || wd_3.operations.len != 3usize { try report("wsdl-header", 3usize) }
    if !same(wd_3.operations[0usize].name, "Add") || !same(wd_3.operations[0usize].action, "urn:calc/Add") || !same(wd_3.operations[0usize].style, "rpc") || !same(wd_3.operations[0usize].input, "AddRequest") || !same(wd_3.operations[0usize].output, "AddResponse") { try report("wsdl-operation", 30usize) }
    if wd_3.operations[0usize].input_parts.len != 2usize { try report("wsdl-parts-count", 30usize) }
    if !same(wd_3.operations[0usize].input_parts[0usize].name, "a") || !same(wd_3.operations[0usize].input_parts[0usize].type_name, "xsd:int") || !same(wd_3.operations[0usize].input_parts[0usize].element, "") { try report("wsdl-part", 30usize) }
    if !same(wd_3.operations[0usize].input_parts[1usize].name, "b") || !same(wd_3.operations[0usize].input_parts[1usize].type_name, "xsd:int") || !same(wd_3.operations[0usize].input_parts[1usize].element, "") { try report("wsdl-part", 30usize) }
    if wd_3.operations[0usize].output_parts.len != 1usize { try report("wsdl-parts-count", 30usize) }
    if !same(wd_3.operations[0usize].output_parts[0usize].name, "sum") || !same(wd_3.operations[0usize].output_parts[0usize].type_name, "xsd:long") || !same(wd_3.operations[0usize].output_parts[0usize].element, "") { try report("wsdl-part", 30usize) }
    if !same(wd_3.operations[1usize].name, "Name") || !same(wd_3.operations[1usize].action, "urn:calc/Name") || !same(wd_3.operations[1usize].style, "document") || !same(wd_3.operations[1usize].input, "NameRequest") || !same(wd_3.operations[1usize].output, "NameResponse") { try report("wsdl-operation", 31usize) }
    if wd_3.operations[1usize].input_parts.len != 1usize { try report("wsdl-parts-count", 31usize) }
    if !same(wd_3.operations[1usize].input_parts[0usize].name, "body") || !same(wd_3.operations[1usize].input_parts[0usize].type_name, "") || !same(wd_3.operations[1usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 31usize) }
    if wd_3.operations[1usize].output_parts.len != 1usize { try report("wsdl-parts-count", 31usize) }
    if !same(wd_3.operations[1usize].output_parts[0usize].name, "body") || !same(wd_3.operations[1usize].output_parts[0usize].type_name, "") || !same(wd_3.operations[1usize].output_parts[0usize].element, "tns:NameReply") { try report("wsdl-part", 31usize) }
    if !same(wd_3.operations[2usize].name, "Ping") || !same(wd_3.operations[2usize].action, "") || !same(wd_3.operations[2usize].style, "document") || !same(wd_3.operations[2usize].input, "NameRequest") || !same(wd_3.operations[2usize].output, "") { try report("wsdl-operation", 32usize) }
    if wd_3.operations[2usize].input_parts.len != 1usize { try report("wsdl-parts-count", 32usize) }
    if !same(wd_3.operations[2usize].input_parts[0usize].name, "body") || !same(wd_3.operations[2usize].input_parts[0usize].type_name, "") || !same(wd_3.operations[2usize].input_parts[0usize].element, "tns:Name") { try report("wsdl-part", 32usize) }
    if wd_3.operations[2usize].output_parts.len != 0usize { try report("wsdl-parts-count", 32usize) }
    let (wsdl_none, wsdl_none_error) = soap.wsdl_parse(a, "<definitions xmlns=\"urn:other\"/>")
    if wsdl_none_error != soap.Invalid { try report("wsdl-not-wsdl", 0usize) }
    let (wsdl_empty, wsdl_empty_error) = soap.wsdl_parse(a, "<wsdl:definitions xmlns:wsdl=\"http://schemas.xmlsoap.org/wsdl/\" targetNamespace=\"urn:e\"/>")
    if wsdl_empty_error != ok || wsdl_empty.operations.len != 0usize || !same(wsdl_empty.target_namespace, "urn:e") { try report("wsdl-empty", 0usize) }
    let (wsdl_unnamed, wsdl_unnamed_error) = soap.wsdl_parse(a, "<wsdl:definitions xmlns:wsdl=\"http://schemas.xmlsoap.org/wsdl/\"><wsdl:portType name=\"p\"><wsdl:operation/></wsdl:portType></wsdl:definitions>")
    if wsdl_unnamed_error != soap.Invalid { try report("wsdl-unnamed-operation", 0usize) }
    let xsd_names = [50]str{ "byte", "short", "int", "long", "integer", "nonNegativeInteger", "positiveInteger", "negativeInteger", "nonPositiveInteger", "unsignedByte", "unsignedShort", "unsignedInt", "unsignedLong", "boolean", "float", "double", "base64Binary", "hexBinary", "string", "normalizedString", "token", "anyURI", "QName", "NCName", "ID", "IDREF", "language", "Name", "NMTOKEN", "decimal", "dateTime", "date", "time", "duration", "gYear", "gYearMonth", "gMonth", "gMonthDay", "gDay", "anyType", "anySimpleType", "Int", "STRING", "xsd:int", "", "integers", "unsigned", "custom", "Boolean", "dateTimeStamp" }
    let xsd_want = [50]str{ "i8", "i16", "i32", "i64", "i64", "i64", "i64", "i64", "i64", "u8", "u16", "u32", "u64", "bool", "f32", "f64", "[]u8", "[]u8", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "str", "", "", "", "", "", "", "", "", "" }
    var xsd_i = 0usize
    while xsd_i < 50 {
        let (xsd_got, xsd_found) = soap.xsd_neper_type(xsd_names[xsd_i])
        if xsd_found != (xsd_want[xsd_i].len > 0usize) || !same(xsd_got, xsd_want[xsd_i]) { try report("xsd-type", xsd_i) }
        xsd_i += 1usize
    }
    let (xb_0, xb_error_0) = soap.parse_xsd_boolean("true")
    if (xb_error_0 == ok) != true || (xb_error_0 == ok && xb_0 != true) { try report("xsd-boolean", 0usize) }
    let (xb_1, xb_error_1) = soap.parse_xsd_boolean("false")
    if (xb_error_1 == ok) != true || (xb_error_1 == ok && xb_1 != false) { try report("xsd-boolean", 1usize) }
    let (xb_2, xb_error_2) = soap.parse_xsd_boolean("1")
    if (xb_error_2 == ok) != true || (xb_error_2 == ok && xb_2 != true) { try report("xsd-boolean", 2usize) }
    let (xb_3, xb_error_3) = soap.parse_xsd_boolean("0")
    if (xb_error_3 == ok) != true || (xb_error_3 == ok && xb_3 != false) { try report("xsd-boolean", 3usize) }
    let (xb_4, xb_error_4) = soap.parse_xsd_boolean(" true ")
    if (xb_error_4 == ok) != true || (xb_error_4 == ok && xb_4 != true) { try report("xsd-boolean", 4usize) }
    let (xb_5, xb_error_5) = soap.parse_xsd_boolean("\n1\n")
    if (xb_error_5 == ok) != true || (xb_error_5 == ok && xb_5 != true) { try report("xsd-boolean", 5usize) }
    let (xb_6, xb_error_6) = soap.parse_xsd_boolean("TRUE")
    if (xb_error_6 == ok) != false || (xb_error_6 == ok && xb_6 != false) { try report("xsd-boolean", 6usize) }
    let (xb_7, xb_error_7) = soap.parse_xsd_boolean("yes")
    if (xb_error_7 == ok) != false || (xb_error_7 == ok && xb_7 != false) { try report("xsd-boolean", 7usize) }
    let (xb_8, xb_error_8) = soap.parse_xsd_boolean("")
    if (xb_error_8 == ok) != false || (xb_error_8 == ok && xb_8 != false) { try report("xsd-boolean", 8usize) }
    let (xb_9, xb_error_9) = soap.parse_xsd_boolean("2")
    if (xb_error_9 == ok) != false || (xb_error_9 == ok && xb_9 != false) { try report("xsd-boolean", 9usize) }
    let (xb_10, xb_error_10) = soap.parse_xsd_boolean("tru")
    if (xb_error_10 == ok) != false || (xb_error_10 == ok && xb_10 != false) { try report("xsd-boolean", 10usize) }
    try io.print("fmt soap ok\n")
    ret ok
}
