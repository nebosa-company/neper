# looks5: for each scaled-form button cell of button_states.png (render it with zero shifts first): fit the sub-pixel translation (dx, dy) that, applied to our crisp render
# (bilinear), best matches the capture. Prints a table; python -I.
import sys,os; HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
import numpy as np
from PIL import Image as I
from lc import *
from bspec import SPEC
ST=R+'ref/windows/states/'
m=5; cols,cw,ch=4,133,40
ours=I.open(R+'windows/button_states.png').convert('RGB'); ref=I.open(R+'ref/windows/button_states.png').convert('RGB')
res={}
for i,(stem,rest,t,x,y,w,h,d,df,en) in enumerate(SPEC):
    if i<16: continue
    vw,vh=w-2,h-1
    hw=vw+2*m; hw+= 1 if hw%2==0 else 0
    hh=vh+2*m; hh+= 1 if hh%2==1 else 0
    ox,oy=origin(i%cols,i//cols,cw,ch); px=ox+(cw-hw)//2; py=oy+(ch-hh)//2
    o=ours.crop((px,py,px+hw,py+hh)); r=np.array(ref.crop((px,py,px+hw,py+hh)).convert('RGB'),float)
    # compare ring zone only (outside text): mask interior
    mask=np.ones((hh,hw),bool); mask[m+5:m+vh-5, m+8:m+vw-8]=False
    best=None
    for dx in np.arange(0.0,1.0001,0.02):
        for dy in np.arange(0.0,1.0001,0.02):
            t=o.transform(o.size,I.AFFINE,(1,0,-dx,0,1,-dy),resample=I.BILINEAR)
            T=np.array(t,float)
            e=np.abs(T-r).max(axis=2)
            err=e[mask].mean()
            if best is None or err<best[0]: best=(err,dx,dy,e[mask].max())
    res[i]=best
    import json
print('%2d %-44s x %3d y %3d  dx %.2f dy %.2f  mean %.2f max %.0f   x/1440 %.2f y/900 %.2f'%(i,stem,x,y,best[1],best[2],best[0],best[3],(x%1440)/1440.0,(y/900.0)%1))

json.dump({str(i):[round(float(b[1]),2),round(float(b[2]),2)] for i,b in res.items()},open(os.path.join(HERE,'phases.json'),'w'))
