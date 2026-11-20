* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

PROC FORMAT;
value height 
     1 = "low" 
     2 = "x,y" 
;

value Q2_score 
     1 = "x,y" 
     2 = "z" 
     3 = "a b" 
     4 = "say "hi"" 
;

value x_y 
     1 = "low" 
     2 = "a b" 
;

DATA  rdata ;
LENGTH
 flag $ 11
 msrmnt__ $ 12
;

INFILE  "tests/oracle/data/wfs_11_1.csv" 
     DSD 
     LRECL= 44 ;
INPUT
 height
 Q2_score
 age
 regin_cd
 x_y
 flag
 msrmnt__
 lng_v___
;
LABEL  Q2_score = "Q2.score" ;
LABEL  regin_cd = "region_code" ;
LABEL  x_y = "x-y" ;
LABEL  msrmnt__ = "measurement_alpha_two" ;
LABEL  lng_v___ = "long_variable_name_number_one" ;
FORMAT height height. ;
FORMAT Q2_score Q2_score. ;
FORMAT x_y x_y. ;
RUN;
