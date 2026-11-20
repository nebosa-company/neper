* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

PROC FORMAT;
value my_var 
     1 = "mid" 
     2 = "z" 
;

value income 
     1 = "a b" 
     2 = "low" 
;

value nm____18 
     1 = "z" 
     2 = "low" 
     3 = "x,y" 
     4 = "a b" 
;

value Smkng_St 
     1 = "x,y" 
     2 = "low" 
;

value Region 
     1 = "low" 
     2 = "say "hi"" 
     3 = "z" 
;

DATA  rdata ;
LENGTH
 region_code $ 11
 year_of_birth_estimate_value_x $ 12
 measurement_alpha_one $ 10
 QuarterlyRevenue $ 12
;

INFILE  "tests/oracle/data/wfs_8_0.csv" 
     DSD 
     LRECL= 80 ;
INPUT
 my_var
 income
 region_code
 number_of_children_under_18
 Smoking_Status
 year_of_birth_estimate_value_x
 ever_married
 Region
 measurement_alpha_one
 city
 QuarterlyRevenue
 e_mail
;
LABEL  my_var = "my var" ;
LABEL  Smoking_Status = "Smoking Status" ;
LABEL  e_mail = "e@mail" ;
FORMAT my_var my_var. ;
FORMAT income income. ;
FORMAT number_of_children_under_18 nm____18. ;
FORMAT Smoking_Status Smkng_St. ;
FORMAT Region Region. ;
RUN;
