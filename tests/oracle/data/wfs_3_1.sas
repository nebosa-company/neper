* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

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
 annl____ $ 12
;

INFILE  "tests/oracle/data/wfs_3_1.csv" 
     DSD 
     LRECL= 71 ;
INPUT
 Q1_score
 dstlc_b_
 score
 nm____18
 city
 age
 e_mail
 x_y
 income
 annl____
 yr_f____
 flag
;
LABEL  Q1_score = "Q1.score" ;
LABEL  dstlc_b_ = "diastolic_blood_pressure" ;
LABEL  nm____18 = "number_of_children_under_18" ;
LABEL  e_mail = "e@mail" ;
LABEL  x_y = "x-y" ;
LABEL  annl____ = "annual_household_income_in_dollars" ;
LABEL  yr_f____ = "year_of_birth_estimate_value_x" ;
FORMAT dstlc_b_ dstlc_b_. ;
FORMAT city city. ;
FORMAT age age. ;
FORMAT x_y x_y. ;
FORMAT flag flag. ;
RUN;
