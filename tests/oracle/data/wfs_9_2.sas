* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

PROC FORMAT;
value city 
     1 = "high" 
     2 = "say "hi"" 
     3 = "mid" 
;

value my_var 
     1 = "low" 
     2 = "x,y" 
;

value _1st 
     1 = "mid" 
     2 = "high" 
     3 = "x,y" 
;

value TtlPpltn 
     1 = "z" 
     2 = "low" 
     3 = "high" 
;

value comment 
     1 = "x,y" 
     2 = "low" 
     3 = "mid" 
     4 = "high" 
;

libname ROutput 'C:/sas';
DATA ROutput.mydata;
LENGTH
 e_mail $ 10
 Q2_score $ 12
;

INFILE  "tests/oracle/data/wfs_9_2.csv" 
     DSD 
     LRECL= 55 ;
INPUT
 score
 number_of_children_under_18
 city
 my_var
 _1st
 w_t
 long_variable_name_number_one
 diastolic_blood_pressure
 e_mail
 TotalPopulation
 Q2_score
 comment
;
LABEL  my_var = "my var" ;
LABEL  _1st = "1st" ;
LABEL  w_t = "w t" ;
LABEL  e_mail = "e@mail" ;
LABEL  Q2_score = "Q2.score" ;
FORMAT city city. ;
FORMAT my_var my_var. ;
FORMAT _1st _1st. ;
FORMAT TotalPopulation TtlPpltn. ;
FORMAT comment comment. ;
RUN;
