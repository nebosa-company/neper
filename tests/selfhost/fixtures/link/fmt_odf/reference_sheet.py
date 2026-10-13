#!/usr/bin/env python3
"""An `.ods` for the fmt_odf fixture's sheet checks (D4803), written with Python's zipfile.

  Budget -- header row Item, Cost, Done; a row with a text paragraph, a float cell (office:value 1200.5, display "1,200.50")
            and a boolean; a row holding a cell repeated three times (number-columns-repeated="3"); a row repeated
            twice (number-rows-repeated="2"); then 5000 empty repeated rows, which are not part of the grid
  Notes  -- one cell with two paragraphs

usage: reference_sheet.py   prints the byte count and the bytes as a comma separated list.
"""
import io
import zipfile

NS = ('xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
      'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"')

content = (
    '<?xml version="1.0"?><office:document-content %s><office:body><office:spreadsheet>'
    '<table:table table:name="Budget">'
    '<table:table-row><table:table-cell office:value-type="string"><text:p>Item</text:p></table:table-cell>'
    '<table:table-cell office:value-type="string"><text:p>Cost</text:p></table:table-cell>'
    '<table:table-cell office:value-type="string"><text:p>Done</text:p></table:table-cell></table:table-row>'
    '<table:table-row><table:table-cell office:value-type="string"><text:p>Rent &amp; bills</text:p></table:table-cell>'
    '<table:table-cell office:value-type="float" office:value="1200.5"><text:p>1,200.50</text:p></table:table-cell>'
    '<table:table-cell office:value-type="boolean" office:boolean-value="true"/></table:table-row>'
    '<table:table-row><table:table-cell table:number-columns-repeated="3" office:value-type="string"><text:p>x</text:p></table:table-cell></table:table-row>'
    '<table:table-row table:number-rows-repeated="2"><table:table-cell/><table:table-cell office:value-type="float" office:value="7"/></table:table-row>'
    '<table:table-row table:number-rows-repeated="5000"><table:table-cell table:number-columns-repeated="1024"/></table:table-row>'
    '</table:table>'
    '<table:table table:name="Notes"><table:table-row><table:table-cell office:value-type="string">'
    '<text:p>first</text:p><text:p>second</text:p></table:table-cell></table:table-row></table:table>'
    '</office:spreadsheet></office:body></office:document-content>' % NS)

buf = io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("mimetype", "application/vnd.oasis.opendocument.spreadsheet")
    z.writestr("content.xml", content)
data = buf.getvalue()
print(len(data))
print(", ".join(str(b) for b in data))
