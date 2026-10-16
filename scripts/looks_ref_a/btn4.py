# Round 4, group a: the button sheets against the live interaction-state grabs (docs/ui/looks/ref/windows/states).
# Builds docs/ui/looks/ref/windows/button.png (and button_shift.png) from real crops and prints, per cell, the largest
# per-channel error outside the caption area. Run with python -I from the repository root after rendering.
import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
ST=R+'ref/windows/states/'
def st(name): return ST+name+'@1x.png'
cols,cw,ch=4,133,40
SPEC={0:('search-filter-top@1x.png',(532,455,75,23)),
 1:('search-search@1x.png',(83,215,75,23)),
 2:('search-filter-top@1x.png',(616,455,75,23)),
 3:('view-conditional-formatting@1x.png',(597,378,85,25)),
 5:(st('button-pressed-search-cancel'),(167,215,75,23)),
 6:(st('button-focused-filter-invert'),(195,413,75,23)),
 7:(st('button-focused-conditional-formatting-apply'),(415,378,85,25)),
 8:('view-conditional-formatting@1x.png',(415,378,85,25)),
 9:('view-conditional-formatting@1x.png',(506,378,85,25)),
 10:(st('button-pressed-sort-ok'),(193,310,75,23)),
 11:(st('button-pressed-conditional-formatting-ok'),(415,378,85,25))}
NAMES=['normal','default','mnemonic','disabled','hover','pressed','focus Invert','default focus','default 85x25','normal 85x25','pressed default','pressed 85x25']
ref=new_ref(12,cols,cw,ch)
rects={}
for i,(src,(x,y,w,h)) in SPEC.items():
    if i==6:
        # looks5: the Filter dialog's face is #F9F9F9: crop 5 px of it around the box (an 83 x 32 holder in the cell)
        m=5; hw,hh=w-2+2*m,h-1+2*m
        hw+=1 if hw%2==0 else 0
        hh+=1 if hh%2==1 else 0
        c=Image.open(src if os.path.isabs(src) else D+src).convert('RGB').crop((x+1-m,y+1-m,x+1-m+hw,y+1-m+hh))
        ox,oy=origin(i%cols,i//cols,cw,ch)
        px,py=ox+(cw-hw)//2,oy+(ch-hh)//2
        ref.paste(c,(px,py)); rects[i]=(px+m,py+m,w-2,h-1)
        continue
    rects[i]=place(ref,i,cols,cw,ch,src,(x+1,y+1,w-2,h-1))
ref.save(R+'ref/windows/button.png')
def cmp(ours,ref,rect):
    x,y,w,h=rect; mx=0; bad=0; worst=None; n=0
    for yy in range(h):
        for xx in range(w):
            if 8<=xx<w-8 and 5<=yy<h-5: continue
            n+=1
            d=max(abs(p-q) for p,q in zip(ours.getpixel((x+xx,y+yy)),ref.getpixel((x+xx,y+yy))))
            if d>2: bad+=1
            if d>mx: mx=d; worst=(xx,yy,ours.getpixel((x+xx,y+yy)),ref.getpixel((x+xx,y+yy)))
    return mx,bad,n,worst
ours=Image.open(R+'windows/button.png').convert('RGB')
for i,r in rects.items():
    print('button',i,NAMES[i],r,'max %d bad(>2) %d of %d'%cmp(ours,ref,r)[:3],'worst',cmp(ours,ref,r)[3])
    sidebyside(ours,ref,r,OUT+'cmp_b4_%d.png'%i)
# the shift sheet: OK (default) and Cancel as Search for Card lays them out
cw2=253
ref=new_ref(3,3,cw2,ch)
rects={}
srcs={0:'dialog-search-rest',1:'button-pressed-search-cancel',2:'dialog-search-rest'}
for i in range(2):  # cell 2 (Cancel focused) has no crisp capture: Options' is the resampled ring
    im=Image.open(ST+srcs[i]+'@1x.png').convert('RGB').crop((84,216,242,238))
    ox,oy=origin(i%3,i//3,cw2,ch)
    ref.paste(im,(ox+6,oy+9))
    rects[i]=(ox+6,oy+9,158,22)
ref.save(R+'ref/windows/button_shift.png')
ours=Image.open(R+'windows/button_shift.png').convert('RGB')
for i,(x,y,w,h) in rects.items():
    for nm,(rx,rw) in (('OK',(0,73)),('Cancel',(84,73))):
        print('shift',i,nm,'max %d bad(>2) %d of %d'%cmp(ours,ref,(x+rx,y,rw,h))[:3],cmp(ours,ref,(x+rx,y,rw,h))[3])
    sidebyside(ours,ref,(x,y,w,h),OUT+'cmp_sh%d.png'%i,S=4)
# the kinds sheet: the old crops (picture + caption rest and disabled, picture alone disabled) plus the pressed New Rule
K={0:('view-conditional-formatting@1x.png',(18,84,125,25)),1:('view-conditional-formatting@1x.png',(280,84,125,25)),3:(st('button-pressed-conditional-formatting-new-rule'),(18,84,125,25)),7:('view-conditional-formatting@1x.png',(616,84,30,25))}
ref=new_ref(16,cols,cw,ch)
rects={}
for i,(src,(x,y,w,h)) in K.items():
    rects[i]=place(ref,i,cols,cw,ch,src,(x+1,y+1,w-2,h-1))
ref.save(R+'ref/windows/button_kinds.png')
ours=Image.open(R+'windows/button_kinds.png').convert('RGB')
for i,r in rects.items():
    print('kinds',i,r,'max %d bad(>2) %d of %d'%cmp(ours,ref,r)[:3],cmp(ours,ref,r)[3])
