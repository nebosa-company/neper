SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_10_spss.csv"  free (",")
ENCODING="UTF8"
/ e@mail height id x.y long_variable_name_number_one 
  .

VARIABLE LABELS
e@mail "e@mail" 
 height "height" 
 id "id" 
 x.y "x-y" 
 long_variable_name_number_one "long_variable_name_number_one" 
 .
VARIABLE LEVEL e@mail, height, id, x.y, long_variable_name_number_one 
 (scale).

EXECUTE.
