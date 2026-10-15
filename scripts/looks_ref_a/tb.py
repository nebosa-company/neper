import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
cols,cw,ch=1,784,31
S={0:('search-search@1x.png',(8,0,309,31)),1:('help-about@1x.png',(8,0,436,31)),2:('deck-legality@1x.png',(8,0,539,31)),3:('options-01-interface@1x.png',(8,0,712,31)),4:('main-window-deck-mode@1x.png',(8,0,784,31))}
ref=new_ref(7,cols,cw,ch)
rects={}
for i,(src,r) in S.items(): rects[i]=place(ref,i,cols,cw,ch,src,r)
ref.save(R+'ref/windows/title_bar.png')
ours=Image.open(R+'windows/title_bar.png').convert('RGB')
print(ours.size,ref.size)
for i,r in rects.items():
    mx,bad,w=diff(ours,ref,r,ring=False)
    print(i,r,'max',mx,'bad',bad,w)
    sidebyside(ours,ref,r,OUT+'cmp_t%d.png'%i,S=2)
print('--- parts')
def part(i,x0,x1,y0=0,y1=31):
    x,y,w,h=rects[i]
    a=ours.crop((x+x0,y+y0,x+x1,y+y1)); b=ref.crop((x+x0,y+y0,x+x1,y+y1))
    mx=0
    for yy in range(a.height):
        for xx in range(a.width):
            mx=max(mx,max(abs(p-q) for p,q in zip(a.getpixel((xx,yy)),b.getpixel((xx,yy)))))
    return mx
for i,(x,y,w,h) in rects.items():
    print(i,'icon',part(i,8,28),'face strip',part(i,0,8),'rows 25-31',part(i,0,w,24,31),'buttons',part(i,w-140 if i in (2,4) else w-34,w))
