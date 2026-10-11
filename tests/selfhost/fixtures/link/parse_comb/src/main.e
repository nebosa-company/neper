// `e.parse.comb` against parsy (scripts/comb_vectors.py): an arithmetic grammar (left-associative
// + - *, right-associative ^, unary minus, parentheses, spaces) and a key/value grammar are written
// both as parsy parsers and as Neper combinators; the vector table holds, for valid and corrupted
// inputs, the value (mod 2**64) or parsy's furthest-failure offset, and the events the combinators
// record are evaluated or rendered and compared. Unit checks pin each combinator's own contract.
use e.io
use e.mem
use e.os
use e.parse.comb as comb
use e.str

const NUM: u32 = 1u32
const ADD: u32 = 2u32
const MUL: u32 = 3u32
const POW: u32 = 4u32
const NEG: u32 = 5u32
const KEY: u32 = 11u32
const VNUM: u32 = 12u32
const VSTR: u32 = 13u32
const PAIR: u32 = 14u32

fn expr_cases() -> str {
    ret "~e:0\n ~e:1\n1~v:1\n1 ~v:1\n 1~v:1\n(1)~v:1\n((2))~v:2\n-3~v:18446744073709551613\n- 3~v:18446744073709551613\n--3~v:3\n2^3^2~v:512\n2 * 3 + 4~v:10\n2 + 3 * 4~v:14\n(2 + 3) * 4~v:20\n10 - 4 - 3~v:3\n2^~e:2\n1 +~e:3\n(1~e:2\n1)~e:1\n+1~e:0\n1 2~e:2\n0^0~v:1\n7^0~v:1\n3^-1~v:12297829382473034411\n(1+2)^2^2~v:81\n41~v:41\n59~v:59\n36+  (  (77)  ^ 4 )~v:35153077\n- 46~v:18446744073709551570\n33+  (  98)+  56~v:187\n71~v:71\n69~v:69\n23  +68*  -45-  (94)^  2+39  ^ 2  - 38*37~v:18446744073709539858\n((42 )  --63+  ( 79 ) )~v:184\n(-97)  + (63  +76- 55  +  20)~v:7\n80~v:80\n(  (40 * 30)+  5*  4 *28*51 )~v:29760\n5+  -26* 56~v:18446744073709550165\n(- (50))^3~v:18446744073709426616\n(98 *  50-85*87)  ^  5~v:18350060487764242241\n98  *  4  +- 33*(99)~v:18446744073709548741\n46 -(93 )  - 72  + 37  *( (14))~v:399\n95~v:95\n76~v:76\n72*(68)^ 1+ 56+(( 87  ) )~v:5039\n(  19)~v:19\n9+6~v:15\n-(46)+ ( (58)  )  +  (- 69-  52  + 58 )~v:18446744073709551565\n93 + - (50 *71)~v:18446744073709548159\n(9 )~v:9\n22--  12 *48* 27*39 - 11 *66- (  ( 2 )  )~v:605822\n2-  51+  - 87 + 61+53  -13* 27 - (84  +1)^2~v:18446744073709544018\n(  88)~v:88\n56~v:56\n77~v:77\n(  (  25 )  *  55+33+ -84*  40* 57)~v:18446744073709361504\n(  -((  53)) )~v:18446744073709551563\n84~v:84\n75~v:75\n(85+57*-  5  )+  41~v:18446744073709551457\n63*73~v:4599\n(35)^ 2~v:1225\n-  ((26- 72 ))~v:46\n-  (43)*74  *  64~v:18446744073709347968\n85  ^  2~v:7225\n( 69 )*  10-54  ^  0  -18 -  (  - 16 )~v:687\n93~v:93\n10 -  28~v:18446744073709551598\n((  75  )+  34*82)  ^  0~v:1\n25~v:25\n(  31)~v:31\n(54) ^ 3~v:157464\n57~v:57\n23~v:23\n64*-81~v:18446744073709546432\n26~v:26\n(  98--10 )*11+68  +71  + 55~v:1382\n17~v:17\n97~v:97\n(-(45)  )~v:18446744073709551571\n(26  --(71) )*11~v:1067\n84  +  4 * 54-(  50 *39  )~v:18446744073709549966\n(4 - - (39) *  18  * 20)~v:14044\n88~v:88\n(55)~v:55\n59~v:59\n(( 44+80*0))~v:44\n(  23)~v:23\n41-- (5-  69)~v:18446744073709551593\n94* 70~v:6580\n- 15~v:18446744073709551601\n-  (89+59)+(7) +  -  73  +  89~v:18446744073709551491\n(95  )~v:95\n(  ((  70))  ^  4 )~v:24010000\n75~v:75\n51- 39 -(  37)+  40 -  98* 5 - 59  *  42~v:18446744073709548663\n85~v:85\n(  82  )~v:82\n(91+ 32  ^2)  *(82+  43)+5-81  -  0~v:139299\n86  +92-(2)- 61~v:115\n34~v:34\n( 34-88  + (67)^4 * 77-  96)~v:1551636167\n5~v:5\n(  -  (52) - 93)~v:18446744073709551471\n( (  30))+ -(51)+22--(55)~v:56\n78*(  63 ) *44  -47~v:216169\n70~v:70\n90~v:90\n(-(85)  )- 97* ( 28  +46*-  (91) )~v:403241\n13+ 47  -  10  +  -  (2)-69 +  -  63~v:18446744073709551532\n(63)  ^  5 *(((52)) )~v:51606700236\n-  97~v:18446744073709551519\n95~v:95\n46~v:46\n(59  +(81)  +88)~v:228\n-(56  *4 - 15  *44)~v:436\n51 ^ 4*  -(26)~v:18446744073533656390\n(65  )~v:65\n41  *(86 )+(31  * 7  )  +  13-41 *  66  * 36~v:18446744073709457956\n-24~v:18446744073709551592\n10  - 6~v:4\n47+  -29  +83 *44+(  9) -14-(  66)~v:3599\n83-  73 -95+90 + 20  *  28~v:565\n48~v:48\n- 51~v:18446744073709551565\n(71 -  (66  )* 61+ 28-(77 )  )~v:18446744073709547612\n26~v:26\n11-(82-  (  60 ))~v:18446744073709551605\n12 ^ 5  + 70~v:248902\n79~v:79\n46^  1~v:46\n- (44)- -(79 +92)~v:127\n82- 78~v:4\n(72  +  98+  6+  54)^  0~v:1\n-(46+13-70 -16)~v:27\n53~v:53\n( 75-46-  -69)~v:98\n(58)* 83 *67  *  18+ 35~v:5805719\n(-  (85)+91  )~v:6\n(8)  ^ 1~v:8\n-  (82)~v:18446744073709551534\n91 ^1+  87~v:178\n-(72)~v:18446744073709551544\n87~v:87\n(  ( 30 )--(49))~v:79\n98~v:98\n-44~v:18446744073709551572\n65 *( 22 )*  53  *65* 48-(51  ) -- 14~v:236464763\n83~v:83\n29~v:29\n79~v:79\n47*-70- 5~v:18446744073709548321\n21 -  0~v:21\n24~v:24\n- (( 91 )  +41)~v:18446744073709551484\n20 *  91  +  77*  47  *32*  1  *41-  -  49~v:4749997\n95~v:95\n39 ^ 2~v:1521\n-(19*5)  +  31~v:18446744073709551552\n-80- 25~v:18446744073709551511\n95~v:95\n94~v:94\n- 0~v:0\n35~v:35\n(( 15  )) *(  - (78))~v:18446744073709550446\n-70~v:18446744073709551546\n87~v:87\n48+  (18^0  )~v:49\n-(4)+  80 - 88  -51  -1 - (49)*  44~v:18446744073709549396\n8~v:8\n71 *75~v:5325\n83~v:83\n37~v:37\n(( (  94  ) ))* 29~v:2726\n52 +89* 55^ 0*24  +  -  (39)~v:2149\n3~v:3\nz2~e:0\n1 90 )~e:2\n~e:0\n9)~e:1\n1~v:1\n(33~e:3\n(-75~e:4\n41~v:41\n~e:0\n93 *  31  + 29  + -(39)--  93  +  87-6~v:3047\n-422~v:18446744073709551194\n( -  83- (84 )  *  15  +  722-(80  ))~v:18446744073709550915\n42 ~v:42\n8- 47~v:18446744073709551577\n27 *(7)^)  *(54)^0~e:8\n~e:0\n75  ~v:75\n(63)  *74  --5(60)~e:14\n- 19- (42 )~v:18446744073709551555\n-71~v:18446744073709551545\n(( 13)-13+22  *7  ~e:18\n978~v:978\n(13 )3- (  (79) )~e:5\n(  )~e:3\n((  45 7)~e:7\n(-5  61-40+ 40+22+92)~e:5\n- (((71)  ^1~e:12\n-98- 98-(19)  ^4  + 18*  3~v:18446744073709421153\n~e:0\n~e:0\n5~v:5\n76~v:76\n(  (25^ 5)8^0)~e:10\n-(25  ~e:6\n648~v:648\n57 6 ^  1~e:3\n- 67+( 44)*  +41+ 33 * 31*  9-  54~e:13\n~e:0\n~e:0\n11~v:11\n115* 16  *39-(55) -(2)~v:71703\n-09~v:18446744073709551607\nx77 - 40 *-(42)~e:0\n~e:0\n(  0- 62  *(20))~v:18446744073709550376\n~e:0\n9~v:9\n99~v:99\n5*(-15  ) -  2~v:18446744073709551539\n(28*42* 9  ~e:11\n(255^1*-0+(24 )*  (( 52  ))  ^  1~e:33\n49 +  -(39)  - (  - 82  )~v:92\n( (85)^ 4  *  67)~v:3497441875\n32*41  *35 + 55 + 26- (24(  0 )~e:25\n~e:0\n6~v:6\n8~v:8\n77~v:77\n(7)^ 2~v:49\n01~v:1\n23 +48+15  ^2 *(98) +  1+83*  ( 45 ) )~e:37\n-  (65-  17 ~e:12\n-47  +9 -  76  * (7~e:19\n3+22~v:25\n(-24)^  3~v:18446744073709537792\n- 51+  (67 +86+)98)~e:15\n~e:0\n)1~e:0\n51-~e:3\n(-  (31)+44*  98 -(  53  +88))~v:4140\n4^5~v:1024\n( 85 )+  44-  7~v:122\n2~v:2\n(4) ^  3+ ((( 8#4 )  ))~e:15\n-(63)  +1 95~e:10\n49 * 41*86 -  58  *62 ~v:169178\n(  -(28)  )*53*  4~v:18446744073709545680\n~e:0\n1~v:1\n-(51)  (68 )+( 26* 2)~e:7\n(14  )+97+ 13  +- (76) * -((2))~v:276\n55* 29~v:1595\n-  (793~e:7\n~e:0\n445  -13  ^ 1  -11*58-29^ 1 -- (91)~v:18446744073709551472\n81  *91 +- 8~v:7363\n( ((95)  ^ 4  #)~e:14\n84 + 92  -14  *  24+33 + 2 41~e:27\n7~v:7\n( 13)  - 3+99  + 17*91~v:1656\n~e:0\n-(~e:2\n-3*~e:3\n2(9~e:1\n78( ^  4~e:2\n( (  445 )~e:10\n-104~v:18446744073709551512\n54~v:54\n13  + 76~v:89\n( ~e:2\n1~v:1\n~e:0\n(24*  (95 )^0~e:13\n8~v:8\n(z70  + 31*89)*72~e:1\n044~v:44\n79~v:79\n(54  *68-51* 9(-(65)  ))~e:14\n48  -(-(59) ~e:12\n82*(  2697 * -2  )~v:18446744073709109308\n-  ((9))~v:18446744073709551607\n- (13++)  - 7 ^4~e:6\n-(92 ))~e:6\n(  (907))~v:907\n- 12+51 *99 - 22  * 72 -  (  18)~v:3435\n(97 - 4*46)*( 2 )--(20)~v:18446744073709551462\n1+^1~e:2\n- ~e:2\n2~v:2\n- 16 *  77+( (47  +25  ))~v:18446744073709550456\n(61 -8* 18^4  )+  72~v:18446744073708711941\n-(( 7 4))~e:6\n(5~e:2\n( 71  -  (~e:10\n530~v:530\n4~v:4\n( (( 9~e:6\n178~v:178\n#  -98 *  13  )~e:0\n(28)+  -(45)1 +  47+-  57  -  14~e:12\n78  65-50 -(-(57) )  *18~e:4\n57-80-(-2  -14)~v:18446744073709551609\n76 *63-  18-( ( 80  )  ) +(10+  743+57 *24)~v:6811\n(~e:1\n97+  21 +- (97~e:14\n3~v:3\n~e:0\n^4~e:0\n((52)^#  3  )~e:6\n5~v:5\n260~v:260\n38- 7 11*87)--((  95))~e:6\n757~v:757\n8*3*-84~v:18446744073709549600\n)0~e:0\n48 *83~v:3984\n(82  -5(0-59-75  )  +(( 28) )~e:7\n(  ~e:3\n46  *  -  (99) *  (54  )  -14-  95 +  -(85)~v:18446744073709305506"
}

