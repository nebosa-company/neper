* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

PROC FORMAT;
value my_var 
     1 = "z" 
     2 = "low" 
;

value evr_mrrd 
     1 = "z" 
     2 = "a b" 
;

value Q1_score 
     1 = "high" 
     2 = "z" 
;

value a_b 
     1 = "a b" 
     2 = "say "hi"" 
     3 = "low" 
;

value Region 
     1 = "x,y" 
     2 = "a b" 
     3 = "say "hi"" 
     4 = "high" 
;

DATA  rdata ;
LENGTH
 comment $ 12
 TtlPpltn $ 11
;

INFILE  "tests/oracle/data/wfs_14_1.csv" 
     DSD 
     LRECL= 72 ;
INPUT
 comment
 my_var
 Smkng_St
 evr_mrrd
 x_y
 Q1_score
 Q2_score
 TtlPpltn
 a_b
 tag_1
 Region
 QrtrlyRv
;
LABEL  my_var = "my var" ;
LABEL  Smkng_St = "Smoking Status" ;
LABEL  evr_mrrd = "ever_married" ;
LABEL  x_y = "x-y" ;
LABEL  Q1_score = "Q1.score" ;
LABEL  Q2_score = "Q2.score" ;
LABEL  TtlPpltn = "TotalPopulation" ;
LABEL  a_b = "a.b" ;
LABEL  tag_1 = "tag#1" ;
LABEL  QrtrlyRv = "QuarterlyRevenue" ;
FORMAT my_var my_var. ;
FORMAT evr_mrrd evr_mrrd. ;
FORMAT Q1_score Q1_score. ;
FORMAT a_b a_b. ;
FORMAT Region Region. ;
RUN;
