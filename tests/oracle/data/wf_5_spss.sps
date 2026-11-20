SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_5_spss.csv"  free (",")
ENCODING="UTF8"
/ long_variable_name_number_one (A12) flag (F8.0) comment (A8) 
  .

VARIABLE LABELS
long_variable_name_number_one "long_variable_name_number_one" 
 flag "flag" 
 comment "comment" 
 .

VALUE LABELS
/
flag 
1 "mid" 
 2 "a b" 
 3 "z" 
 4 "high" 
.

EXECUTE.
