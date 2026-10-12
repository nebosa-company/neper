import zipfile, io, sys
buf = io.BytesIO()
ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
    z.writestr('xl/workbook.xml', f'<?xml version="1.0"?><workbook {ns}><sheets><sheet name="Budget" sheetId="1" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/><sheet name="Notes &amp; more" sheetId="2"/></sheets></workbook>')
    z.writestr('xl/sharedStrings.xml', f'<?xml version="1.0"?><sst {ns} count="3" uniqueCount="3"><si><t>Item</t></si><si><t>Rent &amp; bills</t></si><si><r><t>Tea</t></r><r><t xml:space="preserve"> bags</t></r></si></sst>')
    z.writestr('xl/worksheets/sheet1.xml', f'<?xml version="1.0"?><worksheet {ns}><sheetData>'
      '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><t>Cost</t></is></c><c r="D1" t="b"><v>1</v></c></row>'
      '<row r="3"><c r="A3" t="s"><v>1</v></c><c r="B3"><v>1200.5</v></c><c r="C3" t="b"><v>0</v></c></row>'
      '<row r="4"><c r="A4" t="s"><v>2</v></c><c r="AA4"><f>1+1</f><v>2</v></c></row>'
      '</sheetData></worksheet>')
    z.writestr('xl/worksheets/sheet2.xml', f'<?xml version="1.0"?><worksheet {ns}><sheetData><row r="2"><c r="B2" t="str"><v>only</v></c></row></sheetData></worksheet>')
data = buf.getvalue()
open('book.xlsx','wb').write(data)
print(len(data))
print(', '.join(map(str, data)))
