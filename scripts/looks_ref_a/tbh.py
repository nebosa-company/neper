# Round 5 group a: the title bar hover sheet (title_bar_hover.png) against the hover grabs of the live v3
# (states/hover-caption-*). Builds ref/windows/title_bar_hover.png and prints per cell the largest per-channel error of the
# whole bar outside the title text. Run with python -I from the repository root after rendering.
import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
ST=R+'ref/windows/states/'
cols,cw,ch=1,1600,31
S=[('hover-caption-close-main',784,39),('hover-caption-maximize-main',784,85),('hover-caption-minimize-main',784,131),('hover-caption-inactive-main',784,39),('hover-caption-close-options',712,105),('hover-caption-inactive-options',712,105)]
ref=new_ref(6,cols,cw,ch)
rects={}
for i,(n,w,off) in enumerate(S):
    im=Image.open(ST+n+'@1x.png').convert('RGB').crop((8,0,8+w,31))
    ox,oy=origin(0,i,cw,ch); ref.paste(im,(ox+off,oy)); rects[i]=(ox+off,oy,w,31)
ref.save(R+'ref/windows/title_bar_hover.png')
ours=Image.open(R+'windows/title_bar_hover.png').convert('RGB')
for i,(x,y,w,h) in rects.items():
    mx=bad=0; where=None
    for yy in range(31):
        for xx in range(w):
            if 28<=xx<w-150 and w>740: continue   # title text
            if 28<=xx<w-60 and w<740: continue
            d=max(abs(p-q) for p,q in zip(ours.getpixel((x+xx,y+yy)),ref.getpixel((x+xx,y+yy))))
            if d>2: bad+=1
            if d>mx: mx=d; where=(xx,yy,ours.getpixel((x+xx,y+yy)),ref.getpixel((x+xx,y+yy)))
    print('%-34s max %3d bad %3d worst %s'%(S[i][0],mx,bad,where))
    sidebyside(ours,ref,(x+w-150,y,150,31),OUT+'cmp_tbh_%d.png'%i,S=4)
