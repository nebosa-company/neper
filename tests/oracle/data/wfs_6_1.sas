* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

PROC FORMAT;
value e_mail 
     1 = "mid" 
     2 = "a b" 
;

value x_y 
     1 = "z" 
     2 = "x,y" 
;

DATA  rdata ;
LENGTH
 _9lives $ 12
;

INFILE  "tests/oracle/data/wfs_6_1.csv" 
     DSD 
     LRECL= 30 ;
INPUT
 _9lives
 e_mail
 city
 x_y
 Q2_score
;
LABEL  _9lives = "9lives" ;
LABEL  e_mail = "e@mail" ;
LABEL  x_y = "x-y" ;
LABEL  Q2_score = "Q2.score" ;
FORMAT e_mail e_mail. ;
FORMAT x_y x_y. ;
RUN;
