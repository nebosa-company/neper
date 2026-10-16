# Round 5 group a: every captured button state (states/button-*, states/hover-button-*) as a cell of button_states.png and
# button_hover.png, diffed at scale 1.0.
#   python -I scripts/looks_ref_a/btn5.py states|hover [cell numbers to write side-by-side pictures for]
# Builds docs/ui/looks/ref/windows/button_<sheet>.png (the crops, with 5 px of their dialog around) and prints per cell the
# largest per-channel error outside the caption (and the picture of a picture button), with the number of pixels over 2.
import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from PIL import Image
from lc import *
from bspec import SPEC
SHEET=sys.argv[1] if len(sys.argv)>1 else 'states'
ST=R+'ref/windows/states/'
m=5; cols,cw,ch=4,133,40
ROWS=[r for r in SPEC if (r[7]=='H')==(SHEET=='hover')]
if SHEET=='states':
    ROWS=ROWS+[('%s'%nm,'',t,0,0,w,h,d,df,1) for (nm,t,w,h,d,df) in (('75x32 rest','Cancel',75,32,'N',0),('75x32 default','OK',75,32,'N',1),('75x32 focus','Cancel',75,32,'F',0),('75x32 pressed','OK',75,32,'P',1),('125x40 default','Apply',125,40,'N',1))]
n=len(ROWS)
real=[r for r in ROWS if r[1]!='']
ref=new_ref(n,cols,cw,ch)
rects={}
for i,(stem,rest,t,x,y,w,h,d,df,en) in enumerate(ROWS):
    vw,vh=w-2,h-1
    hw=vw+2*m; hw+= 1 if hw%2==0 else 0
    hh=vh+2*m; hh+= 1 if hh%2==1 else 0
    ox,oy=origin(i%cols,i//cols,cw,ch)
    px=ox+(cw-hw)//2; py=oy+(ch-hh)//2
    rects[i]=(px,py,hw,hh,m,vw,vh)
    if rest=='': continue
    im=Image.open(ST+stem+'@1x.png').convert('RGB').crop((x+1-m,y+1-m,x+1-m+hw,y+1-m+hh))
    ref.paste(im,(px,py))
ref.save(R+'ref/windows/button_%s.png'%SHEET)
ours=Image.open(R+'windows/button_%s.png'%SHEET).convert('RGB')
def cmp(o,r,rect,picture):
    px,py,hw,hh,m,vw,vh=rect; mx=0;bad=0;n=0;worst=None
    ix,iy=(4,4) if picture else (8,5)
    for yy in range(hh):
        for xx in range(hw):
            bx,by=xx-m,yy-m
            if ix<=bx<vw-ix and iy<=by<vh-iy: continue   # the caption or the picture
            n+=1
            a=o.getpixel((px+xx,py+yy)); b=r.getpixel((px+xx,py+yy))
            dd=max(abs(p-q) for p,q in zip(a,b))
            if dd>2: bad+=1
            if dd>mx: mx=dd; worst=(bx,by,'%02X%02X%02X'%a,'%02X%02X%02X'%b)
    return mx,bad,n,worst
for i,(stem,rest,t,x,y,w,h,d,df,en) in enumerate(ROWS):
    if rest=='': continue
    mx,bad,nn,worst=cmp(ours,ref,rects[i],t=='')
    print('%2d %-52s max %3d bad %4d/%d worst %s'%(i,stem,mx,bad,nn,worst))
    px,py,hw,hh,_,_,_=rects[i]
    if str(i) in sys.argv[2:]: sidebyside(ours,ref,(px,py,hw,hh),OUT+'bs_%s_%d.png'%(SHEET,i),S=6)
