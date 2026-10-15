import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
cols,cw,ch=3,300,34
# cell: (src, rect)
S={0:('options-08-grids@1x.png',(224,73,91,17)),1:('search-search@1x.png',(20,47,91,17)),2:('deck-properties@1x.png',(56,34,291,20)),3:('deck-properties@1x.png',(56,55,291,17)),4:('deck-legality@1x.png',(103,451,270,17)),5:('help-about@1x.png',(19,63,202,30)),6:('help-about@1x.png',(19,89,202,22)),7:('help-about@1x.png',(16,271,205,17)),8:('help-about@1x.png',(19,294,202,17)),9:('reports-missing-set-cards@1x.png',(16,39,234,34))}
ref=new_ref(12,cols,cw,ch)
rects={}
for i,(src,r) in S.items():
    # the cell box is centred like the holder (holder is the control box)
    rects[i]=place(ref,i,cols,cw,ch,src,r)
ref.save(R+'ref/windows/label.png')
ours=Image.open(R+'windows/label.png').convert('RGB')
def ink(im,rect,thr=150):
    x,y,w,h=rect;bg=im.getpixel((x,y))
    xs=[];ys=[]
    for yy in range(h):
        for xx in range(w):
            if sum(abs(a-b) for a,b in zip(im.getpixel((x+xx,y+yy)),bg))>thr: xs.append(xx);ys.append(yy)
    return (min(xs),max(xs),min(ys),max(ys)) if xs else None
for i,r in rects.items():
    print(i,r,'ink ours',ink(ours,r),'ref',ink(ref,r))
    sidebyside(ours,ref,r,OUT+'cmp_l%d.png'%i,S=3)
