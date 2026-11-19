// Chebyshev coefficient tables of gsl 2.7.1 (specfunc/dawson, clausen, expint, airy, airy_der, bessel_I0, bessel_I1, bessel_K0, bessel_K1, zeta.c), generated from its source by a script, with gsl's cheb_eval_e and cheb_eval_mode_e.
// cheb_eval(id, order, a, b, x) returns (value, error): error = eps * sum |terms| + |c[order]|; cheb_eval_mode(id, order, order_sp, a, b, x, mode) is the mode form: error = eps |value| + |c[order used]|.

use e.math

fn tid_dawson_daw() -> usize { ret 0usize }
fn tord_dawson_daw() -> usize { ret 15usize }
fn tsp_dawson_daw() -> usize { ret 9usize }
fn ta_dawson_daw() -> f64 { ret -1.0f64 }
fn tb_dawson_daw() -> f64 { ret 1.0f64 }
fn tid_dawson_daw2() -> usize { ret 1usize }
fn tord_dawson_daw2() -> usize { ret 32usize }
fn tsp_dawson_daw2() -> usize { ret 21usize }
fn ta_dawson_daw2() -> f64 { ret -1.0f64 }
fn tb_dawson_daw2() -> f64 { ret 1.0f64 }
fn tid_dawson_dawa() -> usize { ret 2usize }
fn tord_dawson_dawa() -> usize { ret 34usize }
fn tsp_dawson_dawa() -> usize { ret 12usize }
fn ta_dawson_dawa() -> f64 { ret -1.0f64 }
fn tb_dawson_dawa() -> f64 { ret 1.0f64 }
fn tid_clausen_aclaus() -> usize { ret 3usize }
fn tord_clausen_aclaus() -> usize { ret 14usize }
fn tsp_clausen_aclaus() -> usize { ret 8usize }
fn ta_clausen_aclaus() -> f64 { ret -1.0f64 }
fn tb_clausen_aclaus() -> f64 { ret 1.0f64 }
fn tid_expint_AE11() -> usize { ret 4usize }
fn tord_expint_AE11() -> usize { ret 38usize }
fn tsp_expint_AE11() -> usize { ret 20usize }
fn ta_expint_AE11() -> f64 { ret -1.0f64 }
fn tb_expint_AE11() -> f64 { ret 1.0f64 }
fn tid_expint_AE12() -> usize { ret 5usize }
fn tord_expint_AE12() -> usize { ret 24usize }
fn tsp_expint_AE12() -> usize { ret 15usize }
fn ta_expint_AE12() -> f64 { ret -1.0f64 }
fn tb_expint_AE12() -> f64 { ret 1.0f64 }
fn tid_expint_E11() -> usize { ret 6usize }
fn tord_expint_E11() -> usize { ret 18usize }
fn tsp_expint_E11() -> usize { ret 13usize }
fn ta_expint_E11() -> f64 { ret -1.0f64 }
fn tb_expint_E11() -> f64 { ret 1.0f64 }
fn tid_expint_E12() -> usize { ret 7usize }
fn tord_expint_E12() -> usize { ret 15usize }
fn tsp_expint_E12() -> usize { ret 10usize }
fn ta_expint_E12() -> f64 { ret -1.0f64 }
fn tb_expint_E12() -> f64 { ret 1.0f64 }
fn tid_expint_AE13() -> usize { ret 8usize }
fn tord_expint_AE13() -> usize { ret 24usize }
fn tsp_expint_AE13() -> usize { ret 15usize }
fn ta_expint_AE13() -> f64 { ret -1.0f64 }
fn tb_expint_AE13() -> f64 { ret 1.0f64 }
fn tid_expint_AE14() -> usize { ret 9usize }
fn tord_expint_AE14() -> usize { ret 25usize }
fn tsp_expint_AE14() -> usize { ret 13usize }
fn ta_expint_AE14() -> f64 { ret -1.0f64 }
fn tb_expint_AE14() -> f64 { ret 1.0f64 }
fn tid_airy_am21() -> usize { ret 10usize }
fn tord_airy_am21() -> usize { ret 36usize }
fn tsp_airy_am21() -> usize { ret 20usize }
fn ta_airy_am21() -> f64 { ret -1.0f64 }
fn tb_airy_am21() -> f64 { ret 1.0f64 }
fn tid_airy_ath1() -> usize { ret 11usize }
fn tord_airy_ath1() -> usize { ret 35usize }
fn tsp_airy_ath1() -> usize { ret 15usize }
fn ta_airy_ath1() -> f64 { ret -1.0f64 }
fn tb_airy_ath1() -> f64 { ret 1.0f64 }
fn tid_airy_am22() -> usize { ret 12usize }
fn tord_airy_am22() -> usize { ret 32usize }
fn tsp_airy_am22() -> usize { ret 15usize }
fn ta_airy_am22() -> f64 { ret -1.0f64 }
fn tb_airy_am22() -> f64 { ret 1.0f64 }
fn tid_airy_ath2() -> usize { ret 13usize }
fn tord_airy_ath2() -> usize { ret 31usize }
fn tsp_airy_ath2() -> usize { ret 16usize }
fn ta_airy_ath2() -> f64 { ret -1.0f64 }
fn tb_airy_ath2() -> f64 { ret 1.0f64 }
fn tid_airy_aif() -> usize { ret 14usize }
fn tord_airy_aif() -> usize { ret 8usize }
fn tsp_airy_aif() -> usize { ret 8usize }
fn ta_airy_aif() -> f64 { ret -1.0f64 }
fn tb_airy_aif() -> f64 { ret 1.0f64 }
fn tid_airy_aig() -> usize { ret 15usize }
fn tord_airy_aig() -> usize { ret 7usize }
fn tsp_airy_aig() -> usize { ret 7usize }
fn ta_airy_aig() -> f64 { ret -1.0f64 }
fn tb_airy_aig() -> f64 { ret 1.0f64 }
fn tid_airy_bif() -> usize { ret 16usize }
fn tord_airy_bif() -> usize { ret 8usize }
fn tsp_airy_bif() -> usize { ret 8usize }
fn ta_airy_bif() -> f64 { ret -1.0f64 }
fn tb_airy_bif() -> f64 { ret 1.0f64 }
fn tid_airy_big() -> usize { ret 17usize }
fn tord_airy_big() -> usize { ret 7usize }
fn tsp_airy_big() -> usize { ret 7usize }
fn ta_airy_big() -> f64 { ret -1.0f64 }
fn tb_airy_big() -> f64 { ret 1.0f64 }
fn tid_airy_bif2() -> usize { ret 18usize }
fn tord_airy_bif2() -> usize { ret 9usize }
fn tsp_airy_bif2() -> usize { ret 9usize }
fn ta_airy_bif2() -> f64 { ret -1.0f64 }
fn tb_airy_bif2() -> f64 { ret 1.0f64 }
fn tid_airy_big2() -> usize { ret 19usize }
fn tord_airy_big2() -> usize { ret 9usize }
fn tsp_airy_big2() -> usize { ret 9usize }
fn ta_airy_big2() -> f64 { ret -1.0f64 }
fn tb_airy_big2() -> f64 { ret 1.0f64 }
fn tid_airy_aip() -> usize { ret 20usize }
fn tord_airy_aip() -> usize { ret 35usize }
fn tsp_airy_aip() -> usize { ret 17usize }
fn ta_airy_aip() -> f64 { ret -1.0f64 }
fn tb_airy_aip() -> f64 { ret 1.0f64 }
fn tid_airy_bip() -> usize { ret 21usize }
fn tord_airy_bip() -> usize { ret 23usize }
fn tsp_airy_bip() -> usize { ret 14usize }
fn ta_airy_bip() -> f64 { ret -1.0f64 }
fn tb_airy_bip() -> f64 { ret 1.0f64 }
fn tid_airy_bip2() -> usize { ret 22usize }
fn tord_airy_bip2() -> usize { ret 28usize }
fn tsp_airy_bip2() -> usize { ret 10usize }
fn ta_airy_bip2() -> f64 { ret -1.0f64 }
fn tb_airy_bip2() -> f64 { ret 1.0f64 }
fn tid_airy_der_aif() -> usize { ret 23usize }
fn tord_airy_der_aif() -> usize { ret 7usize }
fn tsp_airy_der_aif() -> usize { ret 7usize }
fn ta_airy_der_aif() -> f64 { ret -1.0f64 }
fn tb_airy_der_aif() -> f64 { ret 1.0f64 }
fn tid_airy_der_aig() -> usize { ret 24usize }
fn tord_airy_der_aig() -> usize { ret 8usize }
fn tsp_airy_der_aig() -> usize { ret 8usize }
fn ta_airy_der_aig() -> f64 { ret -1.0f64 }
fn tb_airy_der_aig() -> f64 { ret 1.0f64 }
fn tid_airy_der_aip2() -> usize { ret 25usize }
fn tord_airy_der_aip2() -> usize { ret 14usize }
fn tsp_airy_der_aip2() -> usize { ret 9usize }
fn ta_airy_der_aip2() -> f64 { ret -1.0f64 }
fn tb_airy_der_aip2() -> f64 { ret 1.0f64 }
fn tid_airy_der_aip1() -> usize { ret 26usize }
fn tord_airy_der_aip1() -> usize { ret 24usize }
fn tsp_airy_der_aip1() -> usize { ret 14usize }
fn ta_airy_der_aip1() -> f64 { ret -1.0f64 }
fn tb_airy_der_aip1() -> f64 { ret 1.0f64 }
fn tid_airy_der_bif() -> usize { ret 27usize }
fn tord_airy_der_bif() -> usize { ret 7usize }
fn tsp_airy_der_bif() -> usize { ret 7usize }
fn ta_airy_der_bif() -> f64 { ret -1.0f64 }
fn tb_airy_der_bif() -> f64 { ret 1.0f64 }
fn tid_airy_der_big() -> usize { ret 28usize }
fn tord_airy_der_big() -> usize { ret 8usize }
fn tsp_airy_der_big() -> usize { ret 8usize }
fn ta_airy_der_big() -> f64 { ret -1.0f64 }
fn tb_airy_der_big() -> f64 { ret 1.0f64 }
fn tid_airy_der_bif2() -> usize { ret 29usize }
fn tord_airy_der_bif2() -> usize { ret 9usize }
fn tsp_airy_der_bif2() -> usize { ret 9usize }
fn ta_airy_der_bif2() -> f64 { ret -1.0f64 }
fn tb_airy_der_bif2() -> f64 { ret 1.0f64 }
fn tid_airy_der_big2() -> usize { ret 30usize }
fn tord_airy_der_big2() -> usize { ret 9usize }
fn tsp_airy_der_big2() -> usize { ret 9usize }
fn ta_airy_der_big2() -> f64 { ret -1.0f64 }
fn tb_airy_der_big2() -> f64 { ret 1.0f64 }
fn tid_airy_der_bip2() -> usize { ret 31usize }
fn tord_airy_der_bip2() -> usize { ret 28usize }
fn tsp_airy_der_bip2() -> usize { ret 14usize }
fn ta_airy_der_bip2() -> f64 { ret -1.0f64 }
fn tb_airy_der_bip2() -> f64 { ret 1.0f64 }
fn tid_airy_der_bip1() -> usize { ret 32usize }
fn tord_airy_der_bip1() -> usize { ret 23usize }
fn tsp_airy_der_bip1() -> usize { ret 13usize }
fn ta_airy_der_bip1() -> f64 { ret -1.0f64 }
fn tb_airy_der_bip1() -> f64 { ret 1.0f64 }
fn tid_airy_der_an22() -> usize { ret 33usize }
fn tord_airy_der_an22() -> usize { ret 32usize }
fn tsp_airy_der_an22() -> usize { ret 18usize }
fn ta_airy_der_an22() -> f64 { ret -1.0f64 }
fn tb_airy_der_an22() -> f64 { ret 1.0f64 }
fn tid_airy_der_an21() -> usize { ret 34usize }
fn tord_airy_der_an21() -> usize { ret 23usize }
fn tsp_airy_der_an21() -> usize { ret 12usize }
fn ta_airy_der_an21() -> f64 { ret -1.0f64 }
fn tb_airy_der_an21() -> f64 { ret 1.0f64 }
fn tid_airy_der_an20() -> usize { ret 35usize }
fn tord_airy_der_an20() -> usize { ret 15usize }
fn tsp_airy_der_an20() -> usize { ret 8usize }
fn ta_airy_der_an20() -> f64 { ret -1.0f64 }
fn tb_airy_der_an20() -> f64 { ret 1.0f64 }
fn tid_airy_der_aph2() -> usize { ret 36usize }
fn tord_airy_der_aph2() -> usize { ret 31usize }
fn tsp_airy_der_aph2() -> usize { ret 16usize }
fn ta_airy_der_aph2() -> f64 { ret -1.0f64 }
fn tb_airy_der_aph2() -> f64 { ret 1.0f64 }
fn tid_airy_der_aph1() -> usize { ret 37usize }
fn tord_airy_der_aph1() -> usize { ret 21usize }
fn tsp_airy_der_aph1() -> usize { ret 10usize }
fn ta_airy_der_aph1() -> f64 { ret -1.0f64 }
fn tb_airy_der_aph1() -> f64 { ret 1.0f64 }
fn tid_airy_der_aph0() -> usize { ret 38usize }
fn tord_airy_der_aph0() -> usize { ret 14usize }
fn tsp_airy_der_aph0() -> usize { ret 7usize }
fn ta_airy_der_aph0() -> f64 { ret -1.0f64 }
fn tb_airy_der_aph0() -> f64 { ret 1.0f64 }
fn tid_bessel_I0_bi0() -> usize { ret 39usize }
fn tord_bessel_I0_bi0() -> usize { ret 11usize }
fn tsp_bessel_I0_bi0() -> usize { ret 11usize }
fn ta_bessel_I0_bi0() -> f64 { ret -1.0f64 }
fn tb_bessel_I0_bi0() -> f64 { ret 1.0f64 }
fn tid_bessel_I0_ai0() -> usize { ret 40usize }
fn tord_bessel_I0_ai0() -> usize { ret 20usize }
fn tsp_bessel_I0_ai0() -> usize { ret 13usize }
fn ta_bessel_I0_ai0() -> f64 { ret -1.0f64 }
fn tb_bessel_I0_ai0() -> f64 { ret 1.0f64 }
fn tid_bessel_I0_ai02() -> usize { ret 41usize }
fn tord_bessel_I0_ai02() -> usize { ret 21usize }
fn tsp_bessel_I0_ai02() -> usize { ret 11usize }
fn ta_bessel_I0_ai02() -> f64 { ret -1.0f64 }
fn tb_bessel_I0_ai02() -> f64 { ret 1.0f64 }
fn tid_bessel_I1_bi1() -> usize { ret 42usize }
fn tord_bessel_I1_bi1() -> usize { ret 10usize }
fn tsp_bessel_I1_bi1() -> usize { ret 10usize }
fn ta_bessel_I1_bi1() -> f64 { ret -1.0f64 }
fn tb_bessel_I1_bi1() -> f64 { ret 1.0f64 }
fn tid_bessel_I1_ai1() -> usize { ret 43usize }
fn tord_bessel_I1_ai1() -> usize { ret 20usize }
fn tsp_bessel_I1_ai1() -> usize { ret 11usize }
fn ta_bessel_I1_ai1() -> f64 { ret -1.0f64 }
fn tb_bessel_I1_ai1() -> f64 { ret 1.0f64 }
fn tid_bessel_I1_ai12() -> usize { ret 44usize }
fn tord_bessel_I1_ai12() -> usize { ret 21usize }
fn tsp_bessel_I1_ai12() -> usize { ret 9usize }
fn ta_bessel_I1_ai12() -> f64 { ret -1.0f64 }
fn tb_bessel_I1_ai12() -> f64 { ret 1.0f64 }
fn tid_bessel_K0_ak0() -> usize { ret 45usize }
fn tord_bessel_K0_ak0() -> usize { ret 23usize }
fn tsp_bessel_K0_ak0() -> usize { ret 10usize }
fn ta_bessel_K0_ak0() -> f64 { ret -1.0f64 }
fn tb_bessel_K0_ak0() -> f64 { ret 1.0f64 }
fn tid_bessel_K0_ak02() -> usize { ret 46usize }
fn tord_bessel_K0_ak02() -> usize { ret 13usize }
fn tsp_bessel_K0_ak02() -> usize { ret 8usize }
fn ta_bessel_K0_ak02() -> f64 { ret -1.0f64 }
fn tb_bessel_K0_ak02() -> f64 { ret 1.0f64 }
fn tid_bessel_K1_ak1() -> usize { ret 47usize }
fn tord_bessel_K1_ak1() -> usize { ret 24usize }
fn tsp_bessel_K1_ak1() -> usize { ret 9usize }
fn ta_bessel_K1_ak1() -> f64 { ret -1.0f64 }
fn tb_bessel_K1_ak1() -> f64 { ret 1.0f64 }
fn tid_bessel_K1_ak12() -> usize { ret 48usize }
fn tord_bessel_K1_ak12() -> usize { ret 13usize }
fn tsp_bessel_K1_ak12() -> usize { ret 7usize }
fn ta_bessel_K1_ak12() -> f64 { ret -1.0f64 }
fn tb_bessel_K1_ak12() -> f64 { ret 1.0f64 }
fn tid_zeta_zeta_xlt1() -> usize { ret 49usize }
fn tord_zeta_zeta_xlt1() -> usize { ret 13usize }
fn tsp_zeta_zeta_xlt1() -> usize { ret 8usize }
fn ta_zeta_zeta_xlt1() -> f64 { ret -1.0f64 }
fn tb_zeta_zeta_xlt1() -> f64 { ret 1.0f64 }
fn tid_zeta_zeta_xgt1() -> usize { ret 50usize }
fn tord_zeta_zeta_xgt1() -> usize { ret 29usize }
fn tsp_zeta_zeta_xgt1() -> usize { ret 17usize }
fn ta_zeta_zeta_xgt1() -> f64 { ret -1.0f64 }
fn tb_zeta_zeta_xgt1() -> f64 { ret 1.0f64 }
fn tid_zeta_zetam1_inter() -> usize { ret 51usize }
fn tord_zeta_zetam1_inter() -> usize { ret 22usize }
fn tsp_zeta_zetam1_inter() -> usize { ret 12usize }
fn ta_zeta_zetam1_inter() -> f64 { ret -1.0f64 }
fn tb_zeta_zetam1_inter() -> f64 { ret 1.0f64 }

