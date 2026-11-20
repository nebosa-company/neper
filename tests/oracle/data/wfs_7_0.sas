* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

PROC FORMAT;
value ag_t_f__ 
     1 = "high" 
     2 = "z" 
     3 = "low" 
;

value evr_mrrd 
     1 = "x,y" 
     2 = "low" 
     3 = "mid" 
     4 = "high" 
;

value my_var 
     1 = "high" 
     2 = "x,y" 
;

DATA  rdata ;
LENGTH
 income $ 11
;

INFILE  "tests/oracle/data/wfs_7_0.csv" 
     DSD 
     LRECL= 52 ;
INPUT
 age_at_first_hospital_admission
 group
 w_t
 ever_married
 measurement_alpha_one
 my_var
 systolic_blood_pressure
 income $ 
;
LABEL  w_t = "w t" ;
LABEL  my_var = "my var" ;
FORMAT age_at_first_hospital_admission ag_t_f__. ;
FORMAT ever_married evr_mrrd. ;
FORMAT my_var my_var. ;
RUN;
