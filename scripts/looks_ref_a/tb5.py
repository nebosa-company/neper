# Round 5 group a: the title bar sheet with a cell for every captured window caption (dark active and inactive, the light
# DevExpress captions, the tool window). Builds docs/ui/looks/ref/windows/title_bar.png and prints per cell the largest
# per-channel error of the whole bar outside the title text, of the icon, of the buttons and the title ink box.
import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
ST=R+'ref/windows/states/'
cols,cw,ch=1,941,31
def st(n): return ST+n+'@1x.png'
# index: (source, width, kind: 0 dialog, 1 min disabled, 2 three, 3 light, 4 tool)
S=[(st('dialog-search-rest'),309,0),(D+'help-about@1x.png',436,0),(st('dialog-about-rest'),436,0),(D+'deck-legality@1x.png',539,1),(D+'options-01-interface@1x.png',712,0),(st('dialog-options-interface-rest'),712,0),
   (st('dialog-filter-rest'),692,2),(st('dialog-statistics-rest'),941,0),(st('dialog-deck-properties-rest'),348,0),(st('dialog-sort-rest'),351,0),(st('dialog-missing-set-cards-rest'),250,0),
   (st('dialog-advanced-filter-rest'),544,3),(st('dialog-conditional-formatting-rest'),684,3),(st('dialog-customization-rest'),164,4),(st('main-window-rest'),784,2),(st('dialog-chrome-inactive-caption-main'),784,2)]
NAMES=['search','about inactive','about','deck legality','options inactive','options','filter','statistics','deck props','sort','missing','advanced filter','cond formatting','customization','main','main inactive']
ref=new_ref(18,cols,cw,ch)
rects={}
for i,(src,w,k) in enumerate(S): rects[i]=place(ref,i,cols,cw,ch,src,(8,0,w,31))
ref.save(R+'ref/windows/title_bar.png')
ours=Image.open(R+'windows/title_bar.png').convert('RGB')
def maxd(a,b,box):
    x0,y0,x1,y1=box; mx=0; n=0
    for yy in range(y0,y1):
        for xx in range(x0,x1):
            d=max(abs(p-q) for p,q in zip(a.getpixel((xx,yy)),b.getpixel((xx,yy))))
            if d>2: n+=1
            mx=max(mx,d)
    return mx,n
def ink(im,x,y,x0,x1,bg,thr=60):
    xs=[];ys=[]
    for yy in range(31):
        for xx in range(x0,x1):
            if sum(abs(p-q) for p,q in zip(im.getpixel((x+xx,y+yy)),bg))>thr: xs.append(xx);ys.append(yy)
    return (min(xs),max(xs),min(ys),max(ys)) if xs else None
for i,(x,y,w,h) in rects.items():
    k=S[i][2]
    bw=33 if k in (0,3) else 46*3 if k==2 else 46*3
    if k==4: bw=30
    # outside the title text: everything but x in [28, w-bw]
    left=mx=0
    a=maxd(ours,ref,(x,y,x+28,y+31)); b=maxd(ours,ref,(x+w-bw,y,x+w,y+31)); c=maxd(ours,ref,(x+28,y+24,x+w-bw,y+31))
    ic=maxd(ours,ref,(x+10,y+7,x+26,y+23)) if k!=4 else (0,0)
    bg=ref.getpixel((x+w//2,y+3))
    print('%2d %-16s left %s right %s rows24-30 %s icon %s | ink ours %s ref %s'%(i,NAMES[i],a,b,c,ic,ink(ours,x,y,28 if k!=4 else 6,w-bw,ours.getpixel((x+w//2,y+3))),ink(ref,x,y,28 if k!=4 else 6,w-bw,bg)))
    sidebyside(ours,ref,(x,y,w,31),OUT+'cmp_tb5_%d.png'%i,S=2)
