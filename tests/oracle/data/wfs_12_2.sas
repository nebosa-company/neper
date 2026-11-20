* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", libpath = "C:/sas", dataname = "mydata") ;

libname ROutput 'C:/sas';
DATA ROutput.mydata;
INFILE  "tests/oracle/data/wfs_12_2.csv" 
     DSD 
     LRECL= 23 ;
INPUT
 age
 height
 income
 region_code
 QuarterlyRevenue
;
RUN;
