SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_1_spss.csv"  free (",")
ENCODING="UTF8"
/ comment (A12) city (F8.0) flag (F8.0) 1st * x.y (F8.0) group income * 
 height (F8.0) score id * price$ (F8.0) long_variable_name_number_one 
 (F8.0) 
  .

VARIABLE LABELS
comment "comment" 
 city "city" 
 flag "flag" 
 1st "1st" 
 x.y "x-y" 
 group "group" 
 income "income" 
 height "height" 
 score "score" 
 id "id" 
 price$ "price$" 
 long_variable_name_number_one "long_variable_name_number_one" 
 .

VALUE LABELS
/
city 
1 "x,y" 
 2 "mid" 
 3 "z" 
/
flag 
1 "z" 
 2 "high" 
 3 "say "hi"" 
 4 "mid" 
/
x.y 
1 "mid" 
 2 "x,y" 
 3 "z" 
/
height 
1 "say "hi"" 
 2 "a b" 
 3 "x,y" 
 4 "low" 
/
price$ 
1 "a b" 
 2 "low" 
/
long_variable_name_number_one 
1 "low" 
 2 "a b" 
 3 "high" 
 4 "mid" 
.
VARIABLE LEVEL flag 
 (ordinal).
VARIABLE LEVEL 1st, group, income, score, id 
 (scale).

EXECUTE.
