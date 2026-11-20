* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

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

DATA  rdata ;
LENGTH
 id $ 11
 Q2_score $ 11
 TtlPpltn $ 12
 e_mail $ 11
;

INFILE  "tests/oracle/data/wfs_4_1.csv" 
     DSD 
     LRECL= 83 ;
INPUT
 my_var
 Q1_score
 w_t
 income
 QrtrlyRv
 a_b
 id
 Q2_score
 yr_f____
 TtlPpltn
 flag
 e_mail $ 
;
LABEL  my_var = "my var" ;
LABEL  Q1_score = "Q1.score" ;
LABEL  w_t = "w t" ;
LABEL  QrtrlyRv = "QuarterlyRevenue" ;
LABEL  a_b = "a.b" ;
LABEL  Q2_score = "Q2.score" ;
LABEL  yr_f____ = "year_of_birth_estimate_value_x" ;
LABEL  TtlPpltn = "TotalPopulation" ;
LABEL  e_mail = "e@mail" ;
FORMAT w_t w_t. ;
FORMAT income income. ;
FORMAT a_b a_b. ;
FORMAT yr_f____ yr_f____. ;
FORMAT flag flag. ;
RUN;
