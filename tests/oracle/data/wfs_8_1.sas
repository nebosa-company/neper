* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

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
 regin_cd $ 11
 yr_f____ $ 12
 msrmnt__ $ 10
 QrtrlyRv $ 12
;

INFILE  "tests/oracle/data/wfs_8_1.csv" 
     DSD 
     LRECL= 80 ;
INPUT
 my_var
 income
 regin_cd
 nm____18
 Smkng_St
 yr_f____
 evr_mrrd
 Region
 msrmnt__
 city
 QrtrlyRv
 e_mail
;
LABEL  my_var = "my var" ;
LABEL  regin_cd = "region_code" ;
LABEL  nm____18 = "number_of_children_under_18" ;
LABEL  Smkng_St = "Smoking Status" ;
LABEL  yr_f____ = "year_of_birth_estimate_value_x" ;
LABEL  evr_mrrd = "ever_married" ;
LABEL  msrmnt__ = "measurement_alpha_one" ;
LABEL  QrtrlyRv = "QuarterlyRevenue" ;
LABEL  e_mail = "e@mail" ;
FORMAT my_var my_var. ;
FORMAT income income. ;
FORMAT nm____18 nm____18. ;
FORMAT Smkng_St Smkng_St. ;
FORMAT Region Region. ;
RUN;
