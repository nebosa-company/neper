* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

PROC FORMAT;
value dstlc_b_ 
     1 = "mid" 
     2 = "say "hi"" 
     3 = "high" 
;

value city 
     1 = "a b" 
     2 = "z" 
;

value age 
     1 = "say "hi"" 
     2 = "a b" 
     3 = "z" 
     4 = "high" 
;

value x_y 
     1 = "a b" 
     2 = "high" 
     3 = "z" 
;

value flag 
     1 = "mid" 
     2 = "a b" 
     3 = "low" 
;

DATA  rdata ;
LENGTH
 annual_household_income_in_dllrs $ 12
;

INFILE  "tests/oracle/data/wfs_3_0.csv" 
     DSD 
     LRECL= 71 ;
INPUT
 Q1_score
 diastolic_blood_pressure
 score
 number_of_children_under_18
 city
 age
 e_mail
 x_y
 income
 annual_household_income_in_dllrs
 year_of_birth_estimate_value_x
 flag
;
LABEL  Q1_score = "Q1.score" ;
LABEL  e_mail = "e@mail" ;
LABEL  x_y = "x-y" ;
LABEL  annual_household_income_in_dllrs = "annual_household_income_in_dollars" ;
FORMAT diastolic_blood_pressure dstlc_b_. ;
FORMAT city city. ;
FORMAT age age. ;
FORMAT x_y x_y. ;
FORMAT flag flag. ;
RUN;
