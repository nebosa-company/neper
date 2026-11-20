// Chebyshev coefficient tables of gsl 2.7.1 (specfunc/bessel_olver.c), generated from its source by a script, with gsl's cheb_eval_e and cheb_eval_mode_e.
// cheb_eval(id, order, a, b, x) returns (value, error): error = eps * sum |terms| + |c[order]|; cheb_eval_mode(id, order, order_sp, a, b, x, mode) is the mode form: error = eps |value| + |c[order used]|.

use e.math

fn tid_bessel_olver_zofmzeta_a() -> usize { ret 0usize }
fn tord_bessel_olver_zofmzeta_a() -> usize { ret 19usize }
fn tsp_bessel_olver_zofmzeta_a() -> usize { ret 8usize }
fn ta_bessel_olver_zofmzeta_a() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_zofmzeta_a() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_zofmzeta_b() -> usize { ret 1usize }
fn tord_bessel_olver_zofmzeta_b() -> usize { ret 29usize }
fn tsp_bessel_olver_zofmzeta_b() -> usize { ret 15usize }
fn ta_bessel_olver_zofmzeta_b() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_zofmzeta_b() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_zofmzeta_c() -> usize { ret 2usize }
fn tord_bessel_olver_zofmzeta_c() -> usize { ret 10usize }
fn tsp_bessel_olver_zofmzeta_c() -> usize { ret 6usize }
fn ta_bessel_olver_zofmzeta_c() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_zofmzeta_c() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_A3_gt1() -> usize { ret 3usize }
fn tord_bessel_olver_A3_gt1() -> usize { ret 30usize }
fn tsp_bessel_olver_A3_gt1() -> usize { ret 17usize }
fn ta_bessel_olver_A3_gt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_A3_gt1() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_A4_gt1() -> usize { ret 4usize }
fn tord_bessel_olver_A4_gt1() -> usize { ret 17usize }
fn tsp_bessel_olver_A4_gt1() -> usize { ret 17usize }
fn ta_bessel_olver_A4_gt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_A4_gt1() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_B2_gt1() -> usize { ret 5usize }
fn tord_bessel_olver_B2_gt1() -> usize { ret 39usize }
fn tsp_bessel_olver_B2_gt1() -> usize { ret 30usize }
fn ta_bessel_olver_B2_gt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_B2_gt1() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_B3_gt1() -> usize { ret 6usize }
fn tord_bessel_olver_B3_gt1() -> usize { ret 29usize }
fn tsp_bessel_olver_B3_gt1() -> usize { ret 29usize }
fn ta_bessel_olver_B3_gt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_B3_gt1() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_B2_lt1() -> usize { ret 7usize }
fn tord_bessel_olver_B2_lt1() -> usize { ret 39usize }
fn tsp_bessel_olver_B2_lt1() -> usize { ret 39usize }
fn ta_bessel_olver_B2_lt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_B2_lt1() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_B3_lt1() -> usize { ret 8usize }
fn tord_bessel_olver_B3_lt1() -> usize { ret 39usize }
fn tsp_bessel_olver_B3_lt1() -> usize { ret 39usize }
fn ta_bessel_olver_B3_lt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_B3_lt1() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_A3_lt1() -> usize { ret 9usize }
fn tord_bessel_olver_A3_lt1() -> usize { ret 39usize }
fn tsp_bessel_olver_A3_lt1() -> usize { ret 39usize }
fn ta_bessel_olver_A3_lt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_A3_lt1() -> f64 { ret 1.0f64 }
fn tid_bessel_olver_A4_lt1() -> usize { ret 10usize }
fn tord_bessel_olver_A4_lt1() -> usize { ret 29usize }
fn tsp_bessel_olver_A4_lt1() -> usize { ret 29usize }
fn ta_bessel_olver_A4_lt1() -> f64 { ret -1.0f64 }
fn tb_bessel_olver_A4_lt1() -> f64 { ret 1.0f64 }

