import sys,os,json; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
SPEC=[('search-search',325,257),('view-sort',367,347),('reports-missing-set-cards',266,503),('deck-properties',364,552),('help-about',452,372),('options-01-interface',728,494)]
def make(name,idx,cols,cw,ch):
    ref=new_ref(len(idx),cols,cw,ch)
    info=[]
    for c,k in enumerate(idx):
        n,w,h=SPEC[k]
        W,H=w-16,h-8
        r=place(ref,c,cols,cw,ch,n+'@1x.png',(8,0,W,H))
        info.append((n,r))
    ref.save(R+'ref/windows/%s.png'%name)
    return ref,info
def report(name,idx,cols,cw,ch):
    ref,info=make(name,idx,cols,cw,ch)
    ours=Image.open(R+'windows/%s.png'%name).convert('RGB')
    for n,(x,y,w,h) in info:
        d=json.load(open(D+n+'.controls.json'))
        mask=[]; keep=[]
        for c in d['controls']:
            if not c['visible']: continue
            rect=(c['x']-8,c['y'],c['w'],c['h'])
            if c['class'] in ('TcxButton','TcxLabel'): keep.append((c['class'],rect,c['text']))
            elif c['class'] not in ('TPanel',) and not c['class'].endswith('Form'): mask.append(rect)
        # remove mask of full-client panels/forms: treat any rect >60% of window as container (not a mask)
        def masked(xx,yy):
            for (mx,my,mw,mh) in mask:
                if mx<=xx<mx+mw and my<=yy<my+mh: return True
            for c,(mx,my,mw,mh),t in keep:
                if c=='TcxLabel' and mx-2<=xx<mx+mw+2 and my-2<=yy<my+mh+2: return True
                if c=='TcxButton' and mx-2<=xx<mx+mw+3 and my-2<=yy<my+mh+3: return True
            return False
        worst=0;bad=0;loc=None
        for yy in range(h):
            for xx in range(w):
                if yy<31 and xx>=28 and xx<w-34: continue   # title text
                if masked(xx,yy): continue
                dd=max(abs(p-q) for p,q in zip(ours.getpixel((x+xx,y+yy)),ref.getpixel((x+xx,y+yy))))
                if dd>2: bad+=1
                if dd>worst: worst=dd;loc=(xx,yy)
        print(n,'chrome+face diff max',worst,'pixels>2',bad,loc)
        for c,(mx,my,mw,mh),t in keep:
            if c=='TcxButton':
                r=diff(ours,ref,(x+mx+1,y+my+1,mw-2,mh-1),ring=True)
                print('   button',repr(t),r[:2],r[2])
        sidebyside(ours,ref,(x,y,min(w,420),min(h,40)),OUT+'cmp_d_%s_top.png'%n,S=2)
report('dialog',[0,1,2,3,4],3,440,548)
report('dialog_wide',[5],1,714,488)
def heat(name,idx,cols,cw,ch):
    ref,info=make(name,idx,cols,cw,ch)
    ours=Image.open(R+'windows/%s.png'%name).convert('RGB')
    for n,(x,y,w,h) in info:
        im=Image.new('RGB',(w*2+4,h),(255,0,255))
        im.paste(ref.crop((x,y,x+w,y+h)),(0,0))
        d=Image.new('RGB',(w,h),(0,0,0))
        for yy in range(h):
            for xx in range(w):
                dd=max(abs(p-q) for p,q in zip(ours.getpixel((x+xx,y+yy)),ref.getpixel((x+xx,y+yy))))
                d.putpixel((xx,yy),(min(255,dd*3),min(255,dd*3),0) if dd>2 else ours.getpixel((x+xx,y+yy)))
        im.paste(d,(w+4,0)); im.save(OUT+'heat_%s.png'%n)
heat('dialog',[0,1,2,3,4],3,440,548)
