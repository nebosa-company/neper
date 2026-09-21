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

    try io.print("valid ok\n")
    ret ok
}
