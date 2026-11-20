* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

PROC FORMAT;
value w_t 
     1 = "low" 
     2 = "z" 
     3 = "a b" 
     4 = "say "hi"" 
;

value income 
     1 = "z" 
     2 = "low" 
     3 = "mid" 
;

value a_b 
     1 = "high" 
     2 = "a b" 
;

value yr_f____ 
     1 = "say "hi"" 
     2 = "a b" 
;

value flag 
     1 = "say "hi"" 
     2 = "high" 
     3 = "mid" 
;

libname ROutput 'C:/sas';
DATA ROutput.mydata;
LENGTH
 id $ 11
 Q2_score $ 11
 TotalPopulation $ 12
 e_mail $ 11
;

INFILE  "tests/oracle/data/wfs_4_2.csv" 
     DSD 
     LRECL= 83 ;
INPUT
 my_var
 Q1_score
 w_t
 income
 QuarterlyRevenue
 a_b
 id
 Q2_score
 year_of_birth_estimate_value_x
 TotalPopulation
 flag
 e_mail $ 
;
LABEL  my_var = "my var" ;
LABEL  Q1_score = "Q1.score" ;
LABEL  w_t = "w t" ;
LABEL  a_b = "a.b" ;
LABEL  Q2_score = "Q2.score" ;
LABEL  e_mail = "e@mail" ;
FORMAT w_t w_t. ;
FORMAT income income. ;
FORMAT a_b a_b. ;
FORMAT year_of_birth_estimate_value_x yr_f____. ;
FORMAT flag flag. ;
RUN;
