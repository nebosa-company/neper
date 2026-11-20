* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

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

INFILE  "tests/oracle/data/wfs_2_1.csv" 
     DSD 
     LRECL= 25 ;
INPUT
 height
 Smkng_St
 dstlc_b_
;
LABEL  Smkng_St = "Smoking Status" ;
LABEL  dstlc_b_ = "diastolic_blood_pressure" ;
FORMAT Smkng_St Smkng_St. ;
RUN;
