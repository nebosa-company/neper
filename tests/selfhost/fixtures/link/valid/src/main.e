// `e.valid`: known-valid Luhn, ISBN-13/10, IBAN, EAN-13/8 and UPC-A numbers
// pass and their single-digit and transposition corruptions fail, as the
// Python replica decided; the Luhn check digit rebuilds a card number; the
// IBAN country table rejects a mod-97-valid number of the wrong length.
// Each check exits with its own code.

use e.io
use e.mem
use e.os
use e.valid

fn main(a: *mem.Arena, args: []str) -> err {
    // 1: Luhn.
    if !valid.luhn("4539 1488 0343 6467") || valid.luhn("4539 1488 1343 6467") || valid.luhn("5439 1488 0343 6467") { os.exit(1i32) }
    if !valid.luhn("79927398713") || valid.luhn("79927498713") || valid.luhn("97927398713") { os.exit(1i32) }
    if valid.luhn("7") || valid.luhn("79927398a13") || valid.luhn("0") || !valid.luhn("00") { os.exit(1i32) }
    let (d1, e1) = valid.luhn_check_digit("453914880343646")
    if e1 != ok || d1 != 7u8 { os.exit(1i32) }
    let (d2, e2) = valid.luhn_check_digit("7992739871")
    if e2 != ok || d2 != 3u8 { os.exit(1i32) }
    let (_, e3) = valid.luhn_check_digit("79x")
    if e3 != valid.Invalid { os.exit(1i32) }

    // 2: ISBN-13 and ISBN-10.
    if !valid.isbn13("978-0-306-40615-7") || valid.isbn13("978-0-307-40615-7") || valid.isbn13("798-0-306-40615-7") { os.exit(2i32) }
    if !valid.isbn10("0-306-40615-2") || valid.isbn10("0-306-41615-2") || valid.isbn10("3-006-40615-2") { os.exit(2i32) }
    if !valid.isbn10("0-8044-2957-X") || valid.isbn10("0-8045-2957-X") || valid.isbn10("8-0044-2957-X") { os.exit(2i32) }
    if valid.isbn10("0-80X4-2957-X") || valid.isbn10("0-306-40615-23") || valid.isbn13("978-0-306-40615") { os.exit(2i32) }

    // 3: IBAN.
    if !valid.iban("GB82 WEST 1234 5698 7654 32") || valid.iban("GB82 WEST 1234 5608 7654 32") || valid.iban("GB28 WEST 1234 5698 7654 32") { os.exit(3i32) }
    if !valid.iban("DE89 3704 0044 0532 0130 00") || valid.iban("DE89 3704 0044 1532 0130 00") || valid.iban("DE98 3704 0044 0532 0130 00") { os.exit(3i32) }
    if valid.iban("DE5137040044053201300") || !valid.iban("XX0837040044053201300") { os.exit(3i32) }
    if valid.iban("gb82 WEST 1234 5698 7654 32") || valid.iban("GB82 WEST 1234 5698 7654 3") || valid.iban("GB82-WEST 1234 5698 7654 32") { os.exit(3i32) }

    // 4: EAN-13, EAN-8, UPC-A.
    if !valid.ean13("4006381333931") || valid.ean13("4006382333931") || valid.ean13("0406381333931") { os.exit(4i32) }
    if !valid.ean8("73513537") || valid.ean8("73514537") || valid.ean8("37513537") { os.exit(4i32) }
    if !valid.upc_a("036000291452") || valid.upc_a("036000391452") || valid.upc_a("306000291452") { os.exit(4i32) }
    if valid.ean13("73513537") || valid.ean8("4006381333931") { os.exit(4i32) }

    // 5 to 10: ISIN, LEI, VIN, Verhoeff, BIC and a card's expiry, against python-stdnum (VIN: the NHTSA rule).
    if valid.isin("US0378331005") != true || valid.isin("US0378331006") != false || valid.isin("DE000BAY0017") != true || valid.isin("DE000BAY0018") != false || valid.isin("GB0002634946") != true || valid.isin("GB0002634947") != false || valid.isin("AU0000XVGZA3") != true || valid.isin("XS0000000009") != true || valid.isin("US037833100") != false || valid.isin("US03783310055") != false { os.exit(5i32) }
    if valid.lei("5493001KJTIIGC8Y1R12") != true || valid.lei("5493001KJTIIGC8Y1R13") != false || valid.lei("529900T8BM49AURSDO55") != true || valid.lei("529900T8BM49AURSDO56") != false || valid.lei("HWUPKR0MPOU8FGXBT394") != true || valid.lei("HWUPKR0MPOU8FGXBT395") != false || valid.lei("5493001KJTIIGC8Y1R1") != false || valid.lei("5493001KJTIIGC8Y1R123") != false { os.exit(6i32) }
    if valid.vin("1M8GDM9AXKP042788") != true || valid.vin("1M8GDM9A1KP042788") != false || valid.vin("11111111111111111") != true || valid.vin("1HGCM82633A004352") != true || valid.vin("1HGCM82633A004353") != false || valid.vin("JH4KA7561PC008269") != true || valid.vin("JH4KA7561PC008260") != false || valid.vin("1HGCM82633A00435") != false || valid.vin("1HGCM82633A0043521") != false || valid.vin("1HGCM82O33A004352") != false { os.exit(7i32) }
    if valid.verhoeff("2363") != true || valid.verhoeff("2364") != false || valid.verhoeff("12345") != false || valid.verhoeff("123451") != true || valid.verhoeff("00") != false || valid.verhoeff("1234567890123456") != false || valid.verhoeff("75872") != false || valid.verhoeff("758723") != false { os.exit(8i32) }
    if valid.bic("DEUTDEFF") != true || valid.bic("DEUTDEFF500") != true || valid.bic("DEUTDEF") != false || valid.bic("NEPER1E2XXX") != false || valid.bic("DEUT1EFF") != false || valid.bic("BOFAUS3N") != true || valid.bic("BOFAUS3NXXX1") != false { os.exit(9i32) }
    if valid.card_expiry(12u32, 2026u32, 10u32, 2026u32) != true || valid.card_expiry(9u32, 2026u32, 10u32, 2026u32) != false || valid.card_expiry(10u32, 2026u32, 10u32, 2026u32) != true || valid.card_expiry(1u32, 27u32, 10u32, 2026u32) != true || valid.card_expiry(13u32, 2027u32, 10u32, 2026u32) != false || valid.card_expiry(0u32, 2027u32, 10u32, 2026u32) != false || valid.card_expiry(6u32, 2047u32, 10u32, 2026u32) != false || valid.card_expiry(6u32, 2046u32, 10u32, 2026u32) != true || valid.card_expiry(12u32, 25u32, 10u32, 2026u32) != false { os.exit(10i32) }
    if valid.isin("us0378331005") || valid.bic("deutdeff") || valid.verhoeff("0") || valid.lei("5493001kjtiigc8y1r12") { os.exit(11i32) }

    try io.print("valid ok\n")
    ret ok
}
