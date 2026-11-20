SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_8_spss.csv"  free (",")
ENCODING="UTF8"
/ age (F8.0) group (A11) flag 
  .

VARIABLE LABELS
age "age" 
 group "group" 
 flag "flag" 
 .

VALUE LABELS
/
age 
1 "z" 
 2 "say "hi"" 
 3 "x,y" 
 4 "high" 
.

EXECUTE.
