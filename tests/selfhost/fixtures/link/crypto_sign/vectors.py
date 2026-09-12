# The RFC 8032 section 7.1 vectors (tests 1-3) in the fixture, and the constants
# sign.e carries as byte arrays: d, 2d, sqrt(-1), p - 2, (p - 5) / 8, L's limbs.
def arr(name, h):
    return "    let %s: [%d]u8 = [%d]u8{ %s }" % (name, len(h), len(h), ", ".join(str(b) for b in h))

v = {
    't1_sk': '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
    't1_pk': 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a',
    't1_sig': 'e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b',
    't2_sk': '4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb',
    't2_pk': '3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c',
    't2_sig': '92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00',
    't3_sk': 'c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7',
    't3_pk': 'fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025',
    't3_sig': '6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a',
}
print("\n".join(arr(k, bytes.fromhex(h)) for k, h in v.items()))

p = 2**255 - 19
d = (-121665 * pow(121666, -1, p)) % p
L = 2**252 + 27742317777372353535851937790883648493
enc = lambda x: x.to_bytes(32, 'little')
print(arr('l_bytes', enc(L)))
print('// sign.e constants')
for name, x in (('d', d), ('2d', 2 * d % p), ('sqrt(-1)', pow(2, (p - 1) // 4, p)), ('p - 2', p - 2), ('(p - 5) / 8', (p - 5) // 8)):
    print(name, list(enc(x)))
print('L limbs', [(L >> (32 * i)) & 0xffffffff for i in range(8)])
