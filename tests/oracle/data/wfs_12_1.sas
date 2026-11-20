* Written by R;
*  write.foreign(df, dfile, cfile, "SAS", validvarname = "V6") ;

DATA  rdata ;
INFILE  "tests/oracle/data/wfs_12_1.csv" 
     DSD 
     LRECL= 23 ;
INPUT
 age
 height
 income
 regin_cd
 QrtrlyRv
;
LABEL  regin_cd = "region_code" ;
LABEL  QrtrlyRv = "QuarterlyRevenue" ;
RUN;
