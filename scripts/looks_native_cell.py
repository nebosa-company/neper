"""`python -I scripts/looks_native_cell.py <light|dark> <capture stem> <sheet> cx cy cw ch [rect] [search] [--dump]` (round 15): the capture's control rect `rect` of
ref/windows-native/controls.json against our sheet (docs/ui/looks/windows[-dark]/<sheet>.png), looks_strict13's metric (flat px of the reference off,
other px off, text zone apart). cx cy cw ch is the cell to search around; with ANCHOR=x,y in the environment the rect is placed at that sheet
position +-search px instead (a menu in a padded cell: ANCHOR=32,53). --dump writes the strip picture to nat.png beside the script."""
import sys,json
import os
HERE=os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0,HERE)
import numpy as np
from PIL import Image
import looks_strict13 as s13
N=os.path.join(HERE,'..','docs','ui','looks','ref','windows-native')+os.sep
th,stem,sheet=sys.argv[1:4]
cx,cy,cw,ch=[int(v) for v in sys.argv[4:8]]
rect=int(sys.argv[8]) if len(sys.argv)>8 else 0
search=int(sys.argv[9]) if len(sys.argv)>9 else 4
key='%s/%s@1x.png'%(th,stem)
cs=json.load(open(N+'controls.json'))[key]['controls']
r=cs[rect]
im=np.array(Image.open(N+key).convert('RGB')).astype(int)
ref=im[r['y']:r['y']+r['h'],r['x']:r['x']+r['w']]
d='windows-dark' if th=='dark' else 'windows'
sh=np.array(Image.open(os.path.join(HERE,'..','docs','ui','looks',d,sheet+'.png')).convert('RGB')).astype(int)
an=os.environ.get("ANCHOR")
px,py=s13.place(ref,sh,0,0,10,10,search,tuple(int(v) for v in an.split(",")) if an else None) if an else s13.place(ref,sh,cx,cy,cw,ch,search)
ours=sh[py:py+ref.shape[0],px:px+ref.shape[1]]
s13.row(stem,ref,ours,(px,py))
if '--dump' in sys.argv: s13.dump(ref,ours,os.path.join(HERE,'nat.png'))
