SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_2_spss.csv"  free (",")
ENCODING="UTF8"
/ price$ (F8.0) comment age group * city (F8.0) 1st * 
 long_variable_name_number_one (F8.0) height (A11) 
  .

VARIABLE LABELS
price$ "price$" 
 comment "comment" 
 age "age" 
 group "group" 
 city "city" 
 1st "1st" 
 long_variable_name_number_one "long_variable_name_number_one" 
 height "height" 
 .

VALUE LABELS
/
price$ 
1 "a b" 
 2 "x,y" 
/
city 
1 "a b" 
 2 "say "hi"" 
/
long_variable_name_number_one 
1 "low" 
 2 "z" 
 3 "high" 
 4 "say "hi"" 
.
VARIABLE LEVEL price$, city 
 (ordinal).
VARIABLE LEVEL comment, age, group 
 (scale).

EXECUTE.
