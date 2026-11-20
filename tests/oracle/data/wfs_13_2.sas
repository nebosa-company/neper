* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

PROC FORMAT;
value _1st 
     1 = "high" 
     2 = "x,y" 
     3 = "mid" 
     4 = "say "hi"" 
;

libname ROutput 'C:/sas';
DATA ROutput.mydata;
LENGTH
 ever_married $ 10
;

INFILE  "tests/oracle/data/wfs_13_2.csv" 
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
