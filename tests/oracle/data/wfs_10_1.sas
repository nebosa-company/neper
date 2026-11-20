* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

PROC FORMAT;
value Q1_score 
     1 = "x,y" 
     2 = "mid" 
;

value id 
     1 = "mid" 
     2 = "low" 
     3 = "say "hi"" 
     4 = "a b" 
;

value Smkng_St 
     1 = "say "hi"" 
     2 = "z" 
     3 = "a b" 
     4 = "mid" 
;

value lng_v___ 
     1 = "high" 
     2 = "a b" 
     3 = "low" 
;

DATA  rdata ;
LENGTH
 ag_t_f__ $ 11
 comment $ 10
;

INFILE  "tests/oracle/data/wfs_10_1.csv" 
     DSD 
     LRECL= 46 ;
INPUT
 ag_t_f__
 Q1_score
 id
 systlc__
 Smkng_St
 lng_v___
 TtlPpltn
 comment $ 
;
LABEL  ag_t_f__ = "age_at_first_hospital_admission" ;
LABEL  Q1_score = "Q1.score" ;
LABEL  systlc__ = "systolic_blood_pressure" ;
LABEL  Smkng_St = "Smoking Status" ;
LABEL  lng_v___ = "long_variable_name_number_one" ;
LABEL  TtlPpltn = "TotalPopulation" ;
FORMAT Q1_score Q1_score. ;
FORMAT id id. ;
FORMAT Smkng_St Smkng_St. ;
FORMAT lng_v___ lng_v___. ;
RUN;