fn kv_cases() -> str {
    ret "[]~v:\n[ ]~v:\n[a=1]~v:K:a;N:1;P\n[a=1,b=\"x\"]~v:K:a;N:1;P|K:b;S:x;P\n[a=]~e:3\n[a=1,]~e:5\n[~e:1\na=1~e:0\n~e:0\n[a=1] x~e:6\n[a=\"open]~e:9\n[=1]~e:1\n[ kbae  =  \"\",kbfehc=  \"2\"  ]~v:K:kbae;S:;P|K:kbfehc;S:2;P\n[  kffegd = 4,kbaff=4096  ]~v:K:kffegd;N:4;P|K:kbaff;N:4096;P\n[ kccagd =\"\",  keb =  \"zz\" ]~v:K:kccagd;S:;P|K:keb;S:zz;P\n[ke  = \"\",  kd=\"\"  ]~v:K:ke;S:;P|K:kd;S:;P\n[ka  =\"z \"  ]~v:K:ka;S:z ;P\n[ke=\"zz\",  kcab_=  \"x x\",  kebdd=4864  ]~v:K:ke;S:zz;P|K:kcab_;S:x x;P|K:kebdd;N:4864;P\n[kfg  = 2605, kd = 4519  ]~v:K:kfg;N:2605;P|K:kd;N:4519;P\n[kh = 4961]~v:K:kh;N:4961;P\n[ kg_h=7803,ke_=  1498,k__=  \"xx2\",keacc=\"zy1\"  ]~v:K:kg_h;N:7803;P|K:ke_;N:1498;P|K:k__;S:xx2;P|K:keacc;S:zy1;P\n[ ]~v:\n[kbff  =3380,  kh_=  \"y\"]~v:K:kbff;N:3380;P|K:kh_;S:y;P\n[  kgd_ =  8858]~v:K:kgd_;N:8858;P\n[ ]~v:\n[kafhbf = 5776,kabef  =2334,khecd=  \" \"  ]~v:K:kafhbf;N:5776;P|K:kabef;N:2334;P|K:khecd;S: ;P\n[  kceb = 7213,kfa  = 7835,kgc =  4132,kgef  =\"x\"]~v:K:kceb;N:7213;P|K:kfa;N:7835;P|K:kgc;N:4132;P|K:kgef;S:x;P\n[ kadh = 5323, kdd  =\"\"  ]~v:K:kadh;N:5323;P|K:kdd;S:;P\n[ kdbedf =  \"x11y\",  ka_ab  =2087 ]~v:K:kdbedf;S:x11y;P|K:ka_ab;N:2087;P\n[ ]~v:\n[ kh_cg=\"\",kegcec  =1730,kbgf  =\"2y\" ]~v:K:kh_cg;S:;P|K:kegcec;N:1730;P|K:kbgf;S:2y;P\n[kbaa  =  \"2y x\", kfced =\"2\", khafe=6250, kb= \"\" ]~v:K:kbaa;S:2y x;P|K:kfced;S:2;P|K:khafe;N:6250;P|K:kb;S:;P\n[ ]~v:\n[khgdde=  \"yx2\"]~v:K:khgdde;S:yx2;P\n[  ]~v:\n[kd=\"  \",kdb =4427]~v:K:kd;S:  ;P|K:kdb;N:4427;P\n[kedb_g=  \"xz\" ]~v:K:kedb_g;S:xz;P\n[  ]~v:\n[keg= 8771, keaef  = \"yyy\"]~v:K:keg;N:8771;P|K:keaef;S:yyy;P\n[kbch =9235,khc  =2465,kba =  2402]~v:K:kbch;N:9235;P|K:khc;N:2465;P|K:kba;N:2402;P\n[ keb =\"y\",ka_d  =  7954]~v:K:keb;S:y;P|K:ka_d;N:7954;P\n[ ]~v:\n[  ]~v:\n[ kabef_= \" yxy\", kh=\"11  \", kfde  =7763, khbdcf =6627  ]~v:K:kabef_;S: yxy;P|K:kh;S:11  ;P|K:kfde;N:7763;P|K:khbdcf;N:6627;P\n[k_hfa=  1377, kb= \"x1z\", k_eecg  =\"zy \", kg = \"y \"]~v:K:k_hfa;N:1377;P|K:kb;S:x1z;P|K:k_eecg;S:zy ;P|K:kg;S:y ;P\n[  ]~v:\n[    ]~v:\n[  kafab=  \"1\",khhfce=  \"z\",kdgd_= 4143 ]~v:K:kafab;S:1;P|K:khhfce;S:z;P|K:kdgd_;N:4143;P\n[]~v:\n[  kh_hh = 2182]~v:K:kh_hh;N:2182;P\n[]~v:\n[kg  =\"y\", k_ab=8142]~v:K:kg;S:y;P|K:k_ab;N:8142;P\n[ kabff  = 9918,kff=  \"2x \"  ]~v:K:kabff;N:9918;P|K:kff;S:2x ;P\n[ ]~v:\n[ kcba = 9390,  ked= 9961,  kha_ =4864,  kcfe=\"121y\"]~v:K:kcba;N:9390;P|K:ked;N:9961;P|K:kha_;N:4864;P|K:kcfe;S:121y;P\n[]~v:\n[ka_fa_=\"\", kha =\" 1x1\"]~v:K:ka_fa_;S:;P|K:kha;S: 1x1;P\n[ kgbh=\"\"  ]~v:K:kgbh;S:;P\n[ k__a=2033,keae=\"11z1\",kdf  =1204,kge =4165 ]~v:K:k__a;N:2033;P|K:keae;S:11z1;P|K:kdf;N:1204;P|K:kge;N:4165;P\n[kd  =1920,k_ef =  \"y 1 \" ]~v:K:kd;N:1920;P|K:k_ef;S:y 1 ;P\n[khh=  6127, kaeee_=3678]~v:K:khh;N:6127;P|K:kaeee_;N:3678;P\n[  kf=\" \",keg_f=\"\"]~v:K:kf;S: ;P|K:keg_f;S:;P\n[keff =  \"yx\", kgffhg=4809 ]~v:K:keff;S:yx;P|K:kgffhg;N:4809;P\n[keaea =2171, k_=6926, kedh  =\"121\", khba  =  \"1zy\" ]~v:K:keaea;N:2171;P|K:k_;N:6926;P|K:kedh;S:121;P|K:khba;S:1zy;P\n[  kbhfhg= \"y22\",  kec=4908,  kacgf=\"z\"]~v:K:kbhfhg;S:y22;P|K:kec;N:4908;P|K:kacgf;S:z;P\n[ k_gbhe = \"y1\",khghc= 1522]~v:K:k_gbhe;S:y1;P|K:khghc;N:1522;P\n[  kbdgde  =  8539]~v:K:kbdgde;N:8539;P\n[kd_df= 4937,ke=  \"21\",kfc = \"\"]~v:K:kd_df;N:4937;P|K:ke;S:21;P|K:kfc;S:;P\n[ kaebeg= 1179, kd_bch =5778, kgabhb =\"z z\" ]~v:K:kaebeg;N:1179;P|K:kd_bch;N:5778;P|K:kgabhb;S:z z;P\n[ k_=3824,kfeaae =\"y\"  ]~v:K:k_;N:3824;P|K:kfeaae;S:y;P\n[ kddcf = 5354,keecag=  \"yy22\",kgbhd= 9935]~v:K:kddcf;N:5354;P|K:keecag;S:yy22;P|K:kgbhd;N:9935;P\n[kfcfh=7082]~v:K:kfcfh;N:7082;P\n[  kdag  = 4730]~v:K:kdag;N:4730;P\n[k_fe  =680]~v:K:k_fe;N:680;P\n[ kdb =  \"z\",k_g= \"xyy2\"  ]~v:K:kdb;S:z;P|K:k_g;S:xyy2;P\n[  kca_bh=  \"y\",khhgbf  =6776,k_aad = 8299,khh=\"y y\" ]~v:K:kca_bh;S:y;P|K:khhgbf;N:6776;P|K:k_aad;N:8299;P|K:khh;S:y y;P\n[ kafd=  \" 1xx\",kce_  = \"2x1y\"]~v:K:kafd;S: 1xx;P|K:kce_;S:2x1y;P\n[ka_e=\"z\",khdab  =  8840,k_hdc=1457]~v:K:ka_e;S:z;P|K:khdab;N:8840;P|K:k_hdc;N:1457;P\n[  kedhd =  7223,  kb =\"2y\",  kge= 1400,  khg_d_= 7522  ]~v:K:kedhd;N:7223;P|K:kb;S:2y;P|K:kge;N:1400;P|K:khg_d_;N:7522;P\n[ kd= 665]~v:K:kd;N:665;P\n[ kg=\"yyx\", k_a =  6303, k_g=  3876, ke =6687]~v:K:kg;S:yyx;P|K:k_a;N:6303;P|K:k_g;N:3876;P|K:ke;N:6687;P\n[kf=  9065 ]~v:K:kf;N:9065;P\n[ked_d  = 5077, kdfff= 2221, khcf= \"\"]~v:K:ked_d;N:5077;P|K:kdfff;N:2221;P|K:khcf;S:;P\n[kedede= \"21\", kageff=2888, kched=\"22\"]~v:K:kedede;S:21;P|K:kageff;N:2888;P|K:kched;S:22;P\n[kd  = 8042, kccba =\"2xy\"]~v:K:kd;N:8042;P|K:kccba;S:2xy;P\n[khhe =  5388,kafee = 7022,k_d=  6223,kad_=  9587  ]~v:K:khhe;N:5388;P|K:kafee;N:7022;P|K:k_d;N:6223;P|K:kad_;N:9587;P\n[  ke=\"z \", kc  =  3104, kabaeg =6918, ka =\" \"]~v:K:ke;S:z ;P|K:kc;N:3104;P|K:kabaeg;N:6918;P|K:ka;S: ;P\n[kba= 1352,kfeh =7339,kgc  = 5203]~v:K:kba;N:1352;P|K:kfeh;N:7339;P|K:kgc;N:5203;P\n[ kghhef=\"x11\", kca= \"\", kd  =6188]~v:K:kghhef;S:x11;P|K:kca;S:;P|K:kd;N:6188;P\n[    ]~v:\n[khhcgb  =  9918]~v:K:khhcgb;N:9918;P\n[kfcdda= 7109  ]~v:K:kfcdda;N:7109;P\n[  kdf = \"-\"  ]~v:K:kdf;S:-;P\n[~e:1\n[ 8]~e:2\n[  kg_=3759,  kbh_ah=7432,  kh~e:30\n[ k_de =905#]~e:11\n[k_  =\"zy\",  kh_ah  = \" ( z\",  kc_= \"zx\",  kh=\"\" ]~v:K:k_;S:zy;P|K:kh_ah;S: ( z;P|K:kc_;S:zx;P|K:kh;S:;P\n[khcd =\"z\",  ka_b= \"2 \",  ke_c=  9939,  ka_d=3538  ~e:51\n[ kb_f = 5426,kaade=  8807,k_cgd  =\"1\",he =184  ]~v:K:kb_f;N:5426;P|K:kaade;N:8807;P|K:k_cgd;S:1;P|K:he;N:184;P\n[kh_=\"zzz\",khhb=910,k_hhcf=\"\",kga~e:33\n[  ~e:3\n[  kbfd = 2778,ka_fg  =6297,kba=  \"\",ke__ge=5289  ~e:50\n[kddedg =\"\"]~v:K:kddedg;S:;P\n7[kgch  =  8133]~e:0\n[kf=\"zyyz\",  kf_hd= \" 1z\"]~v:K:kf;S:zyyz;P|K:kf_hd;S: 1z;P\n[kg_cc(=403,kebe_c =\"1\"  ]~e:6\n[ kc=\" \",ka__ =9305]~v:K:kc;S: ;P|K:ka__;N:9305;P\n[  k_bga_~e:9\n[  kda4=372]~v:K:kda4;N:372;P\n[kg = 3242,kcfbc = \"2\",kb_  =  \"y1x1,kcebaa=\" x\"  ]~e:46\n[ 1   ]~e:2\n[  ke = 7633,kafhdc=-8710]~e:20\n[ ( ka_f_h = 7679  ]~e:2\n[ kg~e:4\n[ kdegg=\"\" ]~v:K:kdegg;S:;P\n[  kegdhd  =\"\",kd_eh  =\"\",kbh)= 9319,kh=7734]~e:29\n kchg= \"yy1\", kh= 562]~e:1\n[ kd=4913,kef_ =\"1z z\",ke_gfe=\"1\",kfe= y2y2\"  ]~e:39\n[ kfbac=979,kde= \"2\"]~v:K:kfbac;N:979;P|K:kde;S:2;P\n[ kcgd=  107,khfb = 6336]~v:K:kcgd;N:107;P|K:khfb;N:6336;P\n  kfcca  =\"\",khfg_=\"z\",kgaf  =\"yzyy\",kd_ahe=  \"yz\"]~e:2\n[  khdga=7808, k_  = 6688, kdacc= \"z ]~e:38\n[  ~e:3\n  ]~e:2\n[kcc_=8175,kc~e:13\n[  k_f =\"\",  kbffhh=\"2\",  k_bh= 2170,  kgg_= 3 9269]~e:47\n[kaafdg  =  \"\",kfd1fah=  6346,kbd_h= \"\"]~v:K:kaafdg;S:;P|K:kfd1fah;N:6346;P|K:kbd_h;S:;P\n[   ]~v:\n[ kb=  8049, kcgagh = \"1zy\",  kccg=  \"\",  kbgdgb  =\"2x\"]~v:K:kb;N:8049;P|K:kcgagh;S:1zy;P|K:kccg;S:;P|K:kbgdgb;S:2x;P\n[k_a =~e:6\n[~e:1\n[ aecc=9022  ]~v:K:aecc;N:9022;P\n[4  ]~e:1\n[ke=9436,  kfg=5957]~v:K:ke;N:9436;P|K:kfg;N:5957;P\n[ ]~v:\n[0   ]~e:1\n[  +]~e:3\n[keehh  =\"\", kbc_g =+z2\", kgdd_g= 7515, kbfb=  \"1  \"]~e:20\n[  kdah= \"yyy\", kdec=  \"2xy\", kh_ =\"xz \", k_dd  =  \"0\"  ]~v:K:kdah;S:yyy;P|K:kdec;S:2xy;P|K:kh_;S:xz ;P|K:k_dd;S:0;P\n[) ]~e:1\n[ ~e:2\n[ kgahc =  \" 2yx\", kff =  \"1\", k_h  = y\", kh_=\"z\"]~e:38\n[  kdhc  =919~e:13\n[kfh= 6629,kf~e:13\n[~e:1\n[kd+agh=\"x z2\", kh_eg= 9011]~e:3\n[  kggbh=\" x\",  k_ee= 6413,  kdg =\"2z 1\",  k_d_b  =\"y2\" ~e:56\n[kc_e3fa= \" \"]~v:K:kc_e3fa;S: ;P\n-[ ]~e:0\n[k_agde=)44,kacf_  =\"\"]~e:8\n[ * ]~e:2\n[   ]~v:\n[kh_ga  =5570,kdd=\" 221\",kfd_da=5117]~v:K:kh_ga;N:5570;P|K:kdd;S: 221;P|K:kfd_da;N:5117;P\n[ 5]~e:2\n[ khc= *312, khbgh=8419]~e:7\n[]~v:\n[ kabh =\"\",  kbaac_  =8677]~v:K:kabh;S:;P|K:kbaac_;N:8677;P\n[ kha =5359, kaabc =587, kcbce =2528, kb=\"+2zz\" ]~v:K:kha;N:5359;P|K:kaabc;N:587;P|K:kcbce;N:2528;P|K:kb;S:+2zz;P\n[~e:1\n[ kgbba =559,  kfbfag=\"z\",  k_acg = \"xz\"]~v:K:kgbba;N:559;P|K:kfbfag;S:z;P|K:k_acg;S:xz;P\n[ k_gc=\"z2\", kedfaa  =  3~e:25\n[kec  =461,kaga=3309,kead=3306,keb  =\" yzx\"  ]~v:K:kec;N:461;P|K:kaga;N:3309;P|K:kead;N:3306;P|K:keb;S: yzx;P\n[k_d  = 9894,kfacad =5731,kfde~e:30\n[khdh  =\"-12\" ]~v:K:khdh;S:-12;P\n[   ]~v:\n[  kdgabb=\"]~e:12\n[  kc_bcg= 2031, kag  =122, kfa= \"22\", ke=3131]~v:K:kc_bcg;N:2031;P|K:kag;N:122;P|K:kfa;S:22;P|K:ke;N:3131;P\n[kd=  -x\"]~e:6\n[ kbb=\"xxz2\", kadca= \"12 \", kg =5020, ka_ =952~e:46\n[ kefbd=\"z *yy\",kgca  =7351,kfcc=8198,kggc= \"\"]~v:K:kefbd;S:z *yy;P|K:kgca;N:7351;P|K:kfcc;N:8198;P|K:kggc;S:;P\n[__ebf=7529  ]~e:1\n[ kdcef=\"zy\",kecccg  = 2496,kcac#c  =\"zz\" ]~e:32\n[  ~e:3\n[kga=  8958,kg= \"y\",kd4e= 8155,kbfahd= 213  ]~v:K:kga;N:8958;P|K:kg;S:y;P|K:kd4e;N:8155;P|K:kbfahd;N:213;P\n[(]~e:1\n[kec =22#0, kc=9573, keabdc  =  \"1x1\" ]~e:8\n[khbdh=\" y-y2\"  ]~v:K:khbdh;S: y-y2;P\n[  kea*_  = \"zx\", keg  =2433  ]~e:6\n[kg_h=\"x\", kgba)fc=  5501]~e:15\n[ kb_c =  6917]~v:K:kb_c;N:6917;P\n[ kc_g=  \" z1y\",kd_gb =\"\",kdb =~e:31\n[ dggbg= \"zy\",k_  =\"y2\" ]~v:K:dggbg;S:zy;P|K:k_;S:y2;P\n[ kbg=72 7]~e:9\n[kfhbe=- \"xyzy\",  kebacb =\"1zz\"]~e:7\n7[kh=\"2  y\"]~e:0\n[ kg=  \"2 2\" ]~v:K:kg;S:2 2;P\n[  kbf=2472,kda=  \"\",kghzbbb  =  \"y1z2\",kdgeb = 2458]~v:K:kbf;N:2472;P|K:kda;S:;P|K:kghzbbb;S:y1z2;P|K:kdgeb;N:2458;P\n[kchh 1=\"1xx\",kbfc_ =\"z1 \",kdfhg= \"\"  ]~e:6\n[k_f_de 9 = 8553,kh=  \"\",ka_g_d  = \"x\",kgdd =5421 ]~e:8\n[  khe  =\"y x \",  kgfd_=9500  ]~v:K:khe;S:y x ;P|K:kgfd_;N:9500;P\n[kef =\"2\",ke_  =7039,kfhda  \"zy21\",kfeg__ = \"z\" ]~e:28\n[ ked=  ~e:8\n[ke= \"z\",  khfe= +\"2  \"]~e:17\n[ khc_g  =\"y y\",(kdhd  =\"y2 z\"]~e:16\n[k_eab=\" z\",  kcb  =  187,  kh=  \"y6 \"]~v:K:k_eab;S: z;P|K:kcb;N:187;P|K:kh;S:y6 ;P\n[  ke =21709~e:12\n[k~e:2\n[ ka= \"y1 5\",kab  =  1798,kbc=  \"zz\",kg =6956 ]~v:K:ka;S:y1 5;P|K:kab;N:1798;P|K:kbc;S:zz;P|K:kg;N:6956;P\n[kg=235~e:7\n[]~v:\n[+]~e:1\n~e:0\n[~e:1\n[kh_fhh =\" \",  kaefhc  =5508,~e:29\n[ kha =3475,kddc= \"\",kfb  =~e:27\n[ ka~e:4\n[ k_ad=87,kdd=5758,khac=  \"yy1z\",kd =  \"\"]~v:K:k_ad;N:87;P|K:kdd;N:5758;P|K:khac;S:yy1z;P|K:kd;S:;P\n[k__d= 4221, kc_ead=\"x\", kb~e:27\n[kecg\" \",  k_ =\"\"]~e:5\n[~e:1\n[  k_=  \"1x3\", kdddc=  \"22y\", kbce= 2036, kah  =7125]~v:K:k_;S:1x3;P|K:kdddc;S:22y;P|K:kbce;N:2036;P|K:kah;N:7125;P"
}

