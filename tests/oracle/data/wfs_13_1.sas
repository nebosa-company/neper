* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

PROC FORMAT;
value _1st 
     1 = "high" 
     2 = "x,y" 
     3 = "mid" 
     4 = "say "hi"" 
;

DATA  rdata ;
LENGTH
 evr_mrrd $ 10
;

INFILE  "tests/oracle/data/wfs_13_1.csv" 
     DSD 
     LRECL= 27 ;
INPUT
 _1st
 a_b
 evr_mrrd $ 
;
LABEL  _1st = "1st" ;
LABEL  a_b = "a.b" ;
LABEL  evr_mrrd = "ever_married" ;
FORMAT _1st _1st. ;
RUN;
