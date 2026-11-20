* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

PROC FORMAT;
value Smkng_St 
     1 = "high" 
     2 = "a b" 
     3 = "z" 
     4 = "x,y" 
;

DATA  rdata ;
LENGTH
 height $ 9
;

INFILE  "tests/oracle/data/wfs_2_0.csv" 
     DSD 
     LRECL= 25 ;
INPUT
 height
 Smoking_Status
 diastolic_blood_pressure
;
LABEL  Smoking_Status = "Smoking Status" ;
FORMAT Smoking_Status Smkng_St. ;
RUN;
