* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

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

libname ROutput 'C:/sas';
DATA ROutput.mydata;
LENGTH
 comment $ 12
 TotalPopulation $ 11
;

INFILE  "tests/oracle/data/wfs_14_2.csv" 
     DSD 
     LRECL= 72 ;
INPUT
 comment
 my_var
 Smoking_Status
 ever_married
 x_y
 Q1_score
 Q2_score
 TotalPopulation
 a_b
 tag_1
 Region
 QuarterlyRevenue
;
LABEL  my_var = "my var" ;
LABEL  Smoking_Status = "Smoking Status" ;
LABEL  x_y = "x-y" ;
LABEL  Q1_score = "Q1.score" ;
LABEL  Q2_score = "Q2.score" ;
LABEL  a_b = "a.b" ;
LABEL  tag_1 = "tag#1" ;
FORMAT my_var my_var. ;
FORMAT ever_married evr_mrrd. ;
FORMAT Q1_score Q1_score. ;
FORMAT a_b a_b. ;
FORMAT Region Region. ;
RUN;
