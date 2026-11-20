* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

PROC FORMAT;
value _9lives 
     1 = "high" 
     2 = "low" 
     3 = "a b" 
;

DATA  rdata ;
LENGTH
 w_t $ 9
;

INFILE  "tests/oracle/data/wfs_5_0.csv" 
     DSD 
     LRECL= 41 ;
INPUT
 _9lives
 w_t
 Q2_score
 a_b
 TotalPopulation
;
LABEL  _9lives = "9lives" ;
LABEL  w_t = "w t" ;
LABEL  Q2_score = "Q2.score" ;
LABEL  a_b = "a.b" ;
FORMAT _9lives _9lives. ;
RUN;
