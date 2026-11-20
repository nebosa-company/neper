SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_7_spss.csv"  free (",")
ENCODING="UTF8"
/ price$ (A12) a.b (F8.0) age (F8.0) tag#1 (F8.0) w.t (F8.0) e@mail * 
 group (F8.0) income 
  .

VARIABLE LABELS
price$ "price$" 
 a.b "a.b" 
 age "age" 
 tag#1 "tag#1" 
 w.t "w t" 
 e@mail "e@mail" 
 group "group" 
 income "income" 
 .

VALUE LABELS
/
a.b 
1 "say "hi"" 
 2 "mid" 
 3 "low" 
/
age 
1 "low" 
 2 "high" 
/
tag#1 
1 "mid" 
 2 "x,y" 
 3 "high" 
 4 "low" 
/
w.t 
1 "say "hi"" 
 2 "x,y" 
 3 "mid" 
/
group 
1 "mid" 
 2 "say "hi"" 
.
VARIABLE LEVEL age, tag#1, w.t 
 (ordinal).
VARIABLE LEVEL e@mail, income 
 (scale).

EXECUTE.
