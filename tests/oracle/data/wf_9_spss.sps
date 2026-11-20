SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_9_spss.csv"  free (",")
ENCODING="UTF8"
/ score (A10) age flag * height (A11) income comment * group (A12) 
 e@mail (A12) 
  .

VARIABLE LABELS
score "score" 
 age "age" 
 flag "flag" 
 height "height" 
 income "income" 
 comment "comment" 
 group "group" 
 e@mail "e@mail" 
 .
VARIABLE LEVEL age, flag, income, comment 
 (scale).

EXECUTE.
