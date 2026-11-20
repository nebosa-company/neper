* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

PROC FORMAT;
value city 
     1 = "high" 
     2 = "say "hi"" 
     3 = "mid" 
;

value my_var 
     1 = "low" 
     2 = "x,y" 
;

value _1st 
     1 = "mid" 
     2 = "high" 
     3 = "x,y" 
;

value TtlPpltn 
     1 = "z" 
     2 = "low" 
     3 = "high" 
;

value comment 
     1 = "x,y" 
     2 = "low" 
     3 = "mid" 
     4 = "high" 
;

DATA  rdata ;
LENGTH
 e_mail $ 10
 Q2_score $ 12
;

INFILE  "tests/oracle/data/wfs_9_1.csv" 
     DSD 
     LRECL= 55 ;
INPUT
 score
 nm____18
 city
 my_var
 _1st
 w_t
 lng_v___
 dstlc_b_
 e_mail
 TtlPpltn
 Q2_score
 comment
;
LABEL  nm____18 = "number_of_children_under_18" ;
LABEL  my_var = "my var" ;
LABEL  _1st = "1st" ;
LABEL  w_t = "w t" ;
LABEL  lng_v___ = "long_variable_name_number_one" ;
LABEL  dstlc_b_ = "diastolic_blood_pressure" ;
LABEL  e_mail = "e@mail" ;
LABEL  TtlPpltn = "TotalPopulation" ;
LABEL  Q2_score = "Q2.score" ;
FORMAT city city. ;
FORMAT my_var my_var. ;
FORMAT _1st _1st. ;
FORMAT TtlPpltn TtlPpltn. ;
FORMAT comment comment. ;
RUN;
