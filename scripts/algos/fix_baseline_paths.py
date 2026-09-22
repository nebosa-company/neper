import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = s.replace('\\\\build\\\\wt-algos\\\\build\\\\', '\\\\build\\\\')
s = s.replace(' D:\\\\repos\\\\neper\\\\build\\\\wt-algos ', ' D:\\\\repos\\\\neper ')
s = s.replace('/build/wt-algos/build/', '/build/').replace(' /mnt/d/repos/neper/build/wt-algos ', ' /mnt/d/repos/neper ')
open(p, 'w', encoding='utf-8', newline='\n').write(s)
print(p, 'wt-algos left:', s.count('wt-algos'))
