# looks5: for each scaled-form button cell of button_states.png or button_hover.png (render the sheet with zero shifts first,
# i.e. with phases.json emptied or without those stems): fit the sub-pixel translation (dx, dy) that, applied to our crisp
# render (bilinear), best matches the capture, and merge it into phases.json (stem -> [dx, dy]). Only the four DPI-scaled
# forms (Options, Deck Properties, Deck Legality, About) are fitted.
#   python -I scripts/looks_ref_a/fitshift.py states|hover
import sys,os,json
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
import numpy as np
from PIL import Image as I
from lc import *
from bspec import SPEC
SHEET=sys.argv[1] if len(sys.argv)>1 else 'states'
ST=R+'ref/windows/states/'
m=5; cols,cw,ch=4,133,40
ours=I.open(R+'windows/button_%s.png'%SHEET).convert('RGB'); ref=I.open(R+'ref/windows/button_%s.png'%SHEET).convert('RGB')
rows=[r for r in SPEC if (r[7]=='H')==(SHEET=='hover')]
pf=os.path.join(HERE,'phases.json')
res=json.load(open(pf)) if os.path.exists(pf) else {}
for i,(stem,rest,t,x,y,w,h,d,df,en) in enumerate(rows):
    if not any(k in rest for k in ('about','deck-legality','deck-properties','options')): continue
    vw,vh=w-2,h-1
    hw=vw+2*m; hw+= 1 if hw%2==0 else 0
    hh=vh+2*m; hh+= 1 if hh%2==1 else 0
    ox,oy=origin(i%cols,i//cols,cw,ch); px=ox+(cw-hw)//2; py=oy+(ch-hh)//2
    o=ours.crop((px,py,px+hw,py+hh)); r=np.array(ref.crop((px,py,px+hw,py+hh)).convert('RGB'),float)
    ink=4 if t=='' else 8
    mask=np.ones((hh,hw),bool); mask[m+5:m+vh-5, m+ink:m+vw-ink]=False
    best=None
    for dx in np.arange(0.0,1.0001,0.02):
        for dy in np.arange(0.0,1.0001,0.02):
            T=np.array(o.transform(o.size,I.AFFINE,(1,0,-dx,0,1,-dy),resample=I.BILINEAR),float)
            e=np.abs(T-r).max(axis=2)
            err=e[mask].mean()
            if best is None or err<best[0]: best=(err,dx,dy,e[mask].max())
    res[stem]=[round(float(best[1]),2),round(float(best[2]),2)]
    print('%2d %-52s x %3d y %3d  dx %.2f dy %.2f  mean %.2f max %.0f'%(i,stem,x,y,best[1],best[2],best[0],best[3]))
json.dump(res,open(pf,'w'),indent=0)
