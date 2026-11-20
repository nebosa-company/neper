SET DECIMAL=DOT.

DATA LIST FILE= "tests/oracle/data/wf_3_spss.csv"  free (",")
ENCODING="UTF8"
/ age (A10) e@mail * id (A12) comment (A8) score 1st tag#1 x.y 
 long_variable_name_number_one * price$ (A12) my.var (A9) income * 
 height (A8) a.b (A12) 
  .

VARIABLE LABELS
age "age" 
 e@mail "e@mail" 
 id "id" 
 comment "comment" 
 score "score" 
 1st "1st" 
 tag#1 "tag#1" 
 x.y "x-y" 
 long_variable_name_number_one "long_variable_name_number_one" 
 price$ "price$" 
 my.var "my var" 
 income "income" 
 height "height" 
 a.b "a.b" 
 .
VARIABLE LEVEL e@mail, score, 1st, tag#1, x.y, long_variable_name_number_one, income 
 (scale).

EXECUTE.
