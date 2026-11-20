* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

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

INFILE  "tests/oracle/data/wfs_7_1.csv" 
     DSD 
     LRECL= 52 ;
INPUT
 ag_t_f__
 group
 w_t
 evr_mrrd
 msrmnt__
 my_var
 systlc__
 income $ 
;
LABEL  ag_t_f__ = "age_at_first_hospital_admission" ;
LABEL  w_t = "w t" ;
LABEL  evr_mrrd = "ever_married" ;
LABEL  msrmnt__ = "measurement_alpha_one" ;
LABEL  my_var = "my var" ;
LABEL  systlc__ = "systolic_blood_pressure" ;
FORMAT ag_t_f__ ag_t_f__. ;
FORMAT evr_mrrd evr_mrrd. ;
FORMAT my_var my_var. ;
RUN;