fn ctab(id: usize, k: usize) -> f64 {
    if id == 0usize {
        if k == 0usize { ret 2.9332563730829348990f64 }
        if k == 1usize { ret 0.4896518224847036624f64 }
        if k == 2usize { ret 0.0228637617355380860f64 }
        if k == 3usize { ret -0.0001715731377284693f64 }
        if k == 4usize { ret -0.0000105927538148751f64 }
        if k == 5usize { ret 1.0595602530419e-6f64 }
        if k == 6usize { ret -4.68016051691e-8f64 }
        if k == 7usize { ret 5.8310020e-12f64 }
        if k == 8usize { ret 1.766537581e-10f64 }
        if k == 9usize { ret -1.45034640e-11f64 }
        if k == 10usize { ret 4.357772e-13f64 }
        if k == 11usize { ret 4.60971e-14f64 }
        if k == 12usize { ret -2.57571e-14f64 }
        if k == 13usize { ret 2.26468e-14f64 }
        if k == 14usize { ret -2.22053e-14f64 }
        if k == 15usize { ret 2.08593e-14f64 }
        if k == 16usize { ret -1.84454e-14f64 }
        if k == 17usize { ret 1.50150e-14f64 }
        if k == 18usize { ret -1.06506e-14f64 }
        if k == 19usize { ret 5.5375e-15f64 }
    }
    if id == 1usize {
        if k == 0usize { ret 22.40725276466303489f64 }
        if k == 1usize { ret 10.39808258825165581f64 }
        if k == 2usize { ret 1.092050144486018425f64 }
        if k == 3usize { ret -0.071111274777921604f64 }
        if k == 4usize { ret 0.008990125336059704f64 }
        if k == 5usize { ret -0.001201950338088875f64 }
        if k == 6usize { ret 0.000106686807968315f64 }
        if k == 7usize { ret 0.000017406491576830f64 }
        if k == 8usize { ret -0.000014946669657805f64 }
        if k == 9usize { ret 6.189984487752e-6f64 }
        if k == 10usize { ret -2.049466715178e-6f64 }
        if k == 11usize { ret 5.87189458020e-7f64 }
        if k == 12usize { ret -1.46077514157e-7f64 }
        if k == 13usize { ret 2.9803936132e-8f64 }
        if k == 14usize { ret -3.817692108e-9f64 }
        if k == 15usize { ret -4.66980416e-10f64 }
        if k == 16usize { ret 5.83860334e-10f64 }
        if k == 17usize { ret -2.78825299e-10f64 }
        if k == 18usize { ret 1.01682688e-10f64 }
        if k == 19usize { ret -3.1209928e-11f64 }
        if k == 20usize { ret 8.111122e-12f64 }
        if k == 21usize { ret -1.663986e-12f64 }
        if k == 22usize { ret 1.81364e-13f64 }
        if k == 23usize { ret 5.3414e-14f64 }
        if k == 24usize { ret -4.7234e-14f64 }
        if k == 25usize { ret 2.1689e-14f64 }
        if k == 26usize { ret -7.815e-15f64 }
        if k == 27usize { ret 2.371e-15f64 }
        if k == 28usize { ret -6.04e-16f64 }
        if k == 29usize { ret 1.20e-16f64 }
    }
    if id == 2usize {
        if k == 0usize { ret 1.3824761227122911500f64 }
        if k == 1usize { ret 0.0244856101686774245f64 }
        if k == 2usize { ret -0.0000842866496282540f64 }
        if k == 3usize { ret 1.4656076569771e-6f64 }
        if k == 4usize { ret -3.14874099476e-8f64 }
        if k == 5usize { ret 7.561134833e-10f64 }
        if k == 6usize { ret -1.94531643e-11f64 }
        if k == 7usize { ret 5.245878e-13f64 }
        if k == 8usize { ret -1.46380e-14f64 }
        if k == 9usize { ret 4.192e-16f64 }
        if k == 10usize { ret -1.23e-17f64 }
    }
    if id == 3usize {
        if k == 0usize { ret -0.123783199829515294670493131190f64 }
        if k == 1usize { ret 0.104636462534700704670877382304f64 }
        if k == 2usize { ret -0.067500816575851826744877535903f64 }
        if k == 3usize { ret 0.035563362418888483652711005520f64 }
        if k == 4usize { ret -0.0160738524035979408472979609051f64 }
        if k == 5usize { ret 0.0064497878252851092073278056238f64 }
        if k == 6usize { ret -0.00235408261133449663958121821593f64 }
        if k == 7usize { ret 0.00079545702851302155411892534965f64 }
        if k == 8usize { ret -0.00025214920745855079895784825637f64 }
        if k == 9usize { ret 0.00007574004596069392921153301833f64 }
        if k == 10usize { ret -0.00002172917966339623434407978263f64 }
        if k == 11usize { ret 5.9914810727868915476543145465e-06f64 }
        if k == 12usize { ret -1.5958781571808992162953719817e-06f64 }
        if k == 13usize { ret 4.1232986512903717525448312012e-07f64 }
        if k == 14usize { ret -1.0369725993417659101913919101e-07f64 }
        if k == 15usize { ret 2.5457982304266541145999235022e-08f64 }
        if k == 16usize { ret -6.1161715053791743082427422443e-09f64 }
        if k == 17usize { ret 1.4409346199138658887871461320e-09f64 }
        if k == 18usize { ret -3.3350445956255561668232014995e-10f64 }
        if k == 19usize { ret 7.5950686572918996453336138108e-11f64 }
        if k == 20usize { ret -1.7042296334409430377389900278e-11f64 }
        if k == 21usize { ret 3.7723525020626230919721640081e-12f64 }
        if k == 22usize { ret -8.2460237635733980528416501227e-13f64 }
        if k == 23usize { ret 1.7816961527997797696251868875e-13f64 }
        if k == 24usize { ret -3.8084101506541792942694560802e-14f64 }
        if k == 25usize { ret 8.0593669930916099079755351563e-15f64 }
        if k == 26usize { ret -1.6896565961641739017452636964e-15f64 }
        if k == 27usize { ret 3.5115651805888443184822853595e-16f64 }
        if k == 28usize { ret -7.2384771938569255638904297651e-17f64 }
        if k == 29usize { ret 1.4806598977677176106283840244e-17f64 }
        if k == 30usize { ret -3.0069285750787303634897997963e-18f64 }
    }
    if id == 4usize {
        if k == 0usize { ret 1.15309329391198493586724229008f64 }
        if k == 1usize { ret -1.01812701728669338904729927846f64 }
        if k == 2usize { ret 0.71964022270555684403652781941f64 }
        if k == 3usize { ret -0.42359963977172689685150061355f64 }
        if k == 4usize { ret 0.215024488759339557817435404261f64 }
        if k == 5usize { ret -0.096751915348145944032096342479f64 }
        if k == 6usize { ret 0.039413982058824310099856035361f64 }
        if k == 7usize { ret -0.014775225692561697963781115014f64 }
        if k == 8usize { ret 0.005162114514159370516947823271f64 }
        if k == 9usize { ret -0.00169783446445524322560925166335f64 }
        if k == 10usize { ret 0.00052995667873006847211519193478f64 }
        if k == 11usize { ret -0.00015802027574996477115667974856f64 }
        if k == 12usize { ret 0.000045254366680989687988902825193f64 }
        if k == 13usize { ret -0.000012503722965474638015488600967f64 }
        if k == 14usize { ret 3.3457656998119148699124716204e-06f64 }
        if k == 15usize { ret -8.6981575241150758412492331833e-07f64 }
        if k == 16usize { ret 2.2030895484325645640823940625e-07f64 }
        if k == 17usize { ret -5.4493369492600677068285936533e-08f64 }
        if k == 18usize { ret 1.3190457281724829107139385556e-08f64 }
        if k == 19usize { ret -3.1301560183377379158951191769e-09f64 }
        if k == 20usize { ret 7.2937802527123344842593076131e-10f64 }
        if k == 21usize { ret -1.6712080137945140407348940109e-10f64 }
        if k == 22usize { ret 3.7700053248213600430503521194e-11f64 }
        if k == 23usize { ret -8.3824538848817227637828899571e-12f64 }
        if k == 24usize { ret 1.8388741910049766865274037194e-12f64 }
        if k == 25usize { ret -3.9835919980753778560117573063e-13f64 }
        if k == 26usize { ret 8.5288827136546615604290389711e-14f64 }
        if k == 27usize { ret -1.8060227869114416998653266836e-14f64 }
        if k == 28usize { ret 3.7849342199690728470461022877e-15f64 }
        if k == 29usize { ret -7.8552867468122209577151823365e-16f64 }
    }
    if id == 5usize {
        if k == 0usize { ret 0.00118587147272683864479328868589f64 }
        if k == 1usize { ret 0.00034820459990648274622193981840f64 }
        if k == 2usize { ret -0.00030411304425639768103075864567f64 }
        if k == 3usize { ret 0.00002812066284012343531484682886f64 }
        if k == 4usize { ret 0.00004493525295901613184489898748f64 }
        if k == 5usize { ret -0.00003037629997093072196779489677f64 }
        if k == 6usize { ret 0.00001125979647123875721949743970f64 }
        if k == 7usize { ret -2.4832533969517775991951008218e-06f64 }
        if k == 8usize { ret -9.9003813640537799587086928278e-08f64 }
        if k == 9usize { ret 4.9259859656183110299492296029e-07f64 }
        if k == 10usize { ret -3.7644120964426705960749504975e-07f64 }
        if k == 11usize { ret 2.2887828521334625189639122509e-07f64 }
        if k == 12usize { ret -1.3202687370822203731489855050e-07f64 }
        if k == 13usize { ret 7.7019669092537400811434860763e-08f64 }
        if k == 14usize { ret -4.6589706973010511603890144294e-08f64 }
        if k == 15usize { ret 2.9396476233013923711978522963e-08f64 }
        if k == 16usize { ret -1.9293230611988282919101954538e-08f64 }
        if k == 17usize { ret 1.3099107013728717842406906896e-08f64 }
        if k == 18usize { ret -9.1509111940885962831104149355e-09f64 }
        if k == 19usize { ret 6.5483472971925614347299375295e-09f64 }
        if k == 20usize { ret -4.7831253582139967461241674569e-09f64 }
        if k == 21usize { ret 3.5562625457426178152760148639e-09f64 }
        if k == 22usize { ret -2.6853389444008414186916562103e-09f64 }
        if k == 23usize { ret 2.0554738667134200145781857289e-09f64 }
        if k == 24usize { ret -1.5923172019517426277886522758e-09f64 }
        if k == 25usize { ret 1.2465923213464381457319481498e-09f64 }
        if k == 26usize { ret -9.8494846881180588507969988989e-10f64 }
        if k == 27usize { ret 7.8438674499372126663957464312e-10f64 }
        if k == 28usize { ret -6.2877567918342950225937136855e-10f64 }
        if k == 29usize { ret 5.0662318868755257959686944117e-10f64 }
        if k == 30usize { ret -4.0962270881243451160378710952e-10f64 }
        if k == 31usize { ret 3.3168684677374908553161911299e-10f64 }
        if k == 32usize { ret -2.6829406619847450633596163305e-10f64 }
        if k == 33usize { ret 2.1603988122184568375561077873e-10f64 }
        if k == 34usize { ret -1.7232373309560278402012124481e-10f64 }
        if k == 35usize { ret 1.3512709089611470626617830434e-10f64 }
        if k == 36usize { ret -1.0285354732538663013167579792e-10f64 }
        if k == 37usize { ret 7.4211345443901713467637018423e-11f64 }
        if k == 38usize { ret -4.8124980266864320351456993068e-11f64 }
        if k == 39usize { ret 2.3666534694476306077416831958e-11f64 }
    }
    if id == 6usize {
        if k == 0usize { ret -0.0102445379362695740863663926486f64 }
        if k == 1usize { ret 0.0036618484329295342954730801917f64 }
        if k == 2usize { ret 0.0026154252498599303282569321117f64 }
        if k == 3usize { ret -0.0036187389410353156728771706336f64 }
        if k == 4usize { ret 0.0021878564157692275944613452462f64 }
        if k == 5usize { ret -0.0008219952303590803584426516821f64 }
        if k == 6usize { ret 0.0001281773889155631494321316520f64 }
        if k == 7usize { ret 0.0001000944653368032985720548637f64 }
        if k == 8usize { ret -0.0001288293344663774273453147788f64 }
        if k == 9usize { ret 0.00010136264202696513867821487205f64 }
        if k == 10usize { ret -0.00007000275849659556221916572733f64 }
        if k == 11usize { ret 0.00004694886396757430431607955146f64 }
        if k == 12usize { ret -0.00003190003869717837686356945696f64 }
        if k == 13usize { ret 0.00002231453668447775219665947479f64 }
        if k == 14usize { ret -0.00001611102197712439539300336438f64 }
        if k == 15usize { ret 0.00001196634424990735214466633513f64 }
        if k == 16usize { ret -9.0986920398931223804111374679e-06f64 }
        if k == 17usize { ret 7.0492613694235423068926562567e-06f64 }
        if k == 18usize { ret -5.5425216624642184684300615394e-06f64 }
        if k == 19usize { ret 4.4071884714230296614449244106e-06f64 }
        if k == 20usize { ret -3.5328595506791663127928952625e-06f64 }
        if k == 21usize { ret 2.84594975572077091520522824686e-06f64 }
        if k == 22usize { ret -2.29592697828824392391071619788e-06f64 }
        if k == 23usize { ret 1.84714740375289956396370322228e-06f64 }
        if k == 24usize { ret -1.47383331248116454652025598620e-06f64 }
        if k == 25usize { ret 1.15687781098593231076084710267e-06f64 }
        if k == 26usize { ret -8.8174688524627071175315084910e-07f64 }
        if k == 27usize { ret 6.3705856964426840441434605593e-07f64 }
        if k == 28usize { ret -4.1358791499961929237755474814e-07f64 }
        if k == 29usize { ret 2.0354151158738819867477996807e-07f64 }
    }
    if id == 7usize {
        if k == 0usize { ret 0.00073681565841337130021924199490f64 }
        if k == 1usize { ret 0.00033803599647571227535304316937f64 }
        if k == 2usize { ret -0.00008251723219239754024210552679f64 }
        if k == 3usize { ret -0.00003390879948656432545900779710f64 }
        if k == 4usize { ret 0.00001961398056848881816694014889f64 }
        if k == 5usize { ret -2.35593745904151401624656805567e-06f64 }
        if k == 6usize { ret -1.79055017080406086541563835433e-06f64 }
        if k == 7usize { ret 1.33129571185610681090725934031e-06f64 }
        if k == 8usize { ret -5.38879444715436544130673956170e-07f64 }
        if k == 9usize { ret 1.49603056041381416881299945557e-07f64 }
        if k == 10usize { ret -1.83377228267274327911131293091e-08f64 }
        if k == 11usize { ret -1.33191430762944336526965187651e-08f64 }
        if k == 12usize { ret 1.60642096463700438411396889489e-08f64 }
        if k == 13usize { ret -1.28932576330421806740136816643e-08f64 }
        if k == 14usize { ret 9.6169275086179165484403221944e-09f64 }
        if k == 15usize { ret -7.1818502280703532276832887290e-09f64 }
        if k == 16usize { ret 5.4744009217215145730697754561e-09f64 }
        if k == 17usize { ret -4.2680446690508456935030086136e-09f64 }
        if k == 18usize { ret 3.3941665009266174865683284781e-09f64 }
        if k == 19usize { ret -2.7440714072221673882163135170e-09f64 }
        if k == 20usize { ret 2.2488361522108255229193038962e-09f64 }
        if k == 21usize { ret -1.8638240716608748862087923337e-09f64 }
        if k == 22usize { ret 1.5592350940805373500866440401e-09f64 }
        if k == 23usize { ret -1.3145743937732330609242633070e-09f64 }
        if k == 24usize { ret 1.1153716777215047842790244968e-09f64 }
        if k == 25usize { ret -9.5117576805266622854647303110e-10f64 }
        if k == 26usize { ret 8.1428799553234876296804561100e-10f64 }
        if k == 27usize { ret -6.9893770813548773664326279169e-10f64 }
        if k == 28usize { ret 6.0073113636087448745018831981e-10f64 }
        if k == 29usize { ret -5.1627434258513453901420776514e-10f64 }
        if k == 30usize { ret 4.4290993195074905891788459756e-10f64 }
        if k == 31usize { ret -3.7852978599966867611179315200e-10f64 }
        if k == 32usize { ret 3.2143959338863177145307610452e-10f64 }
        if k == 33usize { ret -2.7025926680620777594992221143e-10f64 }
        if k == 34usize { ret 2.2384857772457918539228234321e-10f64 }
        if k == 35usize { ret -1.8125071664276678046551271701e-10f64 }
        if k == 36usize { ret 1.4164870008713668767293008546e-10f64 }
        if k == 37usize { ret -1.0433101857132782485813325981e-10f64 }
        if k == 38usize { ret 6.8663910168392483929411418190e-11f64 }
        if k == 39usize { ret -3.4068313177952244040559740439e-11f64 }
    }
    if id == 8usize {
        if k == 0usize { ret -0.00137160820526992057354001614451f64 }
        if k == 1usize { ret -0.00025474937951101049982680561302f64 }
        if k == 2usize { ret 0.00024762975547895881652073467771f64 }
        if k == 3usize { ret 0.00005229657281480196749313930265f64 }
        if k == 4usize { ret -0.00007488354272621512385016593760f64 }
        if k == 5usize { ret 0.00001416880012891046449980449746f64 }
        if k == 6usize { ret 0.00001528986060172183690742576230f64 }
        if k == 7usize { ret -0.00001668672297078590514293325326f64 }
        if k == 8usize { ret 0.00001061765189536459018739585094f64 }
        if k == 9usize { ret -5.8220577442406209989680801335e-06f64 }
        if k == 10usize { ret 3.3322423743855900506302033234e-06f64 }
        if k == 11usize { ret -2.23292405803003860894449897815e-06f64 }
        if k == 12usize { ret 1.74816651036678291794777245325e-06f64 }
        if k == 13usize { ret -1.49581306041395051804547535093e-06f64 }
        if k == 14usize { ret 1.32759146107893129050610165582e-06f64 }
        if k == 15usize { ret -1.19376077392564467408373553343e-06f64 }
        if k == 16usize { ret 1.07878303863211630544654040875e-06f64 }
        if k == 17usize { ret -9.7743335011819134006676476250e-07f64 }
        if k == 18usize { ret 8.8729318903693324226127054792e-07f64 }
        if k == 19usize { ret -8.0671146292125665050876015280e-07f64 }
        if k == 20usize { ret 7.3432860378667354971042255937e-07f64 }
        if k == 21usize { ret -6.6897926072697370325310483359e-07f64 }
        if k == 22usize { ret 6.0966619703735610352576581485e-07f64 }
        if k == 23usize { ret -5.5554095284507959561958605420e-07f64 }
        if k == 24usize { ret 5.0588335673197236002812826526e-07f64 }
        if k == 25usize { ret -4.6008146297767601862670079590e-07f64 }
        if k == 26usize { ret 4.1761348515688145911438168306e-07f64 }
        if k == 27usize { ret -3.7803230006989446874174476515e-07f64 }
        if k == 28usize { ret 3.4095248501364300041684648230e-07f64 }
        if k == 29usize { ret -3.0603959751354749520615015472e-07f64 }
        if k == 30usize { ret 2.7300134179365690589640458993e-07f64 }
        if k == 31usize { ret -2.4158028250762304756044254231e-07f64 }
        if k == 32usize { ret 2.1154781038298751985689113868e-07f64 }
        if k == 33usize { ret -1.8269911328756771201465223313e-07f64 }
        if k == 34usize { ret 1.5484895085808513749026173074e-07f64 }
        if k == 35usize { ret -1.2782806851555809369226440495e-07f64 }
        if k == 36usize { ret 1.0148011725394892565174207341e-07f64 }
        if k == 37usize { ret -7.5658969771439627809239950461e-08f64 }
        if k == 38usize { ret 5.0226342286491286957075289622e-08f64 }
        if k == 39usize { ret -2.5049645660259882970547555831e-08f64 }
    }
    if id == 9usize {
        if k == 0usize { ret -0.00017982561472134418587634980117f64 }
        if k == 1usize { ret -0.00036558603837525275836608884064f64 }
        if k == 2usize { ret -0.00002819398055929628850294406363f64 }
        if k == 3usize { ret 0.00016704539863875736769812786067f64 }
        if k == 4usize { ret -0.00007098969970347674307623044850f64 }
        if k == 5usize { ret -8.4470843942344237748899879940e-06f64 }
        if k == 6usize { ret 0.0000273413090343147765148014327150f64 }
        if k == 7usize { ret -0.0000199073838489821681991178018081f64 }
        if k == 8usize { ret 0.0000100004176278235088881096950105f64 }
        if k == 9usize { ret -3.9739852013143676487867902026e-06f64 }
        if k == 10usize { ret 1.2265357766449574306882693267e-06f64 }
        if k == 11usize { ret -1.88755584306424047416914864854e-07f64 }
        if k == 12usize { ret -1.37482206060161206336523452036e-07f64 }
        if k == 13usize { ret 2.10326379301853336795686477738e-07f64 }
        if k == 14usize { ret -2.05583778245412633433934301948e-07f64 }
        if k == 15usize { ret 1.82377384812654863038691147988e-07f64 }
        if k == 16usize { ret -1.58130247846381041027699152436e-07f64 }
        if k == 17usize { ret 1.36966982725588978654041029615e-07f64 }
        if k == 18usize { ret -1.19250280944620257443805710485e-07f64 }
        if k == 19usize { ret 1.04477169029350256435316644493e-07f64 }
        if k == 20usize { ret -9.2064832489437534542041040184e-08f64 }
        if k == 21usize { ret 8.1523798290458784610230199344e-08f64 }
        if k == 22usize { ret -7.2471794980050867512294061891e-08f64 }
        if k == 23usize { ret 6.4614432955971132569968860233e-08f64 }
        if k == 24usize { ret -5.7724095125560946811081322985e-08f64 }
        if k == 25usize { ret 5.1623107567436835158110947901e-08f64 }
        if k == 26usize { ret -4.6171250746798606260216486042e-08f64 }
        if k == 27usize { ret 4.1256621998650164023254101585e-08f64 }
        if k == 28usize { ret -3.6788925543159819135102047082e-08f64 }
        if k == 29usize { ret 3.2694499457951844422299750661e-08f64 }
        if k == 30usize { ret -2.89125899697964696586521743928e-08f64 }
        if k == 31usize { ret 2.53925288725374047626589488217e-08f64 }
        if k == 32usize { ret -2.20915707933726481321465184207e-08f64 }
        if k == 33usize { ret 1.89732166352720474944407102940e-08f64 }
        if k == 34usize { ret -1.60058977893259856012119939554e-08f64 }
        if k == 35usize { ret 1.31619294542205876946742394494e-08f64 }
        if k == 36usize { ret -1.04166651771938038563454275883e-08f64 }
        if k == 37usize { ret 7.7478015858156185064152078434e-09f64 }
        if k == 38usize { ret -5.1347942579352613057675111787e-09f64 }
        if k == 39usize { ret 2.5583541594586723967261504321e-09f64 }
    }
    if id == 10usize {
        if k == 0usize { ret 0.00009054703770051610946958226736f64 }
        if k == 1usize { ret 0.00033066000498098017589672988293f64 }
        if k == 2usize { ret 0.00019737453734363989127226073272f64 }
        if k == 3usize { ret -0.00015490809725932037720034762889f64 }
        if k == 4usize { ret -0.00004514948935538730085479280454f64 }
        if k == 5usize { ret 0.00007976881782603940889444573924f64 }
        if k == 6usize { ret -0.00003314566154544740986264993251f64 }
        if k == 7usize { ret -1.88212148790135672249935711657e-06f64 }
        if k == 8usize { ret 0.0000114788756505519986352882940648f64 }
        if k == 9usize { ret -9.2263039911196207101468331210e-06f64 }
        if k == 10usize { ret 5.1401128250377780476084336340e-06f64 }
        if k == 11usize { ret -2.38418218951722002658891397905e-06f64 }
        if k == 12usize { ret 1.00664292214481531598338960828e-06f64 }
        if k == 13usize { ret -4.23224678096490060264249970540e-07f64 }
        if k == 14usize { ret 2.00132031535793489976535190025e-07f64 }
        if k == 15usize { ret -1.18689501178886741400633921047e-07f64 }
        if k == 16usize { ret 8.7819524319114212999768013738e-08f64 }
        if k == 17usize { ret -7.3964150324206644900787216386e-08f64 }
        if k == 18usize { ret 6.5780431507637165113885884236e-08f64 }
        if k == 19usize { ret -5.9651053193022652369837650411e-08f64 }
        if k == 20usize { ret 5.4447762662767276209052293773e-08f64 }
        if k == 21usize { ret -4.9802057381568863702541294988e-08f64 }
        if k == 22usize { ret 4.5571368194694340198117635845e-08f64 }
        if k == 23usize { ret -4.1682117173547642845382848197e-08f64 }
        if k == 24usize { ret 3.8084701352766049815367147717e-08f64 }
        if k == 25usize { ret -3.4740302885185237434662649907e-08f64 }
        if k == 26usize { ret 3.1616557064701510611273692060e-08f64 }
        if k == 27usize { ret -2.8685739487689556252374879267e-08f64 }
        if k == 28usize { ret 2.5923752117132254429002796600e-08f64 }
        if k == 29usize { ret -2.3309428552190587304662883477e-08f64 }
    }
    ret 0.0f64
}

