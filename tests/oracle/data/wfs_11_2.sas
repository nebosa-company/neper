* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

PROC FORMAT;
value height 
     1 = "low" 
     2 = "x,y" 
;

value Q2_score 
     1 = "x,y" 
     2 = "z" 
     3 = "a b" 
     4 = "say "hi"" 
;

value x_y 
     1 = "low" 
     2 = "a b" 
;

libname ROutput 'C:/sas';
DATA ROutput.mydata;
LENGTH
 flag $ 11
 measurement_alpha_two $ 12
;

INFILE  "tests/oracle/data/wfs_11_2.csv" 
     DSD 
     LRECL= 44 ;
INPUT
 height
 Q2_score
 age
 region_code
 x_y
 flag
 measurement_alpha_two
 long_variable_name_number_one
;
LABEL  Q2_score = "Q2.score" ;
LABEL  x_y = "x-y" ;
FORMAT height height. ;
FORMAT Q2_score Q2_score. ;
FORMAT x_y x_y. ;
RUN;