fn is_digit(c: u8) -> bool { ret c >= 48u8 && c <= 57u8 }
fn is_space(c: u8) -> bool { ret c == 32u8 }
fn is_not_quote(c: u8) -> bool { ret c != 34u8 }
fn is_tail(c: u8) -> bool { ret (c >= 97u8 && c <= 122u8) || (c >= 48u8 && c <= 57u8) || c == 95u8 }

fn ws(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.take_while(cx, off, is_space)
    ret (n, good)
}

fn raw_lparen(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "(")
    ret (n, good)
}
fn raw_rparen(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, ")")
    ret (n, good)
}
fn raw_plus(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "+")
    ret (n, good)
}
fn raw_minus(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "-")
    ret (n, good)
}
fn raw_star(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "*")
    ret (n, good)
}
fn raw_caret(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "^")
    ret (n, good)
}

fn tok_lparen(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_lparen, ws)
    ret (n, good)
}
fn tok_rparen(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_rparen, ws)
    ret (n, good)
}
fn tok_plus(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_plus, ws)
    ret (n, good)
}
fn tok_minus(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_minus, ws)
    ret (n, good)
}
fn tok_star(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_star, ws)
    ret (n, good)
}
fn tok_caret(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_caret, ws)
    ret (n, good)
}

fn addsub(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.choice2(cx, off, tok_plus, tok_minus)
    ret (n, good)
}

