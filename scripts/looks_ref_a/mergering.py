# looks9: merges the ring phases fitted by fitring.py (states and hover; it writes D:/Temp/claude/looks9-w3/ringphases_<sheet>.json,
# edit the path for another machine) into ringphases.json (stem -> [left, top, right, bottom]). A pressed or focused button carries the
# focus dots, which spoil the left and right fit, so its left and right phases are those of the hover grab of the same button.
#   python -I scripts/looks_ref_a/mergering.py
import json,os,sys
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
from bspec import SPEC
src='D:/Temp/claude/looks9-w3/ringphases_%s.json'
ph={}
for sh in ('states','hover'): ph.update(json.load(open(src%sh)))
at={}
for (stem,rest,t,x,y,w,h,d,df,en) in SPEC:
    if stem.startswith('hover-') and not stem.endswith('-pressed') and stem in ph: at[(x,y,t)]=ph[stem]
out={}
for (stem,rest,t,x,y,w,h,d,df,en) in SPEC:
    if stem not in ph: continue
    v=list(ph[stem])
    if (not stem.startswith('hover-') or stem.endswith('-pressed')) and (x,y,t) in at:
        v[0]=at[(x,y,t)][0]; v[2]=at[(x,y,t)][2]
    out[stem]=[max(0.0,round(float(q),3)) for q in v]
json.dump(out,open(os.path.join(HERE,'ringphases.json'),'w'),indent=0)
print(len(out))
