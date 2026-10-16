# looks9: puts a bare reference crop sheet (ref/windows/<name>.png, the crops only) on a canvas of the size of our sheet
# (windows/<name>.png), at the cell offset the harness lays our cells at, so that a comparison can be made in place and
# needs no search for the offset. The crops' pixels are untouched; the canvas is our sheet's background colour. Idempotent
# (a reference that already has our size is left alone). Run from the repository root after the sheets are rendered:
#   python -I scripts/looks_ref_a/padref.py name:dx:dy [...]
import sys
from PIL import Image
R='docs/ui/looks/'
for arg in sys.argv[1:]:
    n,dx,dy=arg.split(':'); dx=int(dx); dy=int(dy)
    ref=Image.open(R+'ref/windows/%s.png'%n).convert('RGB'); ours=Image.open(R+'windows/%s.png'%n).convert('RGB')
    if ref.size==ours.size: print(n,'already the size'); continue
    canvas=Image.new('RGB',ours.size,ours.getpixel((0,0)))
    canvas.paste(ref,(dx,dy)); canvas.save(R+'ref/windows/%s.png'%n); print(n,ref.size,'->',canvas.size,'at',(dx,dy))