fn digits(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.take_while1(cx, off, is_digit, "digit")
    ret (n, good)
}

fn number_node(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, NUM, digits)
    ret (n, good)
}

fn number(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, number_node, ws)
    ret (n, good)
}

fn paren(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.delimited(cx, off, tok_lparen, expr, tok_rparen)
    ret (n, good)
}

fn neg_body(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, tok_minus, atom)
    ret (n, good)
}

fn neg(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, NEG, neg_body)
    ret (n, good)
}

fn atom(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.choice3(cx, off, number, paren, neg)
    ret (n, good)
}

fn power(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.chainr1(cx, off, atom, tok_caret, POW)
    ret (n, good)
}

fn term(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.chainl1(cx, off, power, tok_star, MUL)
    ret (n, good)
}

fn expr(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.chainl1(cx, off, term, addsub, ADD)
    ret (n, good)
}

fn top(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, ws, expr)
    ret (n, good)
}

fn power_of(base: u64, exponent: u64) -> u64 {
    var result = 1u64
    var b = base
    var e = exponent
    while e > 0u64 {
        if (e & 1u64) == 1u64 { result = result *% b }
        b = b *% b
        e = e >> 1u64
    }
    ret result
}

// The value of the recorded events read as reverse Polish; `ok` false on a malformed stream.
fn evaluate(cx: *comb.Cx) -> (u64, bool) {
    var stack: [64]u64 = zero
    var depth = 0usize
    var i = 0usize
    while i < cx.count {
        let ev = cx.events[i]
        if ev.kind == NUM {
            let (v, e) = str.parse_u64(cx.src[ev.start..ev.end])
            if e != ok || depth >= 64usize { ret (0u64, false) }
            stack[depth] = v
            depth += 1usize
        } else if ev.kind == NEG {
            if depth < 1usize { ret (0u64, false) }
            stack[depth - 1usize] = 0u64 -% stack[depth - 1usize]
        } else {
            if depth < 2usize { ret (0u64, false) }
            let b = stack[depth - 1usize]
            let a = stack[depth - 2usize]
            depth -= 1usize
            var r = 0u64
            if ev.kind == MUL { r = a *% b }
            if ev.kind == POW { r = power_of(a, b) }
            if ev.kind == ADD {
                if cx.src[ev.start] == 43u8 { r = a +% b } else { r = a -% b }
            }
            stack[depth - 1usize] = r
        }
        i += 1usize
    }
    if depth != 1usize { ret (0u64, false) }
    ret (stack[0], true)
}

