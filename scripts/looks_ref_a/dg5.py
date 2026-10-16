# Round 5 group a: the dialog sheets (dialog, dialog_wide, dialog_more, dialog_more2, dialog_more3) against every captured
# dialog window. Builds the reference sheets docs/ui/looks/ref/windows/<sheet>.png from the live rest grabs and prints per
# window the largest per-channel error of (chrome) the caption outside the title text, (face) the dialog face outside every
# child window, and (buttons) each button's ring (outside its caption). Other controls' windows are masked: their sheets
# are theirs. Run with python -I from the repository root after rendering.
import sys,os,json; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from lc import *
ST=R+'ref/windows/states/'
def st(n): return ST+n+'@1x.png'
# sheet: (name, columns, cell_w, cell_h, [(label, source png, controls json)])
SHEETS=[
 ('dialog',3,440,548,[('Search',st('dialog-search-rest'),'dialog-search-rest'),('Sort',D+'view-sort@1x.png','view-sort'),('Missing',D+'reports-missing-set-cards@1x.png','reports-missing-set-cards'),('Deck Props',D+'deck-properties@1x.png','deck-properties'),('About (inactive)',D+'help-about@1x.png','help-about'),('About',st('dialog-about-rest'),'dialog-about-rest')]),
 ('dialog_wide',1,714,488,[('Options (inactive)',D+'options-01-interface@1x.png','options-01-interface'),('Options',st('dialog-options-interface-rest'),'dialog-options-interface-rest')]),
 ('dialog_more',1,692,485,[('Filter',st('dialog-filter-rest'),'dialog-filter-rest'),('Advanced Filter',st('dialog-advanced-filter-rest'),'dialog-advanced-filter-rest'),('Cond. Formatting',st('dialog-conditional-formatting-rest'),'dialog-conditional-formatting-rest')]),
 ('dialog_more2',1,539,480,[('Deck Legality',st('dialog-deck-legality-rest'),'dialog-deck-legality-rest'),('Customization',st('dialog-customization-rest'),'dialog-customization-rest')]),
 ('dialog_more3',1,941,501,[('Statistics',st('dialog-statistics-rest'),'dialog-statistics-rest')]),
]
def load_json(n):
    p=(ST+n+'.controls.json') if os.path.exists(ST+n+'.controls.json') else D+n+'.controls.json'
    return json.load(open(p))
tot={}
# the windows whose last row is the #F5F5F5 line (one row taller than the others)
BOTTOM=('Deck Props','About (inactive)','About','Options (inactive)','Options','Deck Legality','Customization')
for name,cols,cw,ch,cells in SHEETS:
    ref=new_ref(len(cells),cols,cw,ch)
    info=[]
    for c,(label,src,js) in enumerate(cells):
        im=Image.open(src).convert('RGB'); W,H=im.width-16,im.height-8+(1 if label in BOTTOM else 0)
        r=place(ref,c,cols,cw,ch,src,(8,0,W,H)); info.append((label,js,r))
    ref.save(R+'ref/windows/%s.png'%name)
    ours=Image.open(R+'windows/%s.png'%name).convert('RGB')
    for label,js,(x,y,w,h) in info:
        d=load_json(js)
        masks=[];btn=[];lab=[]
        tool=label=='Customization'
        btnw=138 if label in ('Filter','Deck Legality') else 33
        for c in d['controls']:
            if not c['visible']: continue
            rect=(c['x']-8,c['y'],c['w'],c['h'])
            if c['class']=='TcxButton': btn.append((c['text'],rect,c.get('enabled',True)))
            elif c['class']=='TcxLabel': lab.append(rect)
            elif not (c['class'].endswith('Form') and c['w']>=d['width']-20): masks.append(rect)
        def inside(xx,yy,rs,pad=0):
            for (mx,my,mw,mh) in rs:
                if mx-pad<=xx<mx+mw+pad and my-pad<=yy<my+mh+pad: return True
            return False
        brects=[r for _,r,_ in btn]
        ch_mx=ch_bad=fc_mx=fc_bad=0
        fb=[]
        for yy in range(h):
            for xx in range(w):
                a=ours.getpixel((x+xx,y+yy)); b=ref.getpixel((x+xx,y+yy))
                dd=max(abs(p-q) for p,q in zip(a,b))
                if yy<31:
                    if tool: 
                        if 6<=xx<w-30: continue
                    elif 28<=xx<w-btnw: continue
                    ch_mx=max(ch_mx,dd); ch_bad+=dd>2
                else:
                    if inside(xx,yy,masks,3) or inside(xx,yy,lab,2) or inside(xx,yy,brects,5): continue
                    fc_mx=max(fc_mx,dd); fc_bad+=dd>2
                    if dd>2: fb.append((xx,yy))
        line='%-18s chrome max %3d bad %3d | face max %3d bad %4d'%(label,ch_mx,ch_bad,fc_mx,fc_bad)
        bm=0;bb=0
        for t,(mx,my,mw,mh),en in btn:
            if not t: continue
            rx,ry,rw,rh=x+mx+1,y+my+1,mw-2,mh-1
            m=n=0
            for yy in range(rh):
                for xx in range(rw):
                    if 8<=xx<rw-8 and 5<=yy<rh-5: continue
                    dd=max(abs(p-q) for p,q in zip(ours.getpixel((rx+xx,ry+yy)),ref.getpixel((rx+xx,ry+yy))))
                    m=max(m,dd); n+=dd>2
            bm=max(bm,m); bb+=n
        if fb: print('      face bad box x %d..%d y %d..%d'%(min(p[0] for p in fb),max(p[0] for p in fb),min(p[1] for p in fb),max(p[1] for p in fb)))
        print(line+' | buttons %d: max %3d bad %d'%(len([1 for t,_,_ in btn if t]),bm,bb))
        sidebyside(ours,ref,(x,y,min(w,420),min(h,40)),OUT+'cmp_d5_%s.png'%label.replace(' ','_'),S=2)
