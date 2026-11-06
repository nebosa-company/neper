// #602 regression: a package whose workbook, sheets, cells and shared strings are all
// bound to an unrelated namespace (foreign:workbook / foreign:sheet / foreign:c /
// foreign:si, plus foreign:x:id instead of r:id) must not decode as spreadsheet data.
// A local-name-only reader accepts it; the namespace-aware reader must not.
use e.io
use e.os
use e.mem
use e.str
use e.fmt.xlsx.book as book
use e.fmt.zip.write as zipw

fn main(a: *mem.Arena, args: []str) -> err {
    let types = "<?xml version=\"1.0\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/></Types>"
    let root_rels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId0\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
    let workbook = "<?xml version=\"1.0\"?><foreign:workbook xmlns:foreign=\"urn:not-spreadsheetml\" xmlns:x=\"urn:not-relationships\"><foreign:sheets><foreign:sheet name=\"Evil\" sheetId=\"1\" x:id=\"rId1\"/></foreign:sheets></foreign:workbook>"
    let workbook_rels = "<?xml version=\"1.0\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"
    let worksheet = "<?xml version=\"1.0\"?><foreign:worksheet xmlns:foreign=\"urn:not-spreadsheetml\"><foreign:sheetData><foreign:row r=\"1\"><foreign:c r=\"A1\" t=\"inlineStr\"><foreign:is><foreign:t>evil</foreign:t></foreign:is></foreign:c></foreign:row></foreign:sheetData></foreign:worksheet>"
    let parts: [5]zipw.Part = [5]zipw.Part{
        zipw.Part { name: "[Content_Types].xml", data: types },
        zipw.Part { name: "_rels/.rels", data: root_rels },
        zipw.Part { name: "xl/workbook.xml", data: workbook },
        zipw.Part { name: "xl/_rels/workbook.xml.rels", data: workbook_rels },
        zipw.Part { name: "xl/worksheets/sheet1.xml", data: worksheet },
    }
    let (bytes, zip_error) = zipw.store(a, parts[0..])
    if zip_error != ok { os.exit(2) }
    let (back, decode_error) = book.decode(a, bytes)
    // Either the workbook is refused outright, or it decodes with no sheet at all.
    if decode_error == ok && back.len != 0usize { os.exit(1) }
    if decode_error == ok {
        var i = 0usize
        while i < back.len {
            if str.eq(back[i].name, "Evil") { os.exit(1) }
            if back[i].grid.len != 0usize { os.exit(3) }
            i += 1usize
        }
    }
    try io.print("xlsx foreign package ok\n")
    ret ok
}

