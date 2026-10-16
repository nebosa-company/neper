# Generates the tables of examples/looks/button_states.e from bspec.py (the capture list). python -I scripts/looks_ref_a/genbs.py
import sys,os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from bspec import SPEC
M=5
bgs={'button-pressed-filter-all':0xF9F9F9,'button-focused-filter-invert':0xF9F9F9}
cells=[]
for (stem,rest,t,x,y,w,h,d,df,en) in SPEC:
    glyph = (t=='&Edit Rule...')
    cells.append(dict(stem=stem,rest=rest,text=t,x=x,y=y,w=w,h=h,d=d,df=df,en=en,bg=bgs.get(stem,0xF0F0F0),glyph=glyph))
# extra cells: our own 75x32 (no capture): checks the ring at another height
for (nm,t,w,h,d,df) in (('75x32 rest','Cancel',75,32,'N',0),('75x32 default','OK',75,32,'N',1),('75x32 focus','Cancel',75,32,'F',0),('75x32 pressed','OK',75,32,'P',1),('125x40 default','Apply',125,40,'N',1)):
    cells.append(dict(stem=nm,rest='',text=t,x=0,y=0,w=w,h=h,d=d,df=df,en=1,bg=0xF0F0F0,glyph=False))
N=len(cells)
PH={}
PHF=os.path.join(os.path.dirname(os.path.abspath(__file__)),'phases.json')
if os.path.exists(PHF):
    import json
    PH=json.load(open(PHF))

def arr(name,ty,vals):
    return 'fn %s() -> [%d]%s { ret [%d]%s{ %s } }'%(name,len(vals),ty,len(vals),ty,', '.join(vals))
def q(s): return '"'+s+'"'
caps=[]
for c in cells:
    s=c['stem'].replace('button-','').replace('dialog-','').replace('-rest',' rest').replace('conditional-formatting','cf').replace('deck-legality','dl').replace('deck-properties','dp').replace('options-','opt ').replace('missing-set-cards','msc').replace('advanced-filter','af').replace('-',' ')
    s=s.replace('password','pw').replace('shortcut','sc').replace('cardart','art').replace('statistics','stats'); caps.append(s[:24])
open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'bs_tables.txt'),'w').write('\n'.join([
 arr('t_captions','str',[q(s) for s in caps]),
 arr('t_words','str',[q(c['text']) for c in cells]),
 arr('t_widths','f32',['%d.0'%c['w'] for c in cells]),
 arr('t_heights','f32',['%d.0'%c['h'] for c in cells]),
 arr('t_drives','u8',['%du8'%{'N':0,'P':1,'F':2,'H':3}[c['d']] for c in cells]),
 arr('t_defaults','bool',['true' if c['df'] else 'false' for c in cells]),
 arr('t_enabled','bool',['true' if c['en'] else 'false' for c in cells]),
 arr('t_faces','u32',['0x%06Xu32'%c['bg'] for c in cells]),
 arr('t_glyphs','bool',['true' if c['glyph'] else 'false' for c in cells]),
 arr('t_shift_x','f32',['%.2f'%PH.get(str(i),[0,0])[0] for i in range(N)]),
 arr('t_shift_y','f32',['%.2f'%PH.get(str(i),[0,0])[1] for i in range(N)]),
]))
print(N)
