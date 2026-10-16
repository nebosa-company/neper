# Round 5 group a: every captured button state (states/button-*) as a cell of button_states.png, diffed at scale 1.0.
# Builds docs/ui/looks/ref/windows/button_states.png (the crops, with 5 px of their dialog around) and prints per cell the
# largest per-channel error outside the caption area. Run with python -I from the repository root after rendering.
import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from lc import *
from bspec import SPEC
ST=R+'ref/windows/states/'
m=5; cols,cw,ch=4,133,40
n=len(SPEC)
ref=new_ref(n,cols,cw,ch)
rects={}
for i,(stem,rest,t,x,y,w,h,d,df,en) in enumerate(SPEC):
    vw,vh=w-2,h-1
    hw=vw+2*m; hw+= 1 if hw%2==0 else 0
    hh=vh+2*m; hh+= 1 if hh%2==1 else 0
    im=Image.open(ST+stem+'@1x.png').convert('RGB').crop((x+1-m,y+1-m,x+1-m+hw,y+1-m+hh))
    ox,oy=origin(i%cols,i//cols,cw,ch)
    px=ox+(cw-hw)//2; py=oy+(ch-hh)//2
    ref.paste(im,(px,py)); rects[i]=(px,py,hw,hh,m,vw,vh)
ref.save(R+'ref/windows/button_states.png')
ours=Image.open(R+'windows/button_states.png').convert('RGB')
def cmp(o,r,rect):
    px,py,hw,hh,m,vw,vh=rect; mx=0;bad=0;n=0;worst=None
    for yy in range(hh):
        for xx in range(hw):
            bx,by=xx-m,yy-m
            if 8<=bx<vw-8 and 5<=by<vh-5: continue   # caption area
            n+=1
            a=o.getpixel((px+xx,py+yy)); b=r.getpixel((px+xx,py+yy))
            dd=max(abs(p-q) for p,q in zip(a,b))
            if dd>2: bad+=1
            if dd>mx: mx=dd; worst=(bx,by,'%02X%02X%02X'%a,'%02X%02X%02X'%b)
    return mx,bad,n,worst
tot=0
for i,(stem,rest,t,x,y,w,h,d,df,en) in enumerate(SPEC):
    mx,bad,nn,worst=cmp(ours,ref,rects[i])
    print('%2d %-46s max %3d bad %4d/%d worst %s'%(i,stem,mx,bad,nn,worst))
    px,py,hw,hh,_,_,_=rects[i]
    if len(sys.argv)>1 and str(i) in sys.argv[1:]: sidebyside(ours,ref,(px,py,hw,hh),OUT+'bs_%d.png'%i,S=6)
