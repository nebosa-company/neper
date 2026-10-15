# Reference composites and diffs for the looks sheets (group a). Run with python -I.
from PIL import Image
import os,tempfile
R=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','docs','ui','looks').replace(chr(92),'/')+'/'
D=R+'ref/windows/dialogs/'
M,SP,CAP=12,10,16
def origin(col,row,cw,ch):
    return (M+col*(cw+SP), M+row*(CAP+4+ch+SP)+CAP+4)
def sheet_size(n,cols,cw,ch):
    rows=(n+cols-1)//cols
    return (M*2+cols*cw+(cols-1)*SP, M*2+rows*(CAP+4+ch+SP)-SP)
def new_ref(n,cols,cw,ch,bg=(240,240,240)):
    return Image.new('RGB',sheet_size(n,cols,cw,ch),bg)
def place(ref,i,cols,cw,ch,src,crop,box=None):
    """crop=(x,y,w,h) of the source image; centred in cell i. returns top-left in sheet."""
    im=Image.open(D+src if not os.path.isabs(src) else src).convert('RGB')
    c=im.crop((crop[0],crop[1],crop[0]+crop[2],crop[1]+crop[3]))
    ox,oy=origin(i%cols,i//cols,cw,ch)
    x=ox+(cw-c.width)//2; y=oy+(ch-c.height)//2
    ref.paste(c,(x,y))
    return x,y,c.width,c.height
def diff(ours,ref,rect,ring=True):
    x,y,w,h=rect
    a=ours.crop((x,y,x+w,y+h)).convert('RGB'); b=ref.crop((x,y,x+w,y+h)).convert('RGB')
    mx=0;bad=0;worst=None
    for yy in range(h):
        for xx in range(w):
            if ring and 3<=xx<w-3 and 3<=yy<h-3: continue
            d=max(abs(p-q) for p,q in zip(a.getpixel((xx,yy)),b.getpixel((xx,yy))))
            if d>2: bad+=1
            if d>mx: mx=d;worst=(xx,yy,a.getpixel((xx,yy)),b.getpixel((xx,yy)))
    return mx,bad,worst
def inkbox(im,rect,thr=60):
    x,y,w,h=rect; im=im.convert('RGB')
    xs=[];ys=[]
    for yy in range(4,h-4):
        for xx in range(4,w-4):
            p=im.getpixel((x+xx,y+yy))
            if min(p)<200-thr+60 and min(p)<190: xs.append(xx);ys.append(yy)
    return (min(xs),max(xs),min(ys),max(ys)) if xs else None
def sidebyside(ours,ref,rect,path,S=4):
    x,y,w,h=rect
    a=ours.crop((x-2,y-2,x+w+2,y+h+2)).resize(((w+4)*S,(h+4)*S),Image.NEAREST)
    b=ref.crop((x-2,y-2,x+w+2,y+h+2)).resize(((w+4)*S,(h+4)*S),Image.NEAREST)
    o=Image.new('RGB',(a.width,a.height*2+4),(255,0,255)); o.paste(b,(0,0)); o.paste(a,(0,a.height+4)); o.save(path)

OUT=os.environ.get('LOOKS_TMP',tempfile.gettempdir()).replace(chr(92),'/')+'/looks_a_'
