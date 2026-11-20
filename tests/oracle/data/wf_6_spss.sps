SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_6_spss.csv"  free (",")
ENCODING="UTF8"
/ 1st * score (A8) price$ (A11) 
  .

VARIABLE LABELS
1st "1st" 
 score "score" 
 price$ "price$" 
 .
VARIABLE LEVEL 1st 
 (scale).

EXECUTE.
