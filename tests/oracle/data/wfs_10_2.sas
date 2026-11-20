* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

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

libname ROutput 'C:/sas';
DATA ROutput.mydata;
LENGTH
 age_at_first_hospital_admission $ 11
 comment $ 10
;

INFILE  "tests/oracle/data/wfs_10_2.csv" 
     DSD 
     LRECL= 46 ;
INPUT
 age_at_first_hospital_admission
 Q1_score
 id
 systolic_blood_pressure
 Smoking_Status
 long_variable_name_number_one
 TotalPopulation
 comment $ 
;
LABEL  Q1_score = "Q1.score" ;
LABEL  Smoking_Status = "Smoking Status" ;
FORMAT Q1_score Q1_score. ;
FORMAT id id. ;
FORMAT Smoking_Status Smkng_St. ;
FORMAT long_variable_name_number_one lng_v___. ;
RUN;
