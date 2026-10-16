# Generates the tables of examples/looks/button_states.e and button_hover.e from bspec.py (the capture list).
#   python -I scripts/looks_ref_a/genbs.py states|hover      then mkbs.py with the same argument
# The sub-pixel phases of the DPI-scaled forms come from phases.json (stem -> [dx, dy]), written by fitshift.py.
import sys,os,json
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
from bspec import SPEC
SHEET=sys.argv[1] if len(sys.argv)>1 else 'states'
bgs={'button-pressed-filter-all':0xF9F9F9,'button-focused-filter-invert':0xF9F9F9,'hover-button-filter-all':0xF9F9F9,'hover-button-filter-invert':0xF9F9F9}
cells=[]
for (stem,rest,t,x,y,w,h,d,df,en) in SPEC:
    if (d=='H')!=(SHEET=='hover'): continue
    glyph = (t in ('&Edit Rule...','&New Rule...',''))
    cells.append(dict(focused=('about-ok' in stem),stem=stem,rest=rest,text=t,x=x,y=y,w=w,h=h,d=d,df=df,en=en,bg=bgs.get(stem,0xF0F0F0),glyph=glyph))
if SHEET=='states':
    # extra cells: our own 75x32 and 125x40 (no capture): the ring at other sizes
    for (nm,t,w,h,d,df) in (('75x32 rest','Cancel',75,32,'N',0),('75x32 default','OK',75,32,'N',1),('75x32 focus','Cancel',75,32,'F',0),('75x32 pressed','OK',75,32,'P',1),('125x40 default','Apply',125,40,'N',1)):
        cells.append(dict(stem=nm,rest='',text=t,x=0,y=0,w=w,h=h,d=d,df=df,en=1,bg=0xF0F0F0,glyph=False))
N=len(cells)
PH={}
if os.path.exists(os.path.join(HERE,'phases.json')): PH=json.load(open(os.path.join(HERE,'phases.json')))
def arr(name,ty,vals):
    return 'fn %s() -> [%d]%s { ret [%d]%s{ %s } }'%(name,len(vals),ty,len(vals),ty,', '.join(vals))
def q(s): return '"'+s+'"'
caps=[]
for c in cells:
    s=c['stem'].replace('button-','').replace('dialog-','').replace('-rest',' rest').replace('conditional-formatting','cf').replace('deck-legality','dl').replace('deck-properties','dp').replace('options-','opt ').replace('missing-set-cards','msc').replace('advanced-filter','af').replace('-',' ')
    s=s.replace('password','pw').replace('shortcut','sc').replace('cardart','art').replace('statistics','stats').replace('hover ','hot ').replace('conditional','cond'); caps.append(s[:24])
def ph(c,k): return '%.2f'%PH.get(c['stem'],[0,0])[k]
open(os.path.join(HERE,'bs_tables.txt'),'w').write('\n'.join([
 arr('t_captions','str',[q(s) for s in caps]),
 arr('t_words','str',[q(c['text']) for c in cells]),
 arr('t_widths','f32',['%d.0'%c['w'] for c in cells]),
 arr('t_heights','f32',['%d.0'%c['h'] for c in cells]),
 arr('t_drives','u8',['%du8'%{'N':0,'P':1,'F':2,'H':3}[c['d']] for c in cells]),
 arr('t_defaults','bool',['true' if c['df'] else 'false' for c in cells]),
 arr('t_enabled','bool',['true' if c['en'] else 'false' for c in cells]),
 arr('t_faces','u32',['0x%06Xu32'%c['bg'] for c in cells]),
 arr('t_focused','bool',['true' if c.get('focused') else 'false' for c in cells]),
 arr('t_glyphs','bool',['true' if c['glyph'] else 'false' for c in cells]),
 arr('t_shift_x','f32',[ph(c,0) for c in cells]),
 arr('t_shift_y','f32',[ph(c,1) for c in cells]),
]))
print(N)
