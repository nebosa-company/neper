# looks5: derives the alpha byte of the outer ring rows and corner cells of winbutton.e (the share of ring over the dialog
# face) from the same ring captured on the #F0F0F0 and the #F9F9F9 faces. Reads the pre-looks5 tables from
# `git show a7c5ee694:lib/e/ui/winbutton.e` saved as winbutton_head.e next to this file; writes newtabs.txt (the new tables).
import re,sys,os
HERE=os.path.dirname(os.path.abspath(__file__))
from PIL import Image
S=os.path.join(HERE,'..','..','docs','ui','looks','ref','windows')+'/'
src=open(os.path.join(HERE,'winbutton_head.e'),encoding='utf-8').read()
def tab(name,n):
    m=re.search(r'fn '+name+r'\(\) -> \[%d\]u32 \{ ret \[%d\]u32\{ (.*?) \} \}'%(n,n),src)
    return [int(x.strip().replace('u32','').replace('0x',''),16) if x.strip()!='0u32' else 0 for x in m.group(1).split(',')]
def img(f): return Image.open(S+f).convert('RGB')
# (kind, corners name, edges name, F0 image/rect, F9 image/rect)
P={
 'normal':('ring_normal_corners','ring_normal_edges',('states/dialog-filter-rest@1x.png',(104,455,75,23)),('states/dialog-filter-rest@1x.png',(109,413,75,23))),
 'default':('ring_default_corners','ring_default_edges',('states/button-focused-conditional-formatting-apply@1x.png',(415,378,85,25)),('states/button-focused-filter-invert@1x.png',(195,413,75,23))),
 'pressed':('ring_pressed_corners','ring_pressed_edges',('states/button-pressed-search-cancel@1x.png',(167,215,75,23)),('states/button-pressed-filter-all@1x.png',(28,413,75,23))),
}
import os
if not os.path.exists(S+'states/dialog-filter-rest@1x.png'):
    print('no dialogs/dialog-filter-rest; ls',os.listdir(S+'dialogs')[:5])
def px(im,rect,fx,fy,corner,k):
    x,y,w,h=rect; vx,vy,vw,vh=x+1,y+1,w-2,h-1
    cx,cy=k%6,k//6
    ox=0 if corner in (0,2) else vw-6
    oy=0 if corner in (0,1) else vh-6
    return im.getpixel((vx+ox+cx,vy+oy+cy))
out={}
for name,(cn,en,a0,a9) in P.items():
    corners=tab(cn,144); edges=tab(en,8)
    i0=img(a0[0]); i9=img(a9[0]); r0=a0[1]; r9=a9[1]
    newc=[]
    stats=[]
    for c in range(4):
        for k in range(36):
            cx,cy=k%6,k//6
            # distance classes: dots only in x>=3 and y>=3 of the cell as drawn (for TL); mirror for other corners
            ex=cx if c in (0,2) else 5-cx
            ey=cy if c in (0,1) else 5-cy
            base=corners[c*36+k]
            if ex>=2 and ey>=2:
                newc.append(0xFF000000|(base&0xFFFFFF) if base else 0); continue
            o0=px(i0,r0,0,0,c,k); o9=px(i9,r9,0,0,c,k)
            if name!='normal':
                pass
            LN={'normal':(0xD0,0xD0,0xD0),'default':(0x00,0x78,0xD4),'pressed':(0x00,0x54,0x99)}[name]
            if all(o0[j]<=240 for j in range(3)) and 0<max(240-o0[j] for j in range(3))<=8:
                a=sum((240-o0[j])/(240-LN[j]) for j in range(3))/3
                a=max(0.0,min(1.0,a))
                newc.append((int(round(a*255))<<24)|(LN[0]<<16)|(LN[1]<<8)|LN[2]); continue
            best=None
            for ai in range(1,256):
                a=ai/255.0
                kk=[max(0,min(255,int(round((o0[j]-(1-a)*240)/a)))) for j in range(3)]
                err=sum(abs(((1-a)*249+a*kk[j])-o9[j])+abs(((1-a)*240+a*kk[j])-o0[j]) for j in range(3))
                if best is None or err<best[0]-1e-9: best=(err,ai,kk)
            if best[1]<10:
                newc.append(0); continue
            a=best[1]/255.0; kk=best[2]
            al=int(round(a*255))
            newc.append((al<<24)|(kk[0]<<16)|(kk[1]<<8)|kk[2])
    # edges: top0 (0), bottom0 (3) are over the bg; use the mid column
    nb=list(edges)
    for idx,row in ((0,0),(3,'last')):
        x,y,w,h=r0; x9,y9,w9,h9=r9
        vy0=y+1; vy9=y9+1
        yy0=vy0 if row==0 else vy0+h-1-1
        yy9=vy9 if row==0 else vy9+h9-1-1
        p0=i0.getpixel((x+1+30,yy0)); p9=i9.getpixel((x9+1+30,yy9))
        a=sum(1-(p9[j]-p0[j])/9.0 for j in range(3))/3
        a=max(0.0,min(1.0,a))
        kk=[max(0,min(255,int(round((p0[j]-(1-a)*240)/a)))) for j in range(3)]
        nb[idx]=(int(round(a*255))<<24)|(kk[0]<<16)|(kk[1]<<8)|kk[2]
        print(name,'edge',idx,'p0',p0,'p9',p9,'alpha %.3f'%a,'K','%02X%02X%02X'%tuple(kk))
    out[name]=(cn,en,newc,nb)
def fmt(v): return '0u32' if v==0 else '0x%08Xu32'%v
res=[]
for name,(cn,en,newc,nb) in out.items():
    res.append('fn %s() -> [144]u32 { ret [144]u32{ %s } }'%(cn,', '.join(fmt(v) for v in newc)))
    res.append('// top0 top1 bottom1 bottom0 left0 left1 right1 right0; the top byte is the share of the colour over the dialog face (the outer rows blend with the face)')
    res.append('fn %s() -> [8]u32 { ret [8]u32{ %s } }'%(en,', '.join(fmt(v) for v in nb)))
open(os.path.join(HERE,'newtabs.txt'),'w').write('\n'.join(res))