fn check_expr(a: *mem.Arena) -> i32 {
    var events: [256]comb.Event = zero
    var lines = str.lines(expr_cases())
    var n = 0i32
    var values = 0i32
    while true {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        if line.len == 0usize { continue }
        let (input, want, found) = str.split_once(line, "~")
        if !found { ret 10i32 }
        var cx = comb.context(input, events[0..])
        let (end, good) = comb.parse_all(&cx, top)
        let (b0, be) = str.builder(a, 64usize)
        if be != ok { ret 11i32 }
        var b = b0
        if good {
            let (v, valid) = evaluate(&cx)
            if !valid { ret 12i32 }
            if str.push(&b, "v:") != ok || str.push_u64(&b, v) != ok { ret 13i32 }
            values += 1i32
        } else {
            if str.push(&b, "e:") != ok || str.push_usize(&b, cx.furthest) != ok { ret 14i32 }
        }
        if !str.eq(str.done(&b), want) { ret 100i32 + n }
        n += 1i32
    }
    if n != 325i32 || values != 239i32 { ret 15i32 }
    ret 0i32
}

// ---- key/value grammar ----
fn raw_lbracket(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "[")
    ret (n, good)
}
fn raw_rbracket(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "]")
    ret (n, good)
}
fn raw_eq(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "=")
    ret (n, good)
}
fn raw_comma(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, ",")
    ret (n, good)
}
fn raw_quote(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "\"")
    ret (n, good)
}

