import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
cols,cw,ch=4,133,40
# (cell, source, control rect x,y,w,h)
SPEC={0:('search-filter-top@1x.png',(532,455,75,23)),
 1:('search-search@1x.png',(83,215,75,23)),
 2:('search-filter-top@1x.png',(616,455,75,23)),
 3:('view-conditional-formatting@1x.png',(597,378,85,25)),
 8:('view-conditional-formatting@1x.png',(415,378,85,25)),
 9:('view-conditional-formatting@1x.png',(506,378,85,25))}
ref=new_ref(10,cols,cw,ch)
rects={}
for i,(src,(x,y,w,h)) in SPEC.items():
    rects[i]=place(ref,i,cols,cw,ch,src,(x+1,y+1,w-2,h-1))
ref.save(R+'ref/windows/button.png')
ours=Image.open(R+'windows/button.png').convert('RGB')
print(ours.size,ref.size)
for i,r in rects.items():
    print(i,r,'ring diff',diff(ours,ref,r),'ink',inkbox(ours,r),inkbox(ref,r))
    sidebyside(ours,ref,r,OUT+'cmp_btn%d.png'%i)
# kinds sheet
ref=new_ref(16,cols,cw,ch)
K={0:('view-conditional-formatting@1x.png',(18,84,125,25)),1:('view-conditional-formatting@1x.png',(280,84,125,25)),7:('view-conditional-formatting@1x.png',(616,84,30,25))}
rects={}
for i,(src,(x,y,w,h)) in K.items():
    rects[i]=place(ref,i,cols,cw,ch,src,(x+1,y+1,w-2,h-1))
ref.save(R+'ref/windows/button_kinds.png')
ours=Image.open(R+'windows/button_kinds.png').convert('RGB')
for i,r in rects.items():
    print('kinds',i,r,'ring diff',diff(ours,ref,r),'ink',inkbox(ours,r),inkbox(ref,r))
    sidebyside(ours,ref,r,OUT+'cmp_k%d.png'%i)
