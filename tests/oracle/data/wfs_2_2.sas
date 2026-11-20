* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

PROC FORMAT;
value Smkng_St 
     1 = "high" 
     2 = "a b" 
     3 = "z" 
     4 = "x,y" 
;

libname ROutput 'C:/sas';
DATA ROutput.mydata;
LENGTH
 height $ 9
;

INFILE  "tests/oracle/data/wfs_2_2.csv" 
     DSD 
     LRECL= 25 ;
INPUT
 height
 Smoking_Status
 diastolic_blood_pressure
;
LABEL  Smoking_Status = "Smoking Status" ;
FORMAT Smoking_Status Smkng_St. ;
RUN;
