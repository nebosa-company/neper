# The constants net_auth and e.net.auth use: the Negotiate header value the fixture expects, and
# the DER bodies of the GSSAPI object identifiers auth.linux.e passes (SPNEGO, krb5, NTLMSSP and
# the two name types).
import base64


def oid(dotted):
    parts = [int(x) for x in dotted.split(".")]
    out = [40 * parts[0] + parts[1]]
    for v in parts[2:]:
        group = [v & 0x7F]
        v >>= 7
        while v:
            group.insert(0, 0x80 | (v & 0x7F))
            v >>= 7
        out += group
    return out


token = bytes([78, 84, 76, 77, 83, 83, 80, 0, 1, 0, 0, 0, 251, 255])
print("Negotiate " + base64.b64encode(token).decode())
for name, dotted in [("spnego", "1.3.6.1.5.5.2"), ("krb5", "1.2.840.113554.1.2.2"), ("ntlmssp", "1.3.6.1.4.1.311.2.2.10"), ("krb5 principal name", "1.2.840.113554.1.2.2.1"), ("host-based service", "1.2.840.113554.1.2.1.4")]:
    print(name, ", ".join(str(b) for b in oid(dotted)))
