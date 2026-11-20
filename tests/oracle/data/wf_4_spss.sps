SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_4_spss.csv"  free (",")
ENCODING="UTF8"
/ city (F8.0) flag (F8.0) long_variable_name_number_one 
  .

VARIABLE LABELS
city "city" 
 flag "flag" 
 long_variable_name_number_one "long_variable_name_number_one" 
 .

VALUE LABELS
/
city 
1 "z" 
 2 "high" 
 3 "x,y" 
 4 "low" 
/
flag 
1 "x,y" 
 2 "z" 
 3 "high" 
 4 "mid" 
.
VARIABLE LEVEL flag 
 (ordinal).
VARIABLE LEVEL long_variable_name_number_one 
 (scale).

EXECUTE.