fn tok_lbracket(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_lbracket, ws)
    ret (n, good)
}
fn tok_rbracket(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_rbracket, ws)
    ret (n, good)
}
fn tok_eq(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_eq, ws)
    ret (n, good)
}
fn tok_comma(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, raw_comma, ws)
    ret (n, good)
}

fn lower(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.byte_range(cx, off, 97u8, 122u8, "letter")
    ret (n, good)
}
fn tail(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.take_while(cx, off, is_tail)
    ret (n, good)
}
fn ident(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, lower, tail)
    ret (n, good)
}
fn key_node(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, KEY, ident)
    ret (n, good)
}
fn key_tok(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, key_node, ws)
    ret (n, good)
}
fn vnum_node(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, VNUM, digits)
    ret (n, good)
}
fn inner(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.take_while(cx, off, is_not_quote)
    ret (n, good)
}
fn vstr_inner(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, VSTR, inner)
    ret (n, good)
}
fn quoted(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.delimited(cx, off, raw_quote, vstr_inner, raw_quote)
    ret (n, good)
}
fn value(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.choice2(cx, off, vnum_node, quoted)
    ret (n, good)
}
fn value_tok(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, value, ws)
    ret (n, good)
}
fn pair_body(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq3(cx, off, key_tok, tok_eq, value_tok)
    ret (n, good)
}
fn pair(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, PAIR, pair_body)
    ret (n, good)
}
fn items(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.separated0(cx, off, pair, tok_comma)
    ret (n, good)
}
fn kv_open(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, ws, tok_lbracket)
    ret (n, good)
}
fn kv_top(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq3(cx, off, kv_open, items, tok_rbracket)
    ret (n, good)
}

