* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

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
 systlc__ $ 9
;

INFILE  "tests/oracle/data/wfs_1_1.csv" 
     DSD 
     LRECL= 19 ;
INPUT
 a_b
 height
 systlc__ $ 
;
LABEL  a_b = "a.b" ;
LABEL  systlc__ = "systolic_blood_pressure" ;
FORMAT a_b a_b. ;
FORMAT height height. ;
RUN;
