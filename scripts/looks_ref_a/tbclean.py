# looks9: the toolbar reference crops (toolbar_button, toolbar_button_row, toolbar_button_hot) are 26 rows of the main window, and
# the last row (y = 109 of the grab) is the toolbar's own light edge line (#D2D2D2) only where nothing is below the bar: from x = 287
# of the crop on it is the top border (#8D9096) of the grid panel under it. That is not the toolbar, and no toolbar render can match
# it, so the foreign pixels are put back to the bar's own edge colour. Idempotent. Run from the repository root:
#   python -I scripts/looks_ref_a/tbclean.py
from PIL import Image
import numpy as np
R='docs/ui/looks/ref/windows/'
def clean(name,tops,w):
    im=np.array(Image.open(R+name+'.png').convert('RGB'))
    n=0
    for y in tops:
        row=im[y+25,:w] if False else im[y+25]
        bad=(row[:,0]==141)&(row[:,1]==144)&(row[:,2]==150)
        im[y+25][bad]=(210,210,210); n+=int(bad.sum())
    Image.fromarray(im).save(R+name+'.png')
    print(name,n,'pixels')
clean('toolbar_button',[0],447)
clean('toolbar_button_row',[0],657)
clean('toolbar_button_hot',[20+56*i for i in range(9)],657)