fn summary(cx: *comb.Cx, b: *str.Builder) -> err {
    var pairs = 0usize
    var i = 0usize
    while i < cx.count {
        let ev = cx.events[i]
        let body = cx.src[ev.start..ev.end]
        if ev.kind == KEY {
            if pairs > 0usize { try str.push(b, "|") }
            try str.push(b, "K:")
            try str.push(b, body)
            try str.push(b, ";")
        } else if ev.kind == VNUM {
            try str.push(b, "N:")
            try str.push(b, body)
            try str.push(b, ";")
        } else if ev.kind == VSTR {
            try str.push(b, "S:")
            try str.push(b, body)
            try str.push(b, ";")
        } else {
            try str.push(b, "P")
            pairs += 1usize
        }
        i += 1usize
    }
    ret ok
}

fn check_kv(a: *mem.Arena) -> i32 {
    var events: [256]comb.Event = zero
    var lines = str.lines(kv_cases())
    var n = 0i32
    while true {
        let (line, more) = str.split_next(&lines)
        if !more { break }
        if line.len == 0usize { continue }
        let (input, want, found) = str.split_once(line, "~")
        if !found { ret 20i32 }
        var cx = comb.context(input, events[0..])
        let (end, good) = comb.parse_all(&cx, kv_top)
        let (b0, be) = str.builder(a, 256usize)
        if be != ok { ret 21i32 }
        var b = b0
        if good {
            if str.push(&b, "v:") != ok || summary(&cx, &b) != ok { ret 22i32 }
        } else {
            if str.push(&b, "e:") != ok || str.push_usize(&b, cx.furthest) != ok { ret 23i32 }
        }
        if !str.eq(str.done(&b), want) { ret 150i32 + n }
        n += 1i32
    }
    if n != 212i32 { ret 24i32 }
    ret 0i32
}

