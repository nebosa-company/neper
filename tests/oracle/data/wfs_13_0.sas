* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

PROC FORMAT;
value _1st 
     1 = "high" 
     2 = "x,y" 
     3 = "mid" 
     4 = "say "hi"" 
;

DATA  rdata ;
LENGTH
 ever_married $ 10
;

INFILE  "tests/oracle/data/wfs_13_0.csv" 
     DSD 
     LRECL= 27 ;
INPUT
 _1st
 a_b
 ever_married $ 
;
LABEL  _1st = "1st" ;
LABEL  a_b = "a.b" ;
FORMAT _1st _1st. ;
RUN;
