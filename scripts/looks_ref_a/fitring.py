import sys, json, numpy as np
from PIL import Image
sys.path.insert(0,'D:/Temp/lanes/looks9-w3/scripts/looks_ref_a')
from bspec import SPEC
R='D:/Temp/lanes/looks9-w3/docs/ui/looks/'
P=np.array([240,240,240.])
def hexc(v): return np.array([(v>>16)&255,(v>>8)&255,v&255],float)
KIND={'normal':(0xD0D0D0,0xBABABA,0xFDFDFD),'default':(0x0078D4,0x006CBD,0xFDFDFD),'hover':(0x0078D4,0x006CBD,0xE0EEF9),'pressed':(0x005499,0x005499,0xCCE4F7)}
def ov(lo,hi,a,b): return max(0.0,min(hi,b)-max(lo,a))
def pix(win,bands):
    # bands: list of (a,b,color or None for P) ; window win=(lo,lo+1)
    out=np.zeros(3);sp=0;tot=0
    for (a,b,c) in bands:
        o=ov(win[0],win[1],a,b)
        if c is None: sp+=o
        else: out+=o*c; tot+=o
    return out,tot,sp
EPS=0.00074
def top_rows(s,L,F,h,n=3):
    res=[]
    for r in range(n):
        bands=[(-9,1/3,None),(1/3,4/3,L),(4/3,99,F)]
        res.append(comp(pix((r-s,r-s+1),bands)))
    return res
def comp(t):
    out,tot,sp=t
    # composite over page P: alpha=1-sp
    return (out+sp*P)  # colour over page
def bot_rows(s,Lb,F,h,n=3):
    res=[]
    for r in range(h-n,h):
        bands=[(-9,h-5/3,F),(h-5/3,h-2/3,Lb),(h-2/3,99,None)]
        res.append(comp(pix((r-s,r-s+1),bands)))
    return res
def left_cols(s,L,F,n=3):
    return [comp(pix((c-s,c-s+1),[(-9,0,None),(0,1,L),(1,99,F)])) for c in range(n)]
def right_cols(s,L,F,w,n=3):
    return [comp(pix((c-s,c-s+1),[(-9,w-1,F),(w-1,w,L),(w,99,None)])) for c in range(w-n,w)]
def kind_of(stem,df):
    if stem.startswith('hover'): return 'hover'
    if 'pressed' in stem: return 'pressed'
    if 'focused' in stem: return 'default'
    return 'default' if df else 'normal'
def cells(sheet):
    sys.path.insert(0,'D:/Temp/lanes/looks9-w3/scripts/looks_ref_a')
    import lc
    rows=[r for r in SPEC if (r[7]=='H')==(sheet=='hover')]
    ref=np.array(Image.open(R+f'ref/windows/button_{sheet}.png').convert('RGB')).astype(float)
    m=5;cols,cw,ch=4,133,40
    out=[]
    for i,(stem,rest,t,x,y,w,h,d,df,en) in enumerate(rows):
        vw,vh=w-2,h-1
        hw=vw+2*m; hw+= 1 if hw%2==0 else 0
        hh=vh+2*m; hh+= 1 if hh%2==1 else 0
        ox,oy=lc.origin(i%cols,i//cols,cw,ch); px=ox+(cw-hw)//2; py=oy+(ch-hh)//2
        out.append((stem,df,vw,vh,px+m,py+m,ref,d))
    return out
if __name__=='__main__':
    sheet=sys.argv[1]
    res={}
    for (stem,df,w,h,bx,by,ref,d) in cells(sheet):
        if not any(k in stem for k in ('about','deck-legality','deck-properties','options')): continue
        k=kind_of(stem,df)
        L,Lb,F=[hexc(v) for v in KIND[k]]
        # observed: top rows at columns 10..w-11 median ; use rows 0,1
        cs=range(10,w-10)
        top=[np.median([ref[by+r,bx+c] for c in cs],axis=0) for r in range(2)]
        bot=[np.median([ref[by+h-2+r,bx+c] for c in cs],axis=0) for r in range(2)]
        rs=range(8,h-8)
        lef=[np.median([ref[by+r,bx+c] for r in rs],axis=0) for c in range(2)]
        rig=[np.median([ref[by+r,bx+w-2+c] for r in rs],axis=0) for c in range(2)]
        def fit(fn):
            best=None
            for s in np.arange(-0.05,1.0,0.001):
                e=fn(s)
                if best is None or e<best[0]: best=(e,s)
            return best[1]
        sy=fit(lambda s: sum(np.abs(a-b).sum() for a,b in zip(top_rows(s,L,F,h,2),top)))
        sy2=fit(lambda s: sum(np.abs(a-b).sum() for a,b in zip(bot_rows(s,Lb,F,h,3)[1:],bot)))
        sx=fit(lambda s: sum(np.abs(a-b).sum() for a,b in zip(left_cols(s,L,F,2),lef)))
        sx2=fit(lambda s: sum(np.abs(a-b).sum() for a,b in zip(right_cols(s,L,F,w,3)[1:],rig)))
        res[stem]=[round(float(sx),3),round(float(sy),3),round(float(sx2),3),round(float(sy2),3)]
        print('%-50s %-8s left %.3f top %.3f right %.3f bottom %.3f'%(stem,k,sx,sy,sx2,sy2))
    json.dump(res,open(f'D:/Temp/claude/looks9-w3/ringphases_{sheet}.json','w'))