fn cheb_eval(id: usize, order: usize, a: f64, b: f64, x: f64) -> (f64, f64) {
    var d = 0.0f64
    var dd = 0.0f64
    let y = (2.0f64 * x - a - b) / (b - a)
    let y2 = 2.0f64 * y
    var e = 0.0f64
    var j = order
    while j >= 1usize {
        let temp = d
        let cj = ctab(id, j)
        d = y2 * d - dd + cj
        e += math.abs[f64](y2 * temp) + math.abs[f64](dd) + math.abs[f64](cj)
        dd = temp
        j -= 1usize
    }
    let temp = d
    let c0 = ctab(id, 0usize)
    d = y * d - dd + 0.5f64 * c0
    e += math.abs[f64](y * temp) + math.abs[f64](dd) + 0.5f64 * math.abs[f64](c0)
    ret (d, 2.2204460492503131e-16f64 * e + math.abs[f64](ctab(id, order)))
}

fn cheb_eval_mode(id: usize, order: usize, order_sp: usize, a: f64, b: f64, x: f64, mode: usize) -> (f64, f64) {
    var d = 0.0f64
    var dd = 0.0f64
    let y = (2.0f64 * x - a - b) / (b - a)
    let y2 = 2.0f64 * y
    var eval_order = order_sp
    if mode % 8usize == 0usize { eval_order = order }
    var j = eval_order
    while j >= 1usize {
        let temp = d
        d = y2 * d - dd + ctab(id, j)
        dd = temp
        j -= 1usize
    }
    let v = y * d - dd + 0.5f64 * ctab(id, 0usize)
    ret (v, 2.2204460492503131e-16f64 * math.abs[f64](v) + math.abs[f64](ctab(id, eval_order)))
}

fn cev_bessel_olver_zofmzeta_a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(0usize, 19usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_zofmzeta_a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(0usize, 19usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_zofmzeta_b(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(1usize, 29usize, 15usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_zofmzeta_b(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(1usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_zofmzeta_c(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(2usize, 10usize, 6usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_zofmzeta_c(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(2usize, 10usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_A3_gt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(3usize, 30usize, 17usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_A3_gt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(3usize, 30usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_A4_gt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(4usize, 17usize, 17usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_A4_gt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(4usize, 17usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_B2_gt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(5usize, 39usize, 30usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_B2_gt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(5usize, 39usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_B3_gt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(6usize, 29usize, 29usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_B3_gt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(6usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_B2_lt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(7usize, 39usize, 39usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_B2_lt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(7usize, 39usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_B3_lt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(8usize, 39usize, 39usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_B3_lt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(8usize, 39usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_A3_lt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(9usize, 39usize, 39usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_A3_lt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(9usize, 39usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_olver_A4_lt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(10usize, 29usize, 29usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_olver_A4_lt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(10usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

