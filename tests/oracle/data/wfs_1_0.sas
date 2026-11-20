* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

PROC FORMAT;
value a_b 
     1 = "high" 
     2 = "x,y" 
     3 = "a b" 
;

value height 
     1 = "low" 
     2 = "z" 
     3 = "a b" 
     4 = "mid" 
;

DATA  rdata ;
LENGTH
 systolic_blood_pressure $ 9
;

INFILE  "tests/oracle/data/wfs_1_0.csv" 
     DSD 
     LRECL= 19 ;
INPUT
 a_b
 height
 systolic_blood_pressure $ 
;
LABEL  a_b = "a.b" ;
FORMAT a_b a_b. ;
FORMAT height height. ;
RUN;
