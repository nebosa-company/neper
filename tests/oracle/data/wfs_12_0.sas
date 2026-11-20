* Written by R;
*  write.foreign(df, dfile, cfile, package = "SAS") ;

DATA  rdata ;
INFILE  "tests/oracle/data/wfs_12_0.csv" 
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