// ---- contracts of the individual combinators ----
fn p_a(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "a")
    ret (n, good)
}
fn p_b(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "b")
    ret (n, good)
}
fn p_ab(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, p_a, p_b)
    ret (n, good)
}
fn p_ab_node(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, 7u32, p_ab)
    ret (n, good)
}
fn p_ac_node(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.node(cx, off, 8u32, p_a)
    ret (n, good)
}
fn p_ac(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.seq2(cx, off, p_ac_node, p_c)
    ret (n, good)
}
fn p_c(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.lit(cx, off, "c")
    ret (n, good)
}
fn p_not_b(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.not(cx, off, p_b, "not b")
    ret (n, good)
}
fn p_peek_a(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.peek(cx, off, p_a)
    ret (n, good)
}
fn p_a_labelled(cx: *comb.Cx, off: usize) -> (usize, bool) {
    let (n, good) = comb.label(cx, off, p_a, "the letter a")
    ret (n, good)
}

fn contracts() -> i32 {
    var events: [3]comb.Event = zero
    var cx = comb.context("aab", events[0..])
    // lit, many0, many1, opt: counts and offsets.
    let (e1, g1) = comb.many0(&cx, 0usize, p_a)
    if !g1 || e1 != 2usize { ret 30i32 }
    let (e2, g2) = comb.many1(&cx, 2usize, p_a)
    if g2 || e2 != 2usize || cx.furthest != 2usize || !str.eq(cx.expected, "a") { ret 31i32 }
    let (e3, g3) = comb.opt(&cx, 2usize, p_a)
    if !g3 || e3 != 2usize { ret 32i32 }
    // count, peek, not.
    let (e4, g4) = comb.count(&cx, 0usize, p_a, 2usize)
    if !g4 || e4 != 2usize { ret 33i32 }
    let (e5, g5) = comb.count(&cx, 0usize, p_a, 3usize)
    if g5 || e5 != 0usize { ret 34i32 }
    let (e6, g6) = comb.peek(&cx, 0usize, p_a)
    if !g6 || e6 != 0usize { ret 35i32 }
    let (e7, g7) = comb.not(&cx, 0usize, p_b, "not b")
    if !g7 || e7 != 0usize { ret 36i32 }
    let (e8, g8) = comb.not(&cx, 2usize, p_b, "not b")
    if g8 || !str.eq(cx.expected, "a") || cx.furthest != 2usize { ret 37i32 }
    // choice, seq: a failed branch leaves no events; the furthest failure survives a later success.
    comb.reset(&cx)
    let (e9, g9) = comb.choice2(&cx, 0usize, p_ab_node, p_ac)
    if g9 || e9 != 0usize || cx.count != 0usize || cx.furthest != 1usize { ret 38i32 }
    var cy = comb.context("ac", events[0..])
    let (e10, g10) = comb.choice2(&cy, 0usize, p_ab_node, p_ac)
    if !g10 || e10 != 2usize || cy.count != 1usize || cy.events[0].kind != 8u32 { ret 39i32 }
    if cy.furthest != 1usize || !str.eq(cy.expected, "b") { ret 40i32 }
    // separated0 and separated1, with a trailing separator left unconsumed.
    var cz = comb.context("a,a,a,", events[0..])
    let (e11, g11) = comb.separated1(&cz, 0usize, p_a, raw_comma)
    if !g11 || e11 != 5usize { ret 41i32 }
    let (e12, g12) = comb.separated0(&cz, 1usize, p_b, raw_comma)
    if !g12 || e12 != 1usize { ret 42i32 }
    let (e13, g13) = comb.separated1(&cz, 1usize, p_b, raw_comma)
    if g13 || e13 != 1usize { ret 43i32 }
    // label: names a failure at the start.
    var cl = comb.context("x", events[0..])
    let (e14, g14) = p_a_labelled(&cl, 0usize)
    if g14 || !str.eq(cl.expected, "the letter a") || cl.furthest != 0usize { ret 44i32 }
    // The event buffer: a full buffer is a failure, not a trap, and the count is restored.
    var small: [1]comb.Event = zero
    var co = comb.context("aa", small[0..])
    let (e15, g15) = comb.many0(&co, 0usize, p_ac_node)
    if !g15 || e15 != 1usize || co.count != 1usize || !co.overflow { ret 45i32 }
    // take_while, byte_range, one_of, none_of, any_byte, eof.
    var cb = comb.context("ab9", events[0..])
    let (e16, g16) = comb.take_while1(&cb, 0usize, is_digit, "digit")
    if g16 || e16 != 0usize { ret 46i32 }
    let (e17, g17) = comb.one_of(&cb, 0usize, "xyab", "set")
    if !g17 || e17 != 1usize { ret 47i32 }
    let (e18, g18) = comb.none_of(&cb, 0usize, "a", "not a")
    if g18 { ret 48i32 }
    let (e19, g19) = comb.eof(&cb, 3usize)
    if !g19 || e19 != 3usize { ret 49i32 }
    let (e20, g20) = comb.any_byte(&cb, 3usize)
    if g20 { ret 50i32 }
    // line_col is one-based and counts bytes.
    let (line, col) = comb.line_col("ab\ncd\n\nx", 7usize)
    if line != 4usize || col != 1usize { ret 51i32 }
    let (line2, col2) = comb.line_col("ab\ncd", 4usize)
    if line2 != 2usize || col2 != 2usize { ret 52i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var code = check_expr(a)
    if code == 0i32 { code = check_kv(a) }
    if code == 0i32 { code = contracts() }
    if code != 0i32 { os.exit(code) }
    let e = io.print("parse comb ok")
    ret ok
}