fn ctab(id: usize, k: usize) -> f64 {
    if id == 0usize {
        if k == 0usize { ret -0.6351734375145949201065127736293e-02f64 }
        if k == 1usize { ret -0.2294071479677386939899824125866e+00f64 }
        if k == 2usize { ret 0.2213050093908476441683979161786e-01f64 }
        if k == 3usize { ret -0.1549265453892985046743057753375e-02f64 }
        if k == 4usize { ret 0.8497327715684917456777542948066e-04f64 }
        if k == 5usize { ret -0.3828266270972014924994099521309e-05f64 }
        if k == 6usize { ret 0.1462854806250163197757148949539e-06f64 }
        if k == 7usize { ret -0.4851982381825991798846715425114e-08f64 }
        if k == 8usize { ret 0.1421463577759139790347568183304e-09f64 }
        if k == 9usize { ret -0.3728836087920596525335493054088e-11f64 }
        if k == 10usize { ret 0.8854942961778203370194565231369e-13f64 }
        if k == 11usize { ret -0.1920757131350206355421648417493e-14f64 }
        if k == 12usize { ret 0.3834325867246327588241074439253e-16f64 }
        if k == 13usize { ret -0.7089154168175881633584099327999e-18f64 }
        if k == 14usize { ret 0.1220552135889457674416901120000e-19f64 }
        if k == 15usize { ret -0.1966204826605348760299451733333e-21f64 }
        if k == 16usize { ret 0.2975845541376597189113173333333e-23f64 }
        if k == 17usize { ret -0.4247069514800596951039999999999e-25f64 }
        if k == 18usize { ret 0.5734270767391742798506666666666e-27f64 }
        if k == 19usize { ret -0.7345836823178450261333333333333e-29f64 }
        if k == 20usize { ret 0.8951937667516552533333333333333e-31f64 }
    }
    if id == 1usize {
        if k == 0usize { ret -0.56886544105215527114160533733674e-01f64 }
        if k == 1usize { ret -0.31811346996168131279322878048822e+00f64 }
        if k == 2usize { ret 0.20873845413642236789741580198858e+00f64 }
        if k == 3usize { ret -0.12475409913779131214073498314784e+00f64 }
        if k == 4usize { ret 0.67869305186676777092847516423676e-01f64 }
        if k == 5usize { ret -0.33659144895270939503068230966587e-01f64 }
        if k == 6usize { ret 0.15260781271987971743682460381640e-01f64 }
        if k == 7usize { ret -0.63483709625962148230586094788535e-02f64 }
        if k == 8usize { ret 0.24326740920748520596865966109343e-02f64 }
        if k == 9usize { ret -0.86219541491065032038526983549637e-03f64 }
        if k == 10usize { ret 0.28376573336321625302857636538295e-03f64 }
        if k == 11usize { ret -0.87057549874170423699396581464335e-04f64 }
        if k == 12usize { ret 0.24986849985481658331800044137276e-04f64 }
        if k == 13usize { ret -0.67319286764160294344603050339520e-05f64 }
        if k == 14usize { ret 0.17078578785573543710504524047844e-05f64 }
        if k == 15usize { ret -0.40917551226475381271896592490038e-06f64 }
        if k == 16usize { ret 0.92828292216755773260751785312273e-07f64 }
        if k == 17usize { ret -0.19991403610147617829845096332198e-07f64 }
        if k == 18usize { ret 0.40963490644082195241210487868917e-08f64 }
        if k == 19usize { ret -0.80032409540993168075706781753561e-09f64 }
        if k == 20usize { ret 0.14938503128761465059143225550110e-09f64 }
        if k == 21usize { ret -0.26687999885622329284924651063339e-10f64 }
        if k == 22usize { ret 0.45712216985159458151405617724103e-11f64 }
        if k == 23usize { ret -0.75187305222043565872243727326771e-12f64 }
        if k == 24usize { ret 0.11893100052629681879029828987302e-12f64 }
        if k == 25usize { ret -0.18116907933852346973490318263084e-13f64 }
        if k == 26usize { ret 0.26611733684358969193001612199626e-14f64 }
        if k == 27usize { ret -0.37738863052129419795444109905930e-15f64 }
        if k == 28usize { ret 0.51727953789087172679680082229329e-16f64 }
        if k == 29usize { ret -0.68603684084077500979419564670102e-17f64 }
        if k == 30usize { ret 0.88123751354161071806469337321745e-18f64 }
        if k == 31usize { ret -0.10974248249996606292106299624652e-18f64 }
        if k == 32usize { ret 0.13261199326367178513595545891635e-19f64 }
        if k == 33usize { ret -0.15562732768137380785488776571562e-20f64 }
        if k == 34usize { ret 0.17751425583655720607833415570773e-21f64 }
        if k == 35usize { ret -0.19695006967006578384953608765439e-22f64 }
        if k == 36usize { ret 0.21270074896998699661924010120533e-23f64 }
        if k == 37usize { ret -0.22375398124627973794182113962666e-24f64 }
        if k == 38usize { ret 0.22942768578582348946971383125333e-25f64 }
        if k == 39usize { ret -0.22943788846552928693329592319999e-26f64 }
        if k == 40usize { ret 0.22391702100592453618342297600000e-27f64 }
        if k == 41usize { ret -0.21338230616608897703678225066666e-28f64 }
        if k == 42usize { ret 0.19866196585123531518028458666666e-29f64 }
        if k == 43usize { ret -0.18079295866694391771955199999999e-30f64 }
        if k == 44usize { ret 0.16090686015283030305450666666666e-31f64 }
    }
    if id == 2usize {
        if k == 0usize { ret 0.1690485637765703755422637438849e-01f64 }
        if k == 1usize { ret 0.8683252278406957990536107850768e-02f64 }
        if k == 2usize { ret 0.2424864042417715453277703459889e-03f64 }
        if k == 3usize { ret 0.1261182399572690001651949240377e-04f64 }
        if k == 4usize { ret 0.1066453314636176955705691125906e-05f64 }
        if k == 5usize { ret 0.1358159794790727611348424505728e-06f64 }
        if k == 6usize { ret 0.2171042356577298398904312744743e-07f64 }
        if k == 7usize { ret 0.2867010501805295270343676804813e-08f64 }
        if k == 8usize { ret -0.1901336393035820112282492378024e-09f64 }
        if k == 9usize { ret -0.3097780484395201125532065774268e-09f64 }
        if k == 10usize { ret -0.1029414876057509247398132286413e-09f64 }
        if k == 11usize { ret -0.6260356459459576150417587283121e-11f64 }
        if k == 12usize { ret 0.8563132497446451216262303166276e-11f64 }
        if k == 13usize { ret 0.3033045148075659292976266276257e-11f64 }
        if k == 14usize { ret -0.2523618306809291372630886938826e-12f64 }
        if k == 15usize { ret -0.4210604795440664513175461934510e-12f64 }
        if k == 16usize { ret -0.4431140826646238312143429452036e-13f64 }
        if k == 17usize { ret 0.4911210272841205205940037065117e-13f64 }
        if k == 18usize { ret 0.1235856242283903407076477954739e-13f64 }
        if k == 19usize { ret -0.5788733199016569246955765071069e-14f64 }
        if k == 20usize { ret -0.2282723294807358620978183957030e-14f64 }
        if k == 21usize { ret 0.7637149411014126476312362917590e-15f64 }
        if k == 22usize { ret 0.3851546883566811728777594002095e-15f64 }
        if k == 23usize { ret -0.1199932056928290592803237283045e-15f64 }
        if k == 24usize { ret -0.6313439150094572347334270285250e-16f64 }
        if k == 25usize { ret 0.2239559965972975375254912790237e-16f64 }
        if k == 26usize { ret 0.9987925830076495995132891200749e-17f64 }
        if k == 27usize { ret -0.4681068274322495334536246507252e-17f64 }
        if k == 28usize { ret -0.1436303644349721337241628751534e-17f64 }
        if k == 29usize { ret 0.1020822731410541112977908032130e-17f64 }
        if k == 30usize { ret 0.1538908873136092072837389822372e-18f64 }
        if k == 31usize { ret -0.2189157877645793888894790926056e-18f64 }
        if k == 32usize { ret 0.2156879197938651750392359152517e-20f64 }
        if k == 33usize { ret 0.4370219827442449851134792557395e-19f64 }
        if k == 34usize { ret -0.8234581460977207241098927905177e-20f64 }
        if k == 35usize { ret -0.7498648721256466222903202835420e-20f64 }
        if k == 36usize { ret 0.3282536720735671610957612930039e-20f64 }
        if k == 37usize { ret 0.8858064309503921116076561515151e-21f64 }
        if k == 38usize { ret -0.9185087111727002988094460531485e-21f64 }
        if k == 39usize { ret 0.2978962223788748988314166045791e-22f64 }
        if k == 40usize { ret 0.1972132136618471883159505468041e-21f64 }
        if k == 41usize { ret -0.5974775596362906638089584995117e-22f64 }
        if k == 42usize { ret -0.2834410031503850965443825182441e-22f64 }
        if k == 43usize { ret 0.2209560791131554514777150489012e-22f64 }
        if k == 44usize { ret -0.5439955741897144300079480307711e-25f64 }
        if k == 45usize { ret -0.5213549243294848668017136696470e-23f64 }
        if k == 46usize { ret 0.1702350556813114199065671499076e-23f64 }
        if k == 47usize { ret 0.6917400860836148343022185660197e-24f64 }
        if k == 48usize { ret -0.6540941793002752512239445125802e-24f64 }
        if k == 49usize { ret 0.6093576580439328960371824654636e-25f64 }
        if k == 50usize { ret 0.1408070432905187461501945080272e-24f64 }
        if k == 51usize { ret -0.6785886121054846331167674943755e-25f64 }
        if k == 52usize { ret -0.9799732036214295711741583102225e-26f64 }
        if k == 53usize { ret 0.2121244903099041332598960939160e-25f64 }
        if k == 54usize { ret -0.5954455022548790938238802154487e-26f64 }
        if k == 55usize { ret -0.3093088861875470177838847232049e-26f64 }
        if k == 56usize { ret 0.2854389216344524682400691986104e-26f64 }
        if k == 57usize { ret -0.3951289447379305566023477271811e-27f64 }
        if k == 58usize { ret -0.5906000648607628478116840894453e-27f64 }
        if k == 59usize { ret 0.3670236964668687003647889980609e-27f64 }
        if k == 60usize { ret -0.4839958238042276256598303038941e-29f64 }
        if k == 61usize { ret -0.9799265984210443869597404017022e-28f64 }
        if k == 62usize { ret 0.4684773732612130606158908804300e-28f64 }
        if k == 63usize { ret 0.5030877696993461051647667603155e-29f64 }
        if k == 64usize { ret -0.1547395051706028239247552068295e-28f64 }
        if k == 65usize { ret 0.6112180185086419243976005662714e-29f64 }
        if k == 66usize { ret 0.1357913399124811650343602736158e-29f64 }
        if k == 67usize { ret -0.2417687752768673088385304299044e-29f64 }
        if k == 68usize { ret 0.8369074582074298945292887587291e-30f64 }
        if k == 69usize { ret 0.2665413042788979165838319401566e-30f64 }
        if k == 70usize { ret -0.3811653692354890336935691003712e-30f64 }
        if k == 71usize { ret 0.1230054721884951464371706872585e-30f64 }
        if k == 72usize { ret 0.4622506399041493508805536929983e-31f64 }
        if k == 73usize { ret -0.6120087296881677722911435593001e-31f64 }
        if k == 74usize { ret 0.1966024640193164686956230217896e-31f64 }
    }
    if id == 3usize {
        if k == 0usize { ret 2.142694363766688447e+00f64 }
        if k == 1usize { ret 0.723324281221257925e-01f64 }
        if k == 2usize { ret 0.101642475021151164e-02f64 }
        if k == 3usize { ret 0.3245250328531645e-04f64 }
        if k == 4usize { ret 0.133315187571472e-05f64 }
        if k == 5usize { ret 0.6213240591653e-07f64 }
        if k == 6usize { ret 0.313004135337e-08f64 }
        if k == 7usize { ret 0.16635723056e-09f64 }
        if k == 8usize { ret 0.919659293e-11f64 }
        if k == 9usize { ret 0.52400462e-12f64 }
        if k == 10usize { ret 0.3058040e-13f64 }
        if k == 11usize { ret 0.18197e-14f64 }
        if k == 12usize { ret 0.1100e-15f64 }
        if k == 13usize { ret 0.68e-17f64 }
        if k == 14usize { ret 0.4e-18f64 }
    }
    if id == 4usize {
        if k == 0usize { ret 0.121503239716065790f64 }
        if k == 1usize { ret -0.065088778513550150f64 }
        if k == 2usize { ret 0.004897651357459670f64 }
        if k == 3usize { ret -0.000649237843027216f64 }
        if k == 4usize { ret 0.000093840434587471f64 }
        if k == 5usize { ret 0.000000420236380882f64 }
        if k == 6usize { ret -0.000008113374735904f64 }
        if k == 7usize { ret 0.000002804247688663f64 }
        if k == 8usize { ret 0.000000056487164441f64 }
        if k == 9usize { ret -0.000000344809174450f64 }
        if k == 10usize { ret 0.000000058209273578f64 }
        if k == 11usize { ret 0.000000038711426349f64 }
        if k == 12usize { ret -0.000000012453235014f64 }
        if k == 13usize { ret -0.000000005118504888f64 }
        if k == 14usize { ret 0.000000002148771527f64 }
        if k == 15usize { ret 0.000000000868459898f64 }
        if k == 16usize { ret -0.000000000343650105f64 }
        if k == 17usize { ret -0.000000000179796603f64 }
        if k == 18usize { ret 0.000000000047442060f64 }
        if k == 19usize { ret 0.000000000040423282f64 }
        if k == 20usize { ret -0.000000000003543928f64 }
        if k == 21usize { ret -0.000000000008853444f64 }
        if k == 22usize { ret -0.000000000000960151f64 }
        if k == 23usize { ret 0.000000000001692921f64 }
        if k == 24usize { ret 0.000000000000607990f64 }
        if k == 25usize { ret -0.000000000000224338f64 }
        if k == 26usize { ret -0.000000000000200327f64 }
        if k == 27usize { ret -0.000000000000006246f64 }
        if k == 28usize { ret 0.000000000000045571f64 }
        if k == 29usize { ret 0.000000000000016383f64 }
        if k == 30usize { ret -0.000000000000005561f64 }
        if k == 31usize { ret -0.000000000000006074f64 }
        if k == 32usize { ret -0.000000000000000862f64 }
        if k == 33usize { ret 0.000000000000001223f64 }
        if k == 34usize { ret 0.000000000000000716f64 }
        if k == 35usize { ret -0.000000000000000024f64 }
        if k == 36usize { ret -0.000000000000000201f64 }
        if k == 37usize { ret -0.000000000000000082f64 }
        if k == 38usize { ret 0.000000000000000017f64 }
    }
    if id == 5usize {
        if k == 0usize { ret 0.582417495134726740f64 }
        if k == 1usize { ret -0.158348850905782750f64 }
        if k == 2usize { ret -0.006764275590323141f64 }
        if k == 3usize { ret 0.005125843950185725f64 }
        if k == 4usize { ret 0.000435232492169391f64 }
        if k == 5usize { ret -0.000143613366305483f64 }
        if k == 6usize { ret -0.000041801320556301f64 }
        if k == 7usize { ret -0.000002713395758640f64 }
        if k == 8usize { ret 0.000001151381913647f64 }
        if k == 9usize { ret 0.000000420650022012f64 }
        if k == 10usize { ret 0.000000066581901391f64 }
        if k == 11usize { ret 0.000000000662143777f64 }
        if k == 12usize { ret -0.000000002844104870f64 }
        if k == 13usize { ret -0.000000000940724197f64 }
        if k == 14usize { ret -0.000000000177476602f64 }
        if k == 15usize { ret -0.000000000015830222f64 }
        if k == 16usize { ret 0.000000000002905732f64 }
        if k == 17usize { ret 0.000000000001769356f64 }
        if k == 18usize { ret 0.000000000000492735f64 }
        if k == 19usize { ret 0.000000000000093709f64 }
        if k == 20usize { ret 0.000000000000010707f64 }
        if k == 21usize { ret -0.000000000000000537f64 }
        if k == 22usize { ret -0.000000000000000716f64 }
        if k == 23usize { ret -0.000000000000000244f64 }
        if k == 24usize { ret -0.000000000000000058f64 }
    }
    if id == 6usize {
        if k == 0usize { ret -16.11346165557149402600f64 }
        if k == 1usize { ret 7.79407277874268027690f64 }
        if k == 2usize { ret -1.95540581886314195070f64 }
        if k == 3usize { ret 0.37337293866277945612f64 }
        if k == 4usize { ret -0.05692503191092901938f64 }
        if k == 5usize { ret 0.00721107776966009185f64 }
        if k == 6usize { ret -0.00078104901449841593f64 }
        if k == 7usize { ret 0.00007388093356262168f64 }
        if k == 8usize { ret -0.00000620286187580820f64 }
        if k == 9usize { ret 0.00000046816002303176f64 }
        if k == 10usize { ret -0.00000003209288853329f64 }
        if k == 11usize { ret 0.00000000201519974874f64 }
        if k == 12usize { ret -0.00000000011673686816f64 }
        if k == 13usize { ret 0.00000000000627627066f64 }
        if k == 14usize { ret -0.00000000000031481541f64 }
        if k == 15usize { ret 0.00000000000001479904f64 }
        if k == 16usize { ret -0.00000000000000065457f64 }
        if k == 17usize { ret 0.00000000000000002733f64 }
        if k == 18usize { ret -0.00000000000000000108f64 }
    }
    if id == 7usize {
        if k == 0usize { ret -0.03739021479220279500f64 }
        if k == 1usize { ret 0.04272398606220957700f64 }
        if k == 2usize { ret -0.13031820798497005440f64 }
        if k == 3usize { ret 0.01441912402469889073f64 }
        if k == 4usize { ret -0.00134617078051068022f64 }
        if k == 5usize { ret 0.00010731029253063780f64 }
        if k == 6usize { ret -0.00000742999951611943f64 }
        if k == 7usize { ret 0.00000045377325690753f64 }
        if k == 8usize { ret -0.00000002476417211390f64 }
        if k == 9usize { ret 0.00000000122076581374f64 }
        if k == 10usize { ret -0.00000000005485141480f64 }
        if k == 11usize { ret 0.00000000000226362142f64 }
        if k == 12usize { ret -0.00000000000008635897f64 }
        if k == 13usize { ret 0.00000000000000306291f64 }
        if k == 14usize { ret -0.00000000000000010148f64 }
        if k == 15usize { ret 0.00000000000000000315f64 }
    }
    if id == 8usize {
        if k == 0usize { ret -0.605773246640603460f64 }
        if k == 1usize { ret -0.112535243483660900f64 }
        if k == 2usize { ret 0.013432266247902779f64 }
        if k == 3usize { ret -0.001926845187381145f64 }
        if k == 4usize { ret 0.000309118337720603f64 }
        if k == 5usize { ret -0.000053564132129618f64 }
        if k == 6usize { ret 0.000009827812880247f64 }
        if k == 7usize { ret -0.000001885368984916f64 }
        if k == 8usize { ret 0.000000374943193568f64 }
        if k == 9usize { ret -0.000000076823455870f64 }
        if k == 10usize { ret 0.000000016143270567f64 }
        if k == 11usize { ret -0.000000003466802211f64 }
        if k == 12usize { ret 0.000000000758754209f64 }
        if k == 13usize { ret -0.000000000168864333f64 }
        if k == 14usize { ret 0.000000000038145706f64 }
        if k == 15usize { ret -0.000000000008733026f64 }
        if k == 16usize { ret 0.000000000002023672f64 }
        if k == 17usize { ret -0.000000000000474132f64 }
        if k == 18usize { ret 0.000000000000112211f64 }
        if k == 19usize { ret -0.000000000000026804f64 }
        if k == 20usize { ret 0.000000000000006457f64 }
        if k == 21usize { ret -0.000000000000001568f64 }
        if k == 22usize { ret 0.000000000000000383f64 }
        if k == 23usize { ret -0.000000000000000094f64 }
        if k == 24usize { ret 0.000000000000000023f64 }
    }
    if id == 9usize {
        if k == 0usize { ret -0.18929180007530170f64 }
        if k == 1usize { ret -0.08648117855259871f64 }
        if k == 2usize { ret 0.00722410154374659f64 }
        if k == 3usize { ret -0.00080975594575573f64 }
        if k == 4usize { ret 0.00010999134432661f64 }
        if k == 5usize { ret -0.00001717332998937f64 }
        if k == 6usize { ret 0.00000298562751447f64 }
        if k == 7usize { ret -0.00000056596491457f64 }
        if k == 8usize { ret 0.00000011526808397f64 }
        if k == 9usize { ret -0.00000002495030440f64 }
        if k == 10usize { ret 0.00000000569232420f64 }
        if k == 11usize { ret -0.00000000135995766f64 }
        if k == 12usize { ret 0.00000000033846628f64 }
        if k == 13usize { ret -0.00000000008737853f64 }
        if k == 14usize { ret 0.00000000002331588f64 }
        if k == 15usize { ret -0.00000000000641148f64 }
        if k == 16usize { ret 0.00000000000181224f64 }
        if k == 17usize { ret -0.00000000000052538f64 }
        if k == 18usize { ret 0.00000000000015592f64 }
        if k == 19usize { ret -0.00000000000004729f64 }
        if k == 20usize { ret 0.00000000000001463f64 }
        if k == 21usize { ret -0.00000000000000461f64 }
        if k == 22usize { ret 0.00000000000000148f64 }
        if k == 23usize { ret -0.00000000000000048f64 }
        if k == 24usize { ret 0.00000000000000016f64 }
        if k == 25usize { ret -0.00000000000000005f64 }
    }
    if id == 10usize {
        if k == 0usize { ret 0.0065809191761485f64 }
        if k == 1usize { ret 0.0023675984685722f64 }
        if k == 2usize { ret 0.0001324741670371f64 }
        if k == 3usize { ret 0.0000157600904043f64 }
        if k == 4usize { ret 0.0000027529702663f64 }
        if k == 5usize { ret 0.0000006102679017f64 }
        if k == 6usize { ret 0.0000001595088468f64 }
        if k == 7usize { ret 0.0000000471033947f64 }
        if k == 8usize { ret 0.0000000152933871f64 }
        if k == 9usize { ret 0.0000000053590722f64 }
        if k == 10usize { ret 0.0000000020000910f64 }
        if k == 11usize { ret 0.0000000007872292f64 }
        if k == 12usize { ret 0.0000000003243103f64 }
        if k == 13usize { ret 0.0000000001390106f64 }
        if k == 14usize { ret 0.0000000000617011f64 }
        if k == 15usize { ret 0.0000000000282491f64 }
        if k == 16usize { ret 0.0000000000132979f64 }
        if k == 17usize { ret 0.0000000000064188f64 }
        if k == 18usize { ret 0.0000000000031697f64 }
        if k == 19usize { ret 0.0000000000015981f64 }
        if k == 20usize { ret 0.0000000000008213f64 }
        if k == 21usize { ret 0.0000000000004296f64 }
        if k == 22usize { ret 0.0000000000002284f64 }
        if k == 23usize { ret 0.0000000000001232f64 }
        if k == 24usize { ret 0.0000000000000675f64 }
        if k == 25usize { ret 0.0000000000000374f64 }
        if k == 26usize { ret 0.0000000000000210f64 }
        if k == 27usize { ret 0.0000000000000119f64 }
        if k == 28usize { ret 0.0000000000000068f64 }
        if k == 29usize { ret 0.0000000000000039f64 }
        if k == 30usize { ret 0.0000000000000023f64 }
        if k == 31usize { ret 0.0000000000000013f64 }
        if k == 32usize { ret 0.0000000000000008f64 }
        if k == 33usize { ret 0.0000000000000005f64 }
        if k == 34usize { ret 0.0000000000000003f64 }
        if k == 35usize { ret 0.0000000000000001f64 }
        if k == 36usize { ret 0.0000000000000001f64 }
    }
    if id == 11usize {
        if k == 0usize { ret -0.07125837815669365f64 }
        if k == 1usize { ret -0.00590471979831451f64 }
        if k == 2usize { ret -0.00012114544069499f64 }
        if k == 3usize { ret -0.00000988608542270f64 }
        if k == 4usize { ret -0.00000138084097352f64 }
        if k == 5usize { ret -0.00000026142640172f64 }
        if k == 6usize { ret -0.00000006050432589f64 }
        if k == 7usize { ret -0.00000001618436223f64 }
        if k == 8usize { ret -0.00000000483464911f64 }
        if k == 9usize { ret -0.00000000157655272f64 }
        if k == 10usize { ret -0.00000000055231518f64 }
        if k == 11usize { ret -0.00000000020545441f64 }
        if k == 12usize { ret -0.00000000008043412f64 }
        if k == 13usize { ret -0.00000000003291252f64 }
        if k == 14usize { ret -0.00000000001399875f64 }
        if k == 15usize { ret -0.00000000000616151f64 }
        if k == 16usize { ret -0.00000000000279614f64 }
        if k == 17usize { ret -0.00000000000130428f64 }
        if k == 18usize { ret -0.00000000000062373f64 }
        if k == 19usize { ret -0.00000000000030512f64 }
        if k == 20usize { ret -0.00000000000015239f64 }
        if k == 21usize { ret -0.00000000000007758f64 }
        if k == 22usize { ret -0.00000000000004020f64 }
        if k == 23usize { ret -0.00000000000002117f64 }
        if k == 24usize { ret -0.00000000000001132f64 }
        if k == 25usize { ret -0.00000000000000614f64 }
        if k == 26usize { ret -0.00000000000000337f64 }
        if k == 27usize { ret -0.00000000000000188f64 }
        if k == 28usize { ret -0.00000000000000105f64 }
        if k == 29usize { ret -0.00000000000000060f64 }
        if k == 30usize { ret -0.00000000000000034f64 }
        if k == 31usize { ret -0.00000000000000020f64 }
        if k == 32usize { ret -0.00000000000000011f64 }
        if k == 33usize { ret -0.00000000000000007f64 }
        if k == 34usize { ret -0.00000000000000004f64 }
        if k == 35usize { ret -0.00000000000000002f64 }
    }
    if id == 12usize {
        if k == 0usize { ret -0.01562844480625341f64 }
        if k == 1usize { ret 0.00778336445239681f64 }
        if k == 2usize { ret 0.00086705777047718f64 }
        if k == 3usize { ret 0.00015696627315611f64 }
        if k == 4usize { ret 0.00003563962571432f64 }
        if k == 5usize { ret 0.00000924598335425f64 }
        if k == 6usize { ret 0.00000262110161850f64 }
        if k == 7usize { ret 0.00000079188221651f64 }
        if k == 8usize { ret 0.00000025104152792f64 }
        if k == 9usize { ret 0.00000008265223206f64 }
        if k == 10usize { ret 0.00000002805711662f64 }
        if k == 11usize { ret 0.00000000976821090f64 }
        if k == 12usize { ret 0.00000000347407923f64 }
        if k == 13usize { ret 0.00000000125828132f64 }
        if k == 14usize { ret 0.00000000046298826f64 }
        if k == 15usize { ret 0.00000000017272825f64 }
        if k == 16usize { ret 0.00000000006523192f64 }
        if k == 17usize { ret 0.00000000002490471f64 }
        if k == 18usize { ret 0.00000000000960156f64 }
        if k == 19usize { ret 0.00000000000373448f64 }
        if k == 20usize { ret 0.00000000000146417f64 }
        if k == 21usize { ret 0.00000000000057826f64 }
        if k == 22usize { ret 0.00000000000022991f64 }
        if k == 23usize { ret 0.00000000000009197f64 }
        if k == 24usize { ret 0.00000000000003700f64 }
        if k == 25usize { ret 0.00000000000001496f64 }
        if k == 26usize { ret 0.00000000000000608f64 }
        if k == 27usize { ret 0.00000000000000248f64 }
        if k == 28usize { ret 0.00000000000000101f64 }
        if k == 29usize { ret 0.00000000000000041f64 }
        if k == 30usize { ret 0.00000000000000017f64 }
        if k == 31usize { ret 0.00000000000000007f64 }
        if k == 32usize { ret 0.00000000000000002f64 }
    }
    if id == 13usize {
        if k == 0usize { ret 0.00440527345871877f64 }
        if k == 1usize { ret -0.03042919452318455f64 }
        if k == 2usize { ret -0.00138565328377179f64 }
        if k == 3usize { ret -0.00018044439089549f64 }
        if k == 4usize { ret -0.00003380847108327f64 }
        if k == 5usize { ret -0.00000767818353522f64 }
        if k == 6usize { ret -0.00000196783944371f64 }
        if k == 7usize { ret -0.00000054837271158f64 }
        if k == 8usize { ret -0.00000016254615505f64 }
        if k == 9usize { ret -0.00000005053049981f64 }
        if k == 10usize { ret -0.00000001631580701f64 }
        if k == 11usize { ret -0.00000000543420411f64 }
        if k == 12usize { ret -0.00000000185739855f64 }
        if k == 13usize { ret -0.00000000064895120f64 }
        if k == 14usize { ret -0.00000000023105948f64 }
        if k == 15usize { ret -0.00000000008363282f64 }
        if k == 16usize { ret -0.00000000003071196f64 }
        if k == 17usize { ret -0.00000000001142367f64 }
        if k == 18usize { ret -0.00000000000429811f64 }
        if k == 19usize { ret -0.00000000000163389f64 }
        if k == 20usize { ret -0.00000000000062693f64 }
        if k == 21usize { ret -0.00000000000024260f64 }
        if k == 22usize { ret -0.00000000000009461f64 }
        if k == 23usize { ret -0.00000000000003716f64 }
        if k == 24usize { ret -0.00000000000001469f64 }
        if k == 25usize { ret -0.00000000000000584f64 }
        if k == 26usize { ret -0.00000000000000233f64 }
        if k == 27usize { ret -0.00000000000000093f64 }
        if k == 28usize { ret -0.00000000000000037f64 }
        if k == 29usize { ret -0.00000000000000015f64 }
        if k == 30usize { ret -0.00000000000000006f64 }
        if k == 31usize { ret -0.00000000000000002f64 }
    }
    if id == 14usize {
        if k == 0usize { ret -0.03797135849666999750f64 }
        if k == 1usize { ret 0.05919188853726363857f64 }
        if k == 2usize { ret 0.00098629280577279975f64 }
        if k == 3usize { ret 0.00000684884381907656f64 }
        if k == 4usize { ret 0.00000002594202596219f64 }
        if k == 5usize { ret 0.00000000006176612774f64 }
        if k == 6usize { ret 0.00000000000010092454f64 }
        if k == 7usize { ret 0.00000000000000012014f64 }
        if k == 8usize { ret 0.00000000000000000010f64 }
    }
    if id == 15usize {
        if k == 0usize { ret 0.01815236558116127f64 }
        if k == 1usize { ret 0.02157256316601076f64 }
        if k == 2usize { ret 0.00025678356987483f64 }
        if k == 3usize { ret 0.00000142652141197f64 }
        if k == 4usize { ret 0.00000000457211492f64 }
        if k == 5usize { ret 0.00000000000952517f64 }
        if k == 6usize { ret 0.00000000000001392f64 }
        if k == 7usize { ret 0.00000000000000001f64 }
    }
    if id == 16usize {
        if k == 0usize { ret -0.01673021647198664948f64 }
        if k == 1usize { ret 0.10252335834249445610f64 }
        if k == 2usize { ret 0.00170830925073815165f64 }
        if k == 3usize { ret 0.00001186254546774468f64 }
        if k == 4usize { ret 0.00000004493290701779f64 }
        if k == 5usize { ret 0.00000000010698207143f64 }
        if k == 6usize { ret 0.00000000000017480643f64 }
        if k == 7usize { ret 0.00000000000000020810f64 }
        if k == 8usize { ret 0.00000000000000000018f64 }
    }
    if id == 17usize {
        if k == 0usize { ret 0.02246622324857452f64 }
        if k == 1usize { ret 0.03736477545301955f64 }
        if k == 2usize { ret 0.00044476218957212f64 }
        if k == 3usize { ret 0.00000247080756363f64 }
        if k == 4usize { ret 0.00000000791913533f64 }
        if k == 5usize { ret 0.00000000001649807f64 }
        if k == 6usize { ret 0.00000000000002411f64 }
        if k == 7usize { ret 0.00000000000000002f64 }
    }
    if id == 18usize {
        if k == 0usize { ret 0.0998457269381604100f64 }
        if k == 1usize { ret 0.4786249778630055380f64 }
        if k == 2usize { ret 0.0251552119604330118f64 }
        if k == 3usize { ret 0.0005820693885232645f64 }
        if k == 4usize { ret 0.0000074997659644377f64 }
        if k == 5usize { ret 0.0000000613460287034f64 }
        if k == 6usize { ret 0.0000000003462753885f64 }
        if k == 7usize { ret 0.0000000000014288910f64 }
        if k == 8usize { ret 0.0000000000000044962f64 }
        if k == 9usize { ret 0.0000000000000000111f64 }
    }
    if id == 19usize {
        if k == 0usize { ret 0.033305662145514340f64 }
        if k == 1usize { ret 0.161309215123197068f64 }
        if k == 2usize { ret 0.0063190073096134286f64 }
        if k == 3usize { ret 0.0001187904568162517f64 }
        if k == 4usize { ret 0.0000013045345886200f64 }
        if k == 5usize { ret 0.0000000093741259955f64 }
        if k == 6usize { ret 0.0000000000474580188f64 }
        if k == 7usize { ret 0.0000000000001783107f64 }
        if k == 8usize { ret 0.0000000000000005167f64 }
        if k == 9usize { ret 0.0000000000000000011f64 }
    }
    if id == 20usize {
        if k == 0usize { ret -0.0187519297793867540198f64 }
        if k == 1usize { ret -0.0091443848250055004725f64 }
        if k == 2usize { ret 0.0009010457337825074652f64 }
        if k == 3usize { ret -0.0001394184127221491507f64 }
        if k == 4usize { ret 0.0000273815815785209370f64 }
        if k == 5usize { ret -0.0000062750421119959424f64 }
        if k == 6usize { ret 0.0000016064844184831521f64 }
        if k == 7usize { ret -0.0000004476392158510354f64 }
        if k == 8usize { ret 0.0000001334635874651668f64 }
        if k == 9usize { ret -0.0000000420735334263215f64 }
        if k == 10usize { ret 0.0000000139021990246364f64 }
        if k == 11usize { ret -0.0000000047831848068048f64 }
        if k == 12usize { ret 0.0000000017047897907465f64 }
        if k == 13usize { ret -0.0000000006268389576018f64 }
        if k == 14usize { ret 0.0000000002369824276612f64 }
        if k == 15usize { ret -0.0000000000918641139267f64 }
        if k == 16usize { ret 0.0000000000364278543037f64 }
        if k == 17usize { ret -0.0000000000147475551725f64 }
        if k == 18usize { ret 0.0000000000060851006556f64 }
        if k == 19usize { ret -0.0000000000025552772234f64 }
        if k == 20usize { ret 0.0000000000010906187250f64 }
        if k == 21usize { ret -0.0000000000004725870319f64 }
        if k == 22usize { ret 0.0000000000002076969064f64 }
        if k == 23usize { ret -0.0000000000000924976214f64 }
        if k == 24usize { ret 0.0000000000000417096723f64 }
        if k == 25usize { ret -0.0000000000000190299093f64 }
        if k == 26usize { ret 0.0000000000000087790676f64 }
        if k == 27usize { ret -0.0000000000000040927557f64 }
        if k == 28usize { ret 0.0000000000000019271068f64 }
        if k == 29usize { ret -0.0000000000000009160199f64 }
        if k == 30usize { ret 0.0000000000000004393567f64 }
        if k == 31usize { ret -0.0000000000000002125503f64 }
        if k == 32usize { ret 0.0000000000000001036735f64 }
        if k == 33usize { ret -0.0000000000000000509642f64 }
        if k == 34usize { ret 0.0000000000000000252377f64 }
        if k == 35usize { ret -0.0000000000000000125793f64 }
    }
    if id == 21usize {
        if k == 0usize { ret -0.08322047477943447f64 }
        if k == 1usize { ret 0.01146118927371174f64 }
        if k == 2usize { ret 0.00042896440718911f64 }
        if k == 3usize { ret -0.00014906639379950f64 }
        if k == 4usize { ret -0.00001307659726787f64 }
        if k == 5usize { ret 0.00000632759839610f64 }
        if k == 6usize { ret -0.00000042226696982f64 }
        if k == 7usize { ret -0.00000019147186298f64 }
        if k == 8usize { ret 0.00000006453106284f64 }
        if k == 9usize { ret -0.00000000784485467f64 }
        if k == 10usize { ret -0.00000000096077216f64 }
        if k == 11usize { ret 0.00000000070004713f64 }
        if k == 12usize { ret -0.00000000017731789f64 }
        if k == 13usize { ret 0.00000000002272089f64 }
        if k == 14usize { ret 0.00000000000165404f64 }
        if k == 15usize { ret -0.00000000000185171f64 }
        if k == 16usize { ret 0.00000000000059576f64 }
        if k == 17usize { ret -0.00000000000012194f64 }
        if k == 18usize { ret 0.00000000000001334f64 }
        if k == 19usize { ret 0.00000000000000172f64 }
        if k == 20usize { ret -0.00000000000000145f64 }
        if k == 21usize { ret 0.00000000000000049f64 }
        if k == 22usize { ret -0.00000000000000011f64 }
        if k == 23usize { ret 0.00000000000000001f64 }
    }
    if id == 22usize {
        if k == 0usize { ret -0.113596737585988679f64 }
        if k == 1usize { ret 0.0041381473947881595f64 }
        if k == 2usize { ret 0.0001353470622119332f64 }
        if k == 3usize { ret 0.0000104273166530153f64 }
        if k == 4usize { ret 0.0000013474954767849f64 }
        if k == 5usize { ret 0.0000001696537405438f64 }
        if k == 6usize { ret -0.0000000100965008656f64 }
        if k == 7usize { ret -0.0000000167291194937f64 }
        if k == 8usize { ret -0.0000000045815364485f64 }
        if k == 9usize { ret 0.0000000003736681366f64 }
        if k == 10usize { ret 0.0000000005766930320f64 }
        if k == 11usize { ret 0.0000000000621812650f64 }
        if k == 12usize { ret -0.0000000000632941202f64 }
        if k == 13usize { ret -0.0000000000149150479f64 }
        if k == 14usize { ret 0.0000000000078896213f64 }
        if k == 15usize { ret 0.0000000000024960513f64 }
        if k == 16usize { ret -0.0000000000012130075f64 }
        if k == 17usize { ret -0.0000000000003740493f64 }
        if k == 18usize { ret 0.0000000000002237727f64 }
        if k == 19usize { ret 0.0000000000000474902f64 }
        if k == 20usize { ret -0.0000000000000452616f64 }
        if k == 21usize { ret -0.0000000000000030172f64 }
        if k == 22usize { ret 0.0000000000000091058f64 }
        if k == 23usize { ret -0.0000000000000009814f64 }
        if k == 24usize { ret -0.0000000000000016429f64 }
        if k == 25usize { ret 0.0000000000000005533f64 }
        if k == 26usize { ret 0.0000000000000002175f64 }
        if k == 27usize { ret -0.0000000000000001737f64 }
        if k == 28usize { ret -0.0000000000000000010f64 }
    }
    if id == 23usize {
        if k == 0usize { ret 0.10527461226531408809f64 }
        if k == 1usize { ret 0.01183613628152997844f64 }
        if k == 2usize { ret 0.00012328104173225664f64 }
        if k == 3usize { ret 0.00000062261225638140f64 }
        if k == 4usize { ret 0.00000000185298887844f64 }
        if k == 5usize { ret 0.00000000000363328873f64 }
        if k == 6usize { ret 0.00000000000000504622f64 }
        if k == 7usize { ret 0.00000000000000000522f64 }
    }
    if id == 24usize {
        if k == 0usize { ret 0.021233878150918666852f64 }
        if k == 1usize { ret 0.086315930335214406752f64 }
        if k == 2usize { ret 0.001797594720383231358f64 }
        if k == 3usize { ret 0.000014265499875550693f64 }
        if k == 4usize { ret 0.000000059437995283683f64 }
        if k == 5usize { ret 0.000000000152403366479f64 }
        if k == 6usize { ret 0.000000000000264587660f64 }
        if k == 7usize { ret 0.000000000000000331562f64 }
        if k == 8usize { ret 0.000000000000000000314f64 }
    }
    if id == 25usize {
        if k == 0usize { ret 0.0065457691989713757f64 }
        if k == 1usize { ret 0.0023833724120774592f64 }
        if k == 2usize { ret -0.0000430700770220586f64 }
        if k == 3usize { ret 0.0000015629125858629f64 }
        if k == 4usize { ret -0.0000000815417186163f64 }
        if k == 5usize { ret 0.0000000054103738057f64 }
        if k == 6usize { ret -0.0000000004284130883f64 }
        if k == 7usize { ret 0.0000000000389497963f64 }
        if k == 8usize { ret -0.0000000000039623161f64 }
        if k == 9usize { ret 0.0000000000004428184f64 }
        if k == 10usize { ret -0.0000000000000536297f64 }
        if k == 11usize { ret 0.0000000000000069650f64 }
        if k == 12usize { ret -0.0000000000000009620f64 }
        if k == 13usize { ret 0.0000000000000001403f64 }
        if k == 14usize { ret -0.0000000000000000215f64 }
    }
    if id == 26usize {
        if k == 0usize { ret 0.0358865097808301538f64 }
        if k == 1usize { ret 0.0114668575627764899f64 }
        if k == 2usize { ret -0.0007592073583861400f64 }
        if k == 3usize { ret 0.0000869517610893841f64 }
        if k == 4usize { ret -0.0000128237294298592f64 }
        if k == 5usize { ret 0.0000022062695681038f64 }
        if k == 6usize { ret -0.0000004222295185921f64 }
        if k == 7usize { ret 0.0000000874686415726f64 }
        if k == 8usize { ret -0.0000000192773588418f64 }
        if k == 9usize { ret 0.0000000044668460054f64 }
        if k == 10usize { ret -0.0000000010790108052f64 }
        if k == 11usize { ret 0.0000000002700029447f64 }
        if k == 12usize { ret -0.0000000000696480108f64 }
        if k == 13usize { ret 0.0000000000184489907f64 }
        if k == 14usize { ret -0.0000000000050027817f64 }
        if k == 15usize { ret 0.0000000000013852243f64 }
        if k == 16usize { ret -0.0000000000003908218f64 }
        if k == 17usize { ret 0.0000000000001121536f64 }
        if k == 18usize { ret -0.0000000000000326862f64 }
        if k == 19usize { ret 0.0000000000000096619f64 }
        if k == 20usize { ret -0.0000000000000028935f64 }
        if k == 21usize { ret 0.0000000000000008770f64 }
        if k == 22usize { ret -0.0000000000000002688f64 }
        if k == 23usize { ret 0.0000000000000000832f64 }
        if k == 24usize { ret -0.0000000000000000260f64 }
    }
    if id == 27usize {
        if k == 0usize { ret 0.1153536790828570243f64 }
        if k == 1usize { ret 0.0205007894049192875f64 }
        if k == 2usize { ret 0.0002135290278902876f64 }
        if k == 3usize { ret 0.0000010783960614677f64 }
        if k == 4usize { ret 0.0000000032094708833f64 }
        if k == 5usize { ret 0.0000000000062930407f64 }
        if k == 6usize { ret 0.0000000000000087403f64 }
        if k == 7usize { ret 0.0000000000000000090f64 }
    }
    if id == 28usize {
        if k == 0usize { ret -0.097196440416443537390f64 }
        if k == 1usize { ret 0.149503576843167066571f64 }
        if k == 2usize { ret 0.003113525387121326042f64 }
        if k == 3usize { ret 0.000024708570579821297f64 }
        if k == 4usize { ret 0.000000102949627731379f64 }
        if k == 5usize { ret 0.000000000263970373987f64 }
        if k == 6usize { ret 0.000000000000458279271f64 }
        if k == 7usize { ret 0.000000000000000574283f64 }
        if k == 8usize { ret 0.000000000000000000544f64 }
    }
    if id == 29usize {
        if k == 0usize { ret 0.323493987603522033521f64 }
        if k == 1usize { ret 0.086297871535563559139f64 }
        if k == 2usize { ret 0.002994025552655397426f64 }
        if k == 3usize { ret 0.000051430528364661637f64 }
        if k == 4usize { ret 0.000000525840250036811f64 }
        if k == 5usize { ret 0.000000003561751373958f64 }
        if k == 6usize { ret 0.000000000017146864007f64 }
        if k == 7usize { ret 0.000000000000061663520f64 }
        if k == 8usize { ret 0.000000000000000171911f64 }
        if k == 9usize { ret 0.000000000000000000382f64 }
    }
    if id == 30usize {
        if k == 0usize { ret 1.6062999463621294578f64 }
        if k == 1usize { ret 0.7449088819876088652f64 }
        if k == 2usize { ret 0.0470138738610277380f64 }
        if k == 3usize { ret 0.0012284422062548239f64 }
        if k == 4usize { ret 0.0000173222412256624f64 }
        if k == 5usize { ret 0.0000001521901652368f64 }
        if k == 6usize { ret 0.0000000009113560249f64 }
        if k == 7usize { ret 0.0000000000039547918f64 }
        if k == 8usize { ret 0.0000000000000130017f64 }
        if k == 9usize { ret 0.0000000000000000335f64 }
    }
    if id == 31usize {
        if k == 0usize { ret -0.13269705443526630495f64 }
        if k == 1usize { ret -0.00568443626045977481f64 }
        if k == 2usize { ret -0.00015643601119611610f64 }
        if k == 3usize { ret -0.00001136737203679562f64 }
        if k == 4usize { ret -0.00000143464350991284f64 }
        if k == 5usize { ret -0.00000018098531185164f64 }
        if k == 6usize { ret 0.00000000926177343611f64 }
        if k == 7usize { ret 0.00000001710005490721f64 }
        if k == 8usize { ret 0.00000000476698163504f64 }
        if k == 9usize { ret -0.00000000035195022023f64 }
        if k == 10usize { ret -0.00000000058890614316f64 }
        if k == 11usize { ret -0.00000000006678499608f64 }
        if k == 12usize { ret 0.00000000006395565102f64 }
        if k == 13usize { ret 0.00000000001554529427f64 }
        if k == 14usize { ret -0.00000000000792397000f64 }
        if k == 15usize { ret -0.00000000000258326243f64 }
        if k == 16usize { ret 0.00000000000121655048f64 }
        if k == 17usize { ret 0.00000000000038707207f64 }
        if k == 18usize { ret -0.00000000000022487045f64 }
        if k == 19usize { ret -0.00000000000004953477f64 }
        if k == 20usize { ret 0.00000000000004563782f64 }
        if k == 21usize { ret 0.00000000000000332998f64 }
        if k == 22usize { ret -0.00000000000000921750f64 }
        if k == 23usize { ret 0.00000000000000094157f64 }
        if k == 24usize { ret 0.00000000000000167154f64 }
        if k == 25usize { ret -0.00000000000000055134f64 }
        if k == 26usize { ret -0.00000000000000022369f64 }
        if k == 27usize { ret 0.00000000000000017487f64 }
        if k == 28usize { ret 0.00000000000000000207f64 }
    }
    if id == 32usize {
        if k == 0usize { ret -0.1729187351079553719f64 }
        if k == 1usize { ret -0.0149358492984694364f64 }
        if k == 2usize { ret -0.0005471104951678566f64 }
        if k == 3usize { ret 0.0001537966292958408f64 }
        if k == 4usize { ret 0.0000154353476192179f64 }
        if k == 5usize { ret -0.0000065434113851906f64 }
        if k == 6usize { ret 0.0000003728082407879f64 }
        if k == 7usize { ret 0.0000002072078388189f64 }
        if k == 8usize { ret -0.0000000658173336470f64 }
        if k == 9usize { ret 0.0000000074926746354f64 }
        if k == 10usize { ret 0.0000000011101336884f64 }
        if k == 11usize { ret -0.0000000007265140553f64 }
        if k == 12usize { ret 0.0000000001782723560f64 }
        if k == 13usize { ret -0.0000000000217346352f64 }
        if k == 14usize { ret -0.0000000000020302035f64 }
        if k == 15usize { ret 0.0000000000019311827f64 }
        if k == 16usize { ret -0.0000000000006044953f64 }
        if k == 17usize { ret 0.0000000000001209450f64 }
        if k == 18usize { ret -0.0000000000000125109f64 }
        if k == 19usize { ret -0.0000000000000019917f64 }
        if k == 20usize { ret 0.0000000000000015154f64 }
        if k == 21usize { ret -0.0000000000000004977f64 }
        if k == 22usize { ret 0.0000000000000001155f64 }
        if k == 23usize { ret -0.0000000000000000186f64 }
    }
    if id == 33usize {
        if k == 0usize { ret 0.0537418629629794329f64 }
        if k == 1usize { ret -0.0126661435859883193f64 }
        if k == 2usize { ret -0.0011924334106593007f64 }
        if k == 3usize { ret -0.0002032327627275655f64 }
        if k == 4usize { ret -0.0000446468963075164f64 }
        if k == 5usize { ret -0.0000113359036053123f64 }
        if k == 6usize { ret -0.0000031641352378546f64 }
        if k == 7usize { ret -0.0000009446708886149f64 }
        if k == 8usize { ret -0.0000002966562236472f64 }
        if k == 9usize { ret -0.0000000969118892024f64 }
        if k == 10usize { ret -0.0000000326822538653f64 }
        if k == 11usize { ret -0.0000000113144618964f64 }
        if k == 12usize { ret -0.0000000040042691002f64 }
        if k == 13usize { ret -0.0000000014440333684f64 }
        if k == 14usize { ret -0.0000000005292853746f64 }
        if k == 15usize { ret -0.0000000001967763374f64 }
        if k == 16usize { ret -0.0000000000740800096f64 }
        if k == 17usize { ret -0.0000000000282016314f64 }
        if k == 18usize { ret -0.0000000000108440066f64 }
        if k == 19usize { ret -0.0000000000042074801f64 }
        if k == 20usize { ret -0.0000000000016459150f64 }
        if k == 21usize { ret -0.0000000000006486827f64 }
        if k == 22usize { ret -0.0000000000002574095f64 }
        if k == 23usize { ret -0.0000000000001027889f64 }
        if k == 24usize { ret -0.0000000000000412846f64 }
        if k == 25usize { ret -0.0000000000000166711f64 }
        if k == 26usize { ret -0.0000000000000067657f64 }
        if k == 27usize { ret -0.0000000000000027585f64 }
        if k == 28usize { ret -0.0000000000000011296f64 }
        if k == 29usize { ret -0.0000000000000004645f64 }
        if k == 30usize { ret -0.0000000000000001917f64 }
        if k == 31usize { ret -0.0000000000000000794f64 }
        if k == 32usize { ret -0.0000000000000000330f64 }
    }
    if id == 34usize {
        if k == 0usize { ret 0.0198313155263169394f64 }
        if k == 1usize { ret -0.0029376249067087533f64 }
        if k == 2usize { ret -0.0001136260695958196f64 }
        if k == 3usize { ret -0.0000100554451087156f64 }
        if k == 4usize { ret -0.0000013048787116563f64 }
        if k == 5usize { ret -0.0000002123881993151f64 }
        if k == 6usize { ret -0.0000000402270833384f64 }
        if k == 7usize { ret -0.0000000084996745953f64 }
        if k == 8usize { ret -0.0000000019514839426f64 }
        if k == 9usize { ret -0.0000000004783865344f64 }
        if k == 10usize { ret -0.0000000001236733992f64 }
        if k == 11usize { ret -0.0000000000334137486f64 }
        if k == 12usize { ret -0.0000000000093702824f64 }
        if k == 13usize { ret -0.0000000000027130128f64 }
        if k == 14usize { ret -0.0000000000008075954f64 }
        if k == 15usize { ret -0.0000000000002463214f64 }
        if k == 16usize { ret -0.0000000000000767656f64 }
        if k == 17usize { ret -0.0000000000000243883f64 }
        if k == 18usize { ret -0.0000000000000078831f64 }
        if k == 19usize { ret -0.0000000000000025882f64 }
        if k == 20usize { ret -0.0000000000000008619f64 }
        if k == 21usize { ret -0.0000000000000002908f64 }
        if k == 22usize { ret -0.0000000000000000993f64 }
        if k == 23usize { ret -0.0000000000000000343f64 }
    }
    if id == 35usize {
        if k == 0usize { ret 0.0126732217145738027f64 }
        if k == 1usize { ret -0.0005212847072615621f64 }
        if k == 2usize { ret -0.0000052672111140370f64 }
        if k == 3usize { ret -0.0000001628202185026f64 }
        if k == 4usize { ret -0.0000000090991442687f64 }
        if k == 5usize { ret -0.0000000007438647126f64 }
        if k == 6usize { ret -0.0000000000795494752f64 }
        if k == 7usize { ret -0.0000000000104050944f64 }
        if k == 8usize { ret -0.0000000000015932426f64 }
        if k == 9usize { ret -0.0000000000002770648f64 }
        if k == 10usize { ret -0.0000000000000535343f64 }
        if k == 11usize { ret -0.0000000000000113062f64 }
        if k == 12usize { ret -0.0000000000000025772f64 }
        if k == 13usize { ret -0.0000000000000006278f64 }
        if k == 14usize { ret -0.0000000000000001621f64 }
        if k == 15usize { ret -0.0000000000000000441f64 }
    }
    if id == 36usize {
        if k == 0usize { ret -0.2057088719781465107f64 }
        if k == 1usize { ret 0.0422196961357771922f64 }
        if k == 2usize { ret 0.0020482560511207275f64 }
        if k == 3usize { ret 0.0002607800735165006f64 }
        if k == 4usize { ret 0.0000474824268004729f64 }
        if k == 5usize { ret 0.0000105102756431612f64 }
        if k == 6usize { ret 0.0000026353534014668f64 }
        if k == 7usize { ret 0.0000007208824863499f64 }
        if k == 8usize { ret 0.0000002103236664473f64 }
        if k == 9usize { ret 0.0000000644975634555f64 }
        if k == 10usize { ret 0.0000000205802377264f64 }
        if k == 11usize { ret 0.0000000067836273921f64 }
        if k == 12usize { ret 0.0000000022974015284f64 }
        if k == 13usize { ret 0.0000000007961306765f64 }
        if k == 14usize { ret 0.0000000002813860610f64 }
        if k == 15usize { ret 0.0000000001011749057f64 }
        if k == 16usize { ret 0.0000000000369306738f64 }
        if k == 17usize { ret 0.0000000000136615066f64 }
        if k == 18usize { ret 0.0000000000051142751f64 }
        if k == 19usize { ret 0.0000000000019351689f64 }
        if k == 20usize { ret 0.0000000000007393607f64 }
        if k == 21usize { ret 0.0000000000002849792f64 }
        if k == 22usize { ret 0.0000000000001107281f64 }
        if k == 23usize { ret 0.0000000000000433412f64 }
        if k == 24usize { ret 0.0000000000000170801f64 }
        if k == 25usize { ret 0.0000000000000067733f64 }
        if k == 26usize { ret 0.0000000000000027017f64 }
        if k == 27usize { ret 0.0000000000000010835f64 }
        if k == 28usize { ret 0.0000000000000004367f64 }
        if k == 29usize { ret 0.0000000000000001769f64 }
        if k == 30usize { ret 0.0000000000000000719f64 }
        if k == 31usize { ret 0.0000000000000000294f64 }
    }
    if id == 37usize {
        if k == 0usize { ret -0.1024172908077571694f64 }
        if k == 1usize { ret 0.0071697275146591248f64 }
        if k == 2usize { ret 0.0001209959363122329f64 }
        if k == 3usize { ret 0.0000073361512841220f64 }
        if k == 4usize { ret 0.0000007535382954272f64 }
        if k == 5usize { ret 0.0000001041478171741f64 }
        if k == 6usize { ret 0.0000000174358728519f64 }
        if k == 7usize { ret 0.0000000033399795033f64 }
        if k == 8usize { ret 0.0000000007073075174f64 }
        if k == 9usize { ret 0.0000000001619187515f64 }
        if k == 10usize { ret 0.0000000000394539982f64 }
        if k == 11usize { ret 0.0000000000101192282f64 }
        if k == 12usize { ret 0.0000000000027092778f64 }
        if k == 13usize { ret 0.0000000000007523806f64 }
        if k == 14usize { ret 0.0000000000002156369f64 }
        if k == 15usize { ret 0.0000000000000635283f64 }
        if k == 16usize { ret 0.0000000000000191757f64 }
        if k == 17usize { ret 0.0000000000000059143f64 }
        if k == 18usize { ret 0.0000000000000018597f64 }
        if k == 19usize { ret 0.0000000000000005950f64 }
        if k == 20usize { ret 0.0000000000000001934f64 }
        if k == 21usize { ret 0.0000000000000000638f64 }
    }
    if id == 38usize {
        if k == 0usize { ret -0.0855849241130933257f64 }
        if k == 1usize { ret 0.0011214378867065261f64 }
        if k == 2usize { ret 0.0000042721029353664f64 }
        if k == 3usize { ret 0.0000000817607381483f64 }
        if k == 4usize { ret 0.0000000033907645000f64 }
        if k == 5usize { ret 0.0000000002253264423f64 }
        if k == 6usize { ret 0.0000000000206284209f64 }
        if k == 7usize { ret 0.0000000000023858763f64 }
        if k == 8usize { ret 0.0000000000003301618f64 }
        if k == 9usize { ret 0.0000000000000527010f64 }
        if k == 10usize { ret 0.0000000000000094555f64 }
        if k == 11usize { ret 0.0000000000000018709f64 }
        if k == 12usize { ret 0.0000000000000004024f64 }
        if k == 13usize { ret 0.0000000000000000930f64 }
        if k == 14usize { ret 0.0000000000000000229f64 }
    }
    if id == 39usize {
        if k == 0usize { ret -0.07660547252839144951f64 }
        if k == 1usize { ret 1.92733795399380827000f64 }
        if k == 2usize { ret 0.22826445869203013390f64 }
        if k == 3usize { ret 0.01304891466707290428f64 }
        if k == 4usize { ret 0.00043442709008164874f64 }
        if k == 5usize { ret 0.00000942265768600193f64 }
        if k == 6usize { ret 0.00000014340062895106f64 }
        if k == 7usize { ret 0.00000000161384906966f64 }
        if k == 8usize { ret 0.00000000001396650044f64 }
        if k == 9usize { ret 0.00000000000009579451f64 }
        if k == 10usize { ret 0.00000000000000053339f64 }
        if k == 11usize { ret 0.00000000000000000245f64 }
    }
    if id == 40usize {
        if k == 0usize { ret 0.07575994494023796f64 }
        if k == 1usize { ret 0.00759138081082334f64 }
        if k == 2usize { ret 0.00041531313389237f64 }
        if k == 3usize { ret 0.00001070076463439f64 }
        if k == 4usize { ret -0.00000790117997921f64 }
        if k == 5usize { ret -0.00000078261435014f64 }
        if k == 6usize { ret 0.00000027838499429f64 }
        if k == 7usize { ret 0.00000000825247260f64 }
        if k == 8usize { ret -0.00000001204463945f64 }
        if k == 9usize { ret 0.00000000155964859f64 }
        if k == 10usize { ret 0.00000000022925563f64 }
        if k == 11usize { ret -0.00000000011916228f64 }
        if k == 12usize { ret 0.00000000001757854f64 }
        if k == 13usize { ret 0.00000000000112822f64 }
        if k == 14usize { ret -0.00000000000114684f64 }
        if k == 15usize { ret 0.00000000000027155f64 }
        if k == 16usize { ret -0.00000000000002415f64 }
        if k == 17usize { ret -0.00000000000000608f64 }
        if k == 18usize { ret 0.00000000000000314f64 }
        if k == 19usize { ret -0.00000000000000071f64 }
        if k == 20usize { ret 0.00000000000000007f64 }
    }
    if id == 41usize {
        if k == 0usize { ret 0.05449041101410882f64 }
        if k == 1usize { ret 0.00336911647825569f64 }
        if k == 2usize { ret 0.00006889758346918f64 }
        if k == 3usize { ret 0.00000289137052082f64 }
        if k == 4usize { ret 0.00000020489185893f64 }
        if k == 5usize { ret 0.00000002266668991f64 }
        if k == 6usize { ret 0.00000000339623203f64 }
        if k == 7usize { ret 0.00000000049406022f64 }
        if k == 8usize { ret 0.00000000001188914f64 }
        if k == 9usize { ret -0.00000000003149915f64 }
        if k == 10usize { ret -0.00000000001321580f64 }
        if k == 11usize { ret -0.00000000000179419f64 }
        if k == 12usize { ret 0.00000000000071801f64 }
        if k == 13usize { ret 0.00000000000038529f64 }
        if k == 14usize { ret 0.00000000000001539f64 }
        if k == 15usize { ret -0.00000000000004151f64 }
        if k == 16usize { ret -0.00000000000000954f64 }
        if k == 17usize { ret 0.00000000000000382f64 }
        if k == 18usize { ret 0.00000000000000176f64 }
        if k == 19usize { ret -0.00000000000000034f64 }
        if k == 20usize { ret -0.00000000000000027f64 }
        if k == 21usize { ret 0.00000000000000003f64 }
    }
    if id == 42usize {
        if k == 0usize { ret -0.001971713261099859f64 }
        if k == 1usize { ret 0.407348876675464810f64 }
        if k == 2usize { ret 0.034838994299959456f64 }
        if k == 3usize { ret 0.001545394556300123f64 }
        if k == 4usize { ret 0.000041888521098377f64 }
        if k == 5usize { ret 0.000000764902676483f64 }
        if k == 6usize { ret 0.000000010042493924f64 }
        if k == 7usize { ret 0.000000000099322077f64 }
        if k == 8usize { ret 0.000000000000766380f64 }
        if k == 9usize { ret 0.000000000000004741f64 }
        if k == 10usize { ret 0.000000000000000024f64 }
    }
    if id == 43usize {
        if k == 0usize { ret -0.02846744181881479f64 }
        if k == 1usize { ret -0.01922953231443221f64 }
        if k == 2usize { ret -0.00061151858579437f64 }
        if k == 3usize { ret -0.00002069971253350f64 }
        if k == 4usize { ret 0.00000858561914581f64 }
        if k == 5usize { ret 0.00000104949824671f64 }
        if k == 6usize { ret -0.00000029183389184f64 }
        if k == 7usize { ret -0.00000001559378146f64 }
        if k == 8usize { ret 0.00000001318012367f64 }
        if k == 9usize { ret -0.00000000144842341f64 }
        if k == 10usize { ret -0.00000000029085122f64 }
        if k == 11usize { ret 0.00000000012663889f64 }
        if k == 12usize { ret -0.00000000001664947f64 }
        if k == 13usize { ret -0.00000000000166665f64 }
        if k == 14usize { ret 0.00000000000124260f64 }
        if k == 15usize { ret -0.00000000000027315f64 }
        if k == 16usize { ret 0.00000000000002023f64 }
        if k == 17usize { ret 0.00000000000000730f64 }
        if k == 18usize { ret -0.00000000000000333f64 }
        if k == 19usize { ret 0.00000000000000071f64 }
        if k == 20usize { ret -0.00000000000000006f64 }
    }
    if id == 44usize {
        if k == 0usize { ret 0.02857623501828014f64 }
        if k == 1usize { ret -0.00976109749136147f64 }
        if k == 2usize { ret -0.00011058893876263f64 }
        if k == 3usize { ret -0.00000388256480887f64 }
        if k == 4usize { ret -0.00000025122362377f64 }
        if k == 5usize { ret -0.00000002631468847f64 }
        if k == 6usize { ret -0.00000000383538039f64 }
        if k == 7usize { ret -0.00000000055897433f64 }
        if k == 8usize { ret -0.00000000001897495f64 }
        if k == 9usize { ret 0.00000000003252602f64 }
        if k == 10usize { ret 0.00000000001412580f64 }
        if k == 11usize { ret 0.00000000000203564f64 }
        if k == 12usize { ret -0.00000000000071985f64 }
        if k == 13usize { ret -0.00000000000040836f64 }
        if k == 14usize { ret -0.00000000000002101f64 }
        if k == 15usize { ret 0.00000000000004273f64 }
        if k == 16usize { ret 0.00000000000001041f64 }
        if k == 17usize { ret -0.00000000000000382f64 }
        if k == 18usize { ret -0.00000000000000186f64 }
        if k == 19usize { ret 0.00000000000000033f64 }
        if k == 20usize { ret 0.00000000000000028f64 }
        if k == 21usize { ret -0.00000000000000003f64 }
    }
    if id == 45usize {
        if k == 0usize { ret -3.28737867094650101e-02f64 }
        if k == 1usize { ret -4.49369057710236880e-02f64 }
        if k == 2usize { ret 2.98149992004308095e-03f64 }
        if k == 3usize { ret -3.03693649396187920e-04f64 }
        if k == 4usize { ret 3.91085569307646836e-05f64 }
        if k == 5usize { ret -5.86872422399215952e-06f64 }
        if k == 6usize { ret 9.82873709937322009e-07f64 }
        if k == 7usize { ret -1.78978645055651171e-07f64 }
        if k == 8usize { ret 3.48332306845240957e-08f64 }
        if k == 9usize { ret -7.15909210462546599e-09f64 }
        if k == 10usize { ret 1.54019930048919494e-09f64 }
        if k == 11usize { ret -3.44555485579194210e-10f64 }
        if k == 12usize { ret 7.97356101783753023e-11f64 }
        if k == 13usize { ret -1.90090968913069735e-11f64 }
        if k == 14usize { ret 4.65295609304114621e-12f64 }
        if k == 15usize { ret -1.16614287433470780e-12f64 }
        if k == 16usize { ret 2.98554375218596891e-13f64 }
        if k == 17usize { ret -7.79276979512292169e-14f64 }
        if k == 18usize { ret 2.07027467168948402e-14f64 }
        if k == 19usize { ret -5.58987860393825313e-15f64 }
        if k == 20usize { ret 1.53202965950646914e-15f64 }
        if k == 21usize { ret -4.25737536712188186e-16f64 }
        if k == 22usize { ret 1.19840238501357389e-16f64 }
        if k == 23usize { ret -3.41407346762502397e-17f64 }
    }
    if id == 46usize {
        if k == 0usize { ret -0.1201869826307592240E-1f64 }
        if k == 1usize { ret -0.9174852691025695311E-2f64 }
        if k == 2usize { ret 0.1444550931775005821E-3f64 }
        if k == 3usize { ret -0.4013614175435709729E-5f64 }
        if k == 4usize { ret 0.1567831810852310673E-6f64 }
        if k == 5usize { ret -0.7770110438521737710E-8f64 }
        if k == 6usize { ret 0.4611182576179717883E-9f64 }
        if k == 7usize { ret -0.3158592997860565771E-10f64 }
        if k == 8usize { ret 0.2435018039365041128E-11f64 }
        if k == 9usize { ret -0.2074331387398347898E-12f64 }
        if k == 10usize { ret 0.1925787280589917085E-13f64 }
        if k == 11usize { ret -0.1927554805838956104E-14f64 }
        if k == 12usize { ret 0.2062198029197818278E-15f64 }
        if k == 13usize { ret -0.2341685117579242403E-16f64 }
    }
    if id == 47usize {
        if k == 0usize { ret 2.07996868001418246e-01f64 }
        if k == 1usize { ret 1.62581565017881476e-01f64 }
        if k == 2usize { ret -5.87070423518863640e-03f64 }
        if k == 3usize { ret 4.95021520115789501e-04f64 }
        if k == 4usize { ret -5.78958347598556986e-05f64 }
        if k == 5usize { ret 8.18614610209334726e-06f64 }
        if k == 6usize { ret -1.31604832009487277e-06f64 }
        if k == 7usize { ret 2.32546031520101213e-07f64 }
        if k == 8usize { ret -4.42206518311557987e-08f64 }
        if k == 9usize { ret 8.92163994883100361e-09f64 }
        if k == 10usize { ret -1.89046270526983427e-09f64 }
        if k == 11usize { ret 4.17568808108504702e-10f64 }
        if k == 12usize { ret -9.55912361791375794e-11f64 }
        if k == 13usize { ret 2.25769353153867758e-11f64 }
        if k == 14usize { ret -5.48128000211158482e-12f64 }
        if k == 15usize { ret 1.36386122546441926e-12f64 }
        if k == 16usize { ret -3.46936690565986409e-13f64 }
        if k == 17usize { ret 9.00354564415705942e-14f64 }
        if k == 18usize { ret -2.37950577776254432e-14f64 }
        if k == 19usize { ret 6.39447503964025336e-15f64 }
        if k == 20usize { ret -1.74498363492322044e-15f64 }
        if k == 21usize { ret 4.82994547989290473e-16f64 }
        if k == 22usize { ret -1.35460927805445606e-16f64 }
        if k == 23usize { ret 3.84604274446777234e-17f64 }
        if k == 24usize { ret -1.10456856122581316e-17f64 }
    }
    if id == 48usize {
        if k == 0usize { ret 0.637930834373900104E-1f64 }
        if k == 1usize { ret 0.283288781304972094E-1f64 }
        if k == 2usize { ret -0.247537067390525035E-3f64 }
        if k == 3usize { ret 0.577197245160724882E-5f64 }
        if k == 4usize { ret -0.206893921953654830E-6f64 }
        if k == 5usize { ret 0.973998344138180418E-8f64 }
        if k == 6usize { ret -0.558533614038062498E-9f64 }
        if k == 7usize { ret 0.373299663404618524E-10f64 }
        if k == 8usize { ret -0.282505196102322545E-11f64 }
        if k == 9usize { ret 0.237201900248414417E-12f64 }
        if k == 10usize { ret -0.217667738799175398E-13f64 }
        if k == 11usize { ret 0.215791416161603245E-14f64 }
        if k == 12usize { ret -0.229019693071826928E-15f64 }
        if k == 13usize { ret 0.258288572982327496E-16f64 }
    }
    if id == 49usize {
        if k == 0usize { ret 1.48018677156931561235192914649f64 }
        if k == 1usize { ret 0.25012062539889426471999938167f64 }
        if k == 2usize { ret 0.00991137502135360774243761467f64 }
        if k == 3usize { ret -0.00012084759656676410329833091f64 }
        if k == 4usize { ret -4.7585866367662556504652535281e-06f64 }
        if k == 5usize { ret 2.2229946694466391855561441361e-07f64 }
        if k == 6usize { ret -2.2237496498030257121309056582e-09f64 }
        if k == 7usize { ret -1.0173226513229028319420799028e-10f64 }
        if k == 8usize { ret 4.3756643450424558284466248449e-12f64 }
        if k == 9usize { ret -6.2229632593100551465504090814e-14f64 }
        if k == 10usize { ret -6.6116201003272207115277520305e-16f64 }
        if k == 11usize { ret 4.9477279533373912324518463830e-17f64 }
        if k == 12usize { ret -1.0429819093456189719660003522e-18f64 }
        if k == 13usize { ret 6.9925216166580021051464412040e-21f64 }
    }
    if id == 50usize {
        if k == 0usize { ret 19.3918515726724119415911269006f64 }
        if k == 1usize { ret 9.1525329692510756181581271500f64 }
        if k == 2usize { ret 0.2427897658867379985365270155f64 }
        if k == 3usize { ret -0.1339000688262027338316641329f64 }
        if k == 4usize { ret 0.0577827064065028595578410202f64 }
        if k == 5usize { ret -0.0187625983754002298566409700f64 }
        if k == 6usize { ret 0.0039403014258320354840823803f64 }
        if k == 7usize { ret -0.0000581508273158127963598882f64 }
        if k == 8usize { ret -0.0003756148907214820704594549f64 }
        if k == 9usize { ret 0.0001892530548109214349092999f64 }
        if k == 10usize { ret -0.0000549032199695513496115090f64 }
        if k == 11usize { ret 8.7086484008939038610413331863e-6f64 }
        if k == 12usize { ret 6.4609477924811889068410083425e-7f64 }
        if k == 13usize { ret -9.6749773915059089205835337136e-7f64 }
        if k == 14usize { ret 3.6585400766767257736982342461e-7f64 }
        if k == 15usize { ret -8.4592516427275164351876072573e-8f64 }
        if k == 16usize { ret 9.9956786144497936572288988883e-9f64 }
        if k == 17usize { ret 1.4260036420951118112457144842e-9f64 }
        if k == 18usize { ret -1.1761968823382879195380320948e-9f64 }
        if k == 19usize { ret 3.7114575899785204664648987295e-10f64 }
        if k == 20usize { ret -7.4756855194210961661210215325e-11f64 }
        if k == 21usize { ret 7.8536934209183700456512982968e-12f64 }
        if k == 22usize { ret 9.9827182259685539619810406271e-13f64 }
        if k == 23usize { ret -7.5276687030192221587850302453e-13f64 }
        if k == 24usize { ret 2.1955026393964279988917878654e-13f64 }
        if k == 25usize { ret -4.1934859852834647427576319246e-14f64 }
        if k == 26usize { ret 4.6341149635933550715779074274e-15f64 }
        if k == 27usize { ret 2.3742488509048340106830309402e-16f64 }
        if k == 28usize { ret -2.7276516388124786119323824391e-16f64 }
        if k == 29usize { ret 7.8473570134636044722154797225e-17f64 }
    }
    if id == 51usize {
        if k == 0usize { ret -21.7509435653088483422022339374f64 }
        if k == 1usize { ret -5.63036877698121782876372020472f64 }
        if k == 2usize { ret 0.0528041358684229425504861579635f64 }
        if k == 3usize { ret -0.0156381809179670789342700883562f64 }
        if k == 4usize { ret 0.00408218474372355881195080781927f64 }
        if k == 5usize { ret -0.0010264867349474874045036628282f64 }
        if k == 6usize { ret 0.000260469880409886900143834962387f64 }
        if k == 7usize { ret -0.0000676175847209968878098566819447f64 }
        if k == 8usize { ret 0.0000179284472587833525426660171124f64 }
        if k == 9usize { ret -4.83238651318556188834107605116e-6f64 }
        if k == 10usize { ret 1.31913788964999288471371329447e-6f64 }
        if k == 11usize { ret -3.63760500656329972578222188542e-7f64 }
        if k == 12usize { ret 1.01146847513194744989748396574e-7f64 }
        if k == 13usize { ret -2.83215225141806501619105289509e-8f64 }
        if k == 14usize { ret 7.97733710252021423361012829496e-9f64 }
        if k == 15usize { ret -2.25850168553956886676250696891e-9f64 }
        if k == 16usize { ret 6.42269392950164306086395744145e-10f64 }
        if k == 17usize { ret -1.83363861846127284505060843614e-10f64 }
        if k == 18usize { ret 5.25309763895283179960368072104e-11f64 }
        if k == 19usize { ret -1.50958687042589821074710575446e-11f64 }
        if k == 20usize { ret 4.34997545516049244697776942981e-12f64 }
        if k == 21usize { ret -1.25597782748190416118082322061e-12f64 }
        if k == 22usize { ret 3.61280740072222650030134104162e-13f64 }
        if k == 23usize { ret -9.66437239205745207188920348801e-14f64 }
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

fn cev_dawson_daw(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(0usize, 15usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_dawson_daw(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(0usize, 15usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_dawson_daw2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(1usize, 32usize, 21usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_dawson_daw2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(1usize, 32usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_dawson_dawa(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(2usize, 34usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_dawson_dawa(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(2usize, 34usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_clausen_aclaus(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(3usize, 14usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_clausen_aclaus(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(3usize, 14usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_expint_AE11(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(4usize, 38usize, 20usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_expint_AE11(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(4usize, 38usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_expint_AE12(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(5usize, 24usize, 15usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_expint_AE12(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(5usize, 24usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_expint_E11(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(6usize, 18usize, 13usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_expint_E11(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(6usize, 18usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_expint_E12(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(7usize, 15usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_expint_E12(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(7usize, 15usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_expint_AE13(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(8usize, 24usize, 15usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_expint_AE13(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(8usize, 24usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_expint_AE14(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(9usize, 25usize, 13usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_expint_AE14(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(9usize, 25usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_am21(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(10usize, 36usize, 20usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_am21(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(10usize, 36usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_ath1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(11usize, 35usize, 15usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_ath1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(11usize, 35usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_am22(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(12usize, 32usize, 15usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_am22(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(12usize, 32usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_ath2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(13usize, 31usize, 16usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_ath2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(13usize, 31usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_aif(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(14usize, 8usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_aif(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(14usize, 8usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_aig(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(15usize, 7usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_aig(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(15usize, 7usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_bif(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(16usize, 8usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_bif(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(16usize, 8usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_big(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(17usize, 7usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_big(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(17usize, 7usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_bif2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(18usize, 9usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_bif2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(18usize, 9usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_big2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(19usize, 9usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_big2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(19usize, 9usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_aip(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(20usize, 35usize, 17usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_aip(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(20usize, 35usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_bip(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(21usize, 23usize, 14usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_bip(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(21usize, 23usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_bip2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(22usize, 28usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_bip2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(22usize, 28usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_aif(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(23usize, 7usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_aif(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(23usize, 7usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_aig(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(24usize, 8usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_aig(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(24usize, 8usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_aip2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(25usize, 14usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_aip2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(25usize, 14usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_aip1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(26usize, 24usize, 14usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_aip1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(26usize, 24usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_bif(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(27usize, 7usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_bif(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(27usize, 7usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_big(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(28usize, 8usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_big(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(28usize, 8usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_bif2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(29usize, 9usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_bif2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(29usize, 9usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_big2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(30usize, 9usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_big2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(30usize, 9usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_bip2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(31usize, 28usize, 14usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_bip2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(31usize, 28usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_bip1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(32usize, 23usize, 13usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_bip1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(32usize, 23usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_an22(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(33usize, 32usize, 18usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_an22(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(33usize, 32usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_an21(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(34usize, 23usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_an21(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(34usize, 23usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_an20(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(35usize, 15usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_an20(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(35usize, 15usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_aph2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(36usize, 31usize, 16usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_aph2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(36usize, 31usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_aph1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(37usize, 21usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_aph1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(37usize, 21usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_airy_der_aph0(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(38usize, 14usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_airy_der_aph0(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(38usize, 14usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_I0_bi0(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(39usize, 11usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_I0_bi0(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(39usize, 11usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_I0_ai0(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(40usize, 20usize, 13usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_I0_ai0(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(40usize, 20usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_I0_ai02(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(41usize, 21usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_I0_ai02(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(41usize, 21usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_I1_bi1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(42usize, 10usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_I1_bi1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(42usize, 10usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_I1_ai1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(43usize, 20usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_I1_ai1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(43usize, 20usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_I1_ai12(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(44usize, 21usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_I1_ai12(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(44usize, 21usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_K0_ak0(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(45usize, 23usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_K0_ak0(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(45usize, 23usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_K0_ak02(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(46usize, 13usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_K0_ak02(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(46usize, 13usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_K1_ak1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(47usize, 24usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_K1_ak1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(47usize, 24usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_K1_ak12(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(48usize, 13usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_K1_ak12(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(48usize, 13usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_zeta_zeta_xlt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(49usize, 13usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_zeta_zeta_xlt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(49usize, 13usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_zeta_zeta_xgt1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(50usize, 29usize, 17usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_zeta_zeta_xgt1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(50usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_zeta_zetam1_inter(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(51usize, 22usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_zeta_zetam1_inter(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(51usize, 22usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

// gsl_poly_eval of bessel_K0_k0_poly
fn pv_bessel_K0_k0_poly(x: f64) -> f64 {
    ret 1.1593151565841244842077226e-01f64 + x * (2.7898287891460317300886539e-01f64 + x * (2.5248929932161220559969776e-02f64 + x * (8.4603509072136578707676406e-04f64 + x * (1.4914719243067801775856150e-05f64 + x * (1.6271068931224552553548933e-07f64 + x * (1.2082660336282566759313543e-09f64 + x * (6.6117104672254184399933971e-12f64)))))))
}

// gsl_poly_eval of bessel_K0_i0_poly
fn pv_bessel_K0_i0_poly(x: f64) -> f64 {
    ret 1.0000000000000000044974165e+00f64 + x * (2.4999999999999822316775454e-01f64 + x * (2.7777777777892149148858521e-02f64 + x * (1.7361111083544590676709592e-03f64 + x * (6.9444476047072424198677755e-05f64 + x * (1.9288265756466775034067979e-06f64 + x * (3.9908220583262192851839992e-08f64))))))
}

// gsl_poly_eval of bessel_K1_k1_poly
fn pv_bessel_K1_k1_poly(x: f64) -> f64 {
    ret -3.0796575782920622440538935e-01f64 + x * (-8.5370719728650778045782736e-02f64 + x * (-4.6421827664715603298154971e-03f64 + x * (-1.1253607036630425931072996e-04f64 + x * (-1.5592887702110907110292728e-06f64 + x * (-1.4030163679125934402498239e-08f64 + x * (-8.8718998640336832196558868e-11f64 + x * (-4.1614323580221539328960335e-13f64 + x * (-1.5261293392975541707230366e-15f64))))))))
}

// gsl_poly_eval of bessel_K1_i1_poly
fn pv_bessel_K1_i1_poly(x: f64) -> f64 {
    ret 8.3333333333333325191635191e-02f64 + x * (6.9444444444467956461838830e-03f64 + x * (3.4722222211230452695165215e-04f64 + x * (1.1574075952009842696580084e-05f64 + x * (2.7555870002088181016676934e-07f64 + x * (4.9724386164128529514040614e-09f64)))))
}

// gsl_poly_eval of zeta_hzeta_c
fn pv_zeta_hzeta_c(x: f64) -> f64 {
    ret 1.00000000000000000000000000000f64 + x * (0.083333333333333333333333333333f64 + x * (-0.00138888888888888888888888888889f64 + x * (0.000033068783068783068783068783069f64 + x * (-8.2671957671957671957671957672e-07f64 + x * (2.0876756987868098979210090321e-08f64 + x * (-5.2841901386874931848476822022e-10f64 + x * (1.3382536530684678832826980975e-11f64 + x * (-3.3896802963225828668301953912e-13f64 + x * (8.5860620562778445641359054504e-15f64 + x * (-2.1748686985580618730415164239e-16f64 + x * (5.5090028283602295152026526089e-18f64 + x * (-1.3954464685812523340707686264e-19f64 + x * (3.5347070396294674716932299778e-21f64 + x * (-8.9535174270375468504026113181e-23f64))))))))))))))
}

