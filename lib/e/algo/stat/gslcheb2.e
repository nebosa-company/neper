// Chebyshev coefficient tables of gsl 2.7.1 (specfunc/trig, log, fermi_dirac, synchrotron, transport, bessel_temme, gamma.c), generated from its source by a script, with gsl's cheb_eval_e and cheb_eval_mode_e.
// cheb_eval(id, order, a, b, x) returns (value, error): error = eps * sum |terms| + |c[order]|; cheb_eval_mode(id, order, order_sp, a, b, x, mode) is the mode form: error = eps |value| + |c[order used]|.

use e.math

fn tid_trig_sinc() -> usize { ret 0usize }
fn tord_trig_sinc() -> usize { ret 16usize }
fn tsp_trig_sinc() -> usize { ret 10usize }
fn ta_trig_sinc() -> f64 { ret -1.0f64 }
fn tb_trig_sinc() -> f64 { ret 1.0f64 }
fn tid_trig_sin() -> usize { ret 1usize }
fn tord_trig_sin() -> usize { ret 11usize }
fn tsp_trig_sin() -> usize { ret 11usize }
fn ta_trig_sin() -> f64 { ret -1.0f64 }
fn tb_trig_sin() -> f64 { ret 1.0f64 }
fn tid_trig_cos() -> usize { ret 2usize }
fn tord_trig_cos() -> usize { ret 10usize }
fn tsp_trig_cos() -> usize { ret 10usize }
fn ta_trig_cos() -> f64 { ret -1.0f64 }
fn tb_trig_cos() -> f64 { ret 1.0f64 }
fn tid_log_lopx() -> usize { ret 3usize }
fn tord_log_lopx() -> usize { ret 20usize }
fn tsp_log_lopx() -> usize { ret 10usize }
fn ta_log_lopx() -> f64 { ret -1.0f64 }
fn tb_log_lopx() -> f64 { ret 1.0f64 }
fn tid_log_lopxmx() -> usize { ret 4usize }
fn tord_log_lopxmx() -> usize { ret 19usize }
fn tsp_log_lopxmx() -> usize { ret 9usize }
fn ta_log_lopxmx() -> f64 { ret -1.0f64 }
fn tb_log_lopxmx() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_1_a() -> usize { ret 5usize }
fn tord_fermi_dirac_fd_1_a() -> usize { ret 21usize }
fn tsp_fermi_dirac_fd_1_a() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_1_a() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_1_a() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_1_b() -> usize { ret 6usize }
fn tord_fermi_dirac_fd_1_b() -> usize { ret 21usize }
fn tsp_fermi_dirac_fd_1_b() -> usize { ret 11usize }
fn ta_fermi_dirac_fd_1_b() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_1_b() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_1_c() -> usize { ret 7usize }
fn tord_fermi_dirac_fd_1_c() -> usize { ret 22usize }
fn tsp_fermi_dirac_fd_1_c() -> usize { ret 13usize }
fn ta_fermi_dirac_fd_1_c() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_1_c() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_1_d() -> usize { ret 8usize }
fn tord_fermi_dirac_fd_1_d() -> usize { ret 29usize }
fn tsp_fermi_dirac_fd_1_d() -> usize { ret 14usize }
fn ta_fermi_dirac_fd_1_d() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_1_d() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_1_e() -> usize { ret 9usize }
fn tord_fermi_dirac_fd_1_e() -> usize { ret 9usize }
fn tsp_fermi_dirac_fd_1_e() -> usize { ret 4usize }
fn ta_fermi_dirac_fd_1_e() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_1_e() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_2_a() -> usize { ret 10usize }
fn tord_fermi_dirac_fd_2_a() -> usize { ret 20usize }
fn tsp_fermi_dirac_fd_2_a() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_2_a() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_2_a() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_2_b() -> usize { ret 11usize }
fn tord_fermi_dirac_fd_2_b() -> usize { ret 21usize }
fn tsp_fermi_dirac_fd_2_b() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_2_b() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_2_b() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_2_c() -> usize { ret 12usize }
fn tord_fermi_dirac_fd_2_c() -> usize { ret 19usize }
fn tsp_fermi_dirac_fd_2_c() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_2_c() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_2_c() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_2_d() -> usize { ret 13usize }
fn tord_fermi_dirac_fd_2_d() -> usize { ret 29usize }
fn tsp_fermi_dirac_fd_2_d() -> usize { ret 14usize }
fn ta_fermi_dirac_fd_2_d() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_2_d() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_2_e() -> usize { ret 14usize }
fn tord_fermi_dirac_fd_2_e() -> usize { ret 3usize }
fn tsp_fermi_dirac_fd_2_e() -> usize { ret 3usize }
fn ta_fermi_dirac_fd_2_e() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_2_e() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_mhalf_a() -> usize { ret 15usize }
fn tord_fermi_dirac_fd_mhalf_a() -> usize { ret 19usize }
fn tsp_fermi_dirac_fd_mhalf_a() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_mhalf_a() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_mhalf_a() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_mhalf_b() -> usize { ret 16usize }
fn tord_fermi_dirac_fd_mhalf_b() -> usize { ret 19usize }
fn tsp_fermi_dirac_fd_mhalf_b() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_mhalf_b() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_mhalf_b() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_mhalf_c() -> usize { ret 17usize }
fn tord_fermi_dirac_fd_mhalf_c() -> usize { ret 24usize }
fn tsp_fermi_dirac_fd_mhalf_c() -> usize { ret 13usize }
fn ta_fermi_dirac_fd_mhalf_c() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_mhalf_c() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_mhalf_d() -> usize { ret 18usize }
fn tord_fermi_dirac_fd_mhalf_d() -> usize { ret 29usize }
fn tsp_fermi_dirac_fd_mhalf_d() -> usize { ret 15usize }
fn ta_fermi_dirac_fd_mhalf_d() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_mhalf_d() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_half_a() -> usize { ret 19usize }
fn tord_fermi_dirac_fd_half_a() -> usize { ret 22usize }
fn tsp_fermi_dirac_fd_half_a() -> usize { ret 11usize }
fn ta_fermi_dirac_fd_half_a() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_half_a() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_half_b() -> usize { ret 20usize }
fn tord_fermi_dirac_fd_half_b() -> usize { ret 19usize }
fn tsp_fermi_dirac_fd_half_b() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_half_b() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_half_b() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_half_c() -> usize { ret 21usize }
fn tord_fermi_dirac_fd_half_c() -> usize { ret 22usize }
fn tsp_fermi_dirac_fd_half_c() -> usize { ret 13usize }
fn ta_fermi_dirac_fd_half_c() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_half_c() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_half_d() -> usize { ret 22usize }
fn tord_fermi_dirac_fd_half_d() -> usize { ret 29usize }
fn tsp_fermi_dirac_fd_half_d() -> usize { ret 15usize }
fn ta_fermi_dirac_fd_half_d() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_half_d() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_3half_a() -> usize { ret 23usize }
fn tord_fermi_dirac_fd_3half_a() -> usize { ret 19usize }
fn tsp_fermi_dirac_fd_3half_a() -> usize { ret 11usize }
fn ta_fermi_dirac_fd_3half_a() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_3half_a() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_3half_b() -> usize { ret 24usize }
fn tord_fermi_dirac_fd_3half_b() -> usize { ret 21usize }
fn tsp_fermi_dirac_fd_3half_b() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_3half_b() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_3half_b() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_3half_c() -> usize { ret 25usize }
fn tord_fermi_dirac_fd_3half_c() -> usize { ret 20usize }
fn tsp_fermi_dirac_fd_3half_c() -> usize { ret 12usize }
fn ta_fermi_dirac_fd_3half_c() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_3half_c() -> f64 { ret 1.0f64 }
fn tid_fermi_dirac_fd_3half_d() -> usize { ret 26usize }
fn tord_fermi_dirac_fd_3half_d() -> usize { ret 24usize }
fn tsp_fermi_dirac_fd_3half_d() -> usize { ret 16usize }
fn ta_fermi_dirac_fd_3half_d() -> f64 { ret -1.0f64 }
fn tb_fermi_dirac_fd_3half_d() -> f64 { ret 1.0f64 }
fn tid_synchrotron_synchrotron1() -> usize { ret 27usize }
fn tord_synchrotron_synchrotron1() -> usize { ret 12usize }
fn tsp_synchrotron_synchrotron1() -> usize { ret 9usize }
fn ta_synchrotron_synchrotron1() -> f64 { ret -1.0f64 }
fn tb_synchrotron_synchrotron1() -> f64 { ret 1.0f64 }
fn tid_synchrotron_synchrotron2() -> usize { ret 28usize }
fn tord_synchrotron_synchrotron2() -> usize { ret 11usize }
fn tsp_synchrotron_synchrotron2() -> usize { ret 7usize }
fn ta_synchrotron_synchrotron2() -> f64 { ret -1.0f64 }
fn tb_synchrotron_synchrotron2() -> f64 { ret 1.0f64 }
fn tid_synchrotron_synchrotron1a() -> usize { ret 29usize }
fn tord_synchrotron_synchrotron1a() -> usize { ret 22usize }
fn tsp_synchrotron_synchrotron1a() -> usize { ret 11usize }
fn ta_synchrotron_synchrotron1a() -> f64 { ret -1.0f64 }
fn tb_synchrotron_synchrotron1a() -> f64 { ret 1.0f64 }
fn tid_synchrotron_synchrotron21() -> usize { ret 30usize }
fn tord_synchrotron_synchrotron21() -> usize { ret 12usize }
fn tsp_synchrotron_synchrotron21() -> usize { ret 9usize }
fn ta_synchrotron_synchrotron21() -> f64 { ret -1.0f64 }
fn tb_synchrotron_synchrotron21() -> f64 { ret 1.0f64 }
fn tid_synchrotron_synchrotron22() -> usize { ret 31usize }
fn tord_synchrotron_synchrotron22() -> usize { ret 12usize }
fn tsp_synchrotron_synchrotron22() -> usize { ret 8usize }
fn ta_synchrotron_synchrotron22() -> f64 { ret -1.0f64 }
fn tb_synchrotron_synchrotron22() -> f64 { ret 1.0f64 }
fn tid_synchrotron_synchrotron2a() -> usize { ret 32usize }
fn tord_synchrotron_synchrotron2a() -> usize { ret 16usize }
fn tsp_synchrotron_synchrotron2a() -> usize { ret 8usize }
fn ta_synchrotron_synchrotron2a() -> f64 { ret -1.0f64 }
fn tb_synchrotron_synchrotron2a() -> f64 { ret 1.0f64 }
fn tid_transport_transport2() -> usize { ret 33usize }
fn tord_transport_transport2() -> usize { ret 17usize }
fn tsp_transport_transport2() -> usize { ret 9usize }
fn ta_transport_transport2() -> f64 { ret -1.0f64 }
fn tb_transport_transport2() -> f64 { ret 1.0f64 }
fn tid_transport_transport3() -> usize { ret 34usize }
fn tord_transport_transport3() -> usize { ret 17usize }
fn tsp_transport_transport3() -> usize { ret 9usize }
fn ta_transport_transport3() -> f64 { ret -1.0f64 }
fn tb_transport_transport3() -> f64 { ret 1.0f64 }
fn tid_transport_transport4() -> usize { ret 35usize }
fn tord_transport_transport4() -> usize { ret 17usize }
fn tsp_transport_transport4() -> usize { ret 9usize }
fn ta_transport_transport4() -> f64 { ret -1.0f64 }
fn tb_transport_transport4() -> f64 { ret 1.0f64 }
fn tid_transport_transport5() -> usize { ret 36usize }
fn tord_transport_transport5() -> usize { ret 17usize }
fn tsp_transport_transport5() -> usize { ret 9usize }
fn ta_transport_transport5() -> f64 { ret -1.0f64 }
fn tb_transport_transport5() -> f64 { ret 1.0f64 }
fn tid_bessel_temme_g1() -> usize { ret 37usize }
fn tord_bessel_temme_g1() -> usize { ret 13usize }
fn tsp_bessel_temme_g1() -> usize { ret 7usize }
fn ta_bessel_temme_g1() -> f64 { ret -1.0f64 }
fn tb_bessel_temme_g1() -> f64 { ret 1.0f64 }
fn tid_bessel_temme_g2() -> usize { ret 38usize }
fn tord_bessel_temme_g2() -> usize { ret 14usize }
fn tsp_bessel_temme_g2() -> usize { ret 8usize }
fn ta_bessel_temme_g2() -> f64 { ret -1.0f64 }
fn tb_bessel_temme_g2() -> f64 { ret 1.0f64 }
fn tid_gamma_gstar_a() -> usize { ret 39usize }
fn tord_gamma_gstar_a() -> usize { ret 29usize }
fn tsp_gamma_gstar_a() -> usize { ret 17usize }
fn ta_gamma_gstar_a() -> f64 { ret -1.0f64 }
fn tb_gamma_gstar_a() -> f64 { ret 1.0f64 }
fn tid_gamma_gstar_b() -> usize { ret 40usize }
fn tord_gamma_gstar_b() -> usize { ret 29usize }
fn tsp_gamma_gstar_b() -> usize { ret 18usize }
fn ta_gamma_gstar_b() -> f64 { ret -1.0f64 }
fn tb_gamma_gstar_b() -> f64 { ret 1.0f64 }
fn tid_gamma_gamma_5_10() -> usize { ret 41usize }
fn tord_gamma_gamma_5_10() -> usize { ret 23usize }
fn tsp_gamma_gamma_5_10() -> usize { ret 11usize }
fn ta_gamma_gamma_5_10() -> f64 { ret -1.0f64 }
fn tb_gamma_gamma_5_10() -> f64 { ret 1.0f64 }

fn ctab(id: usize, k: usize) -> f64 {
    if id == 0usize {
        if k == 0usize { ret 1.133648177811747875422f64 }
        if k == 1usize { ret -0.532677564732557348781f64 }
        if k == 2usize { ret -0.068293048346633177859f64 }
        if k == 3usize { ret 0.033403684226353715020f64 }
        if k == 4usize { ret 0.001485679893925747818f64 }
        if k == 5usize { ret -0.000734421305768455295f64 }
        if k == 6usize { ret -0.000016837282388837229f64 }
        if k == 7usize { ret 0.000008359950146618018f64 }
        if k == 8usize { ret 0.000000117382095601192f64 }
        if k == 9usize { ret -0.000000058413665922724f64 }
        if k == 10usize { ret -0.000000000554763755743f64 }
        if k == 11usize { ret 0.000000000276434190426f64 }
        if k == 12usize { ret 0.000000000001895374892f64 }
        if k == 13usize { ret -0.000000000000945237101f64 }
        if k == 14usize { ret -0.000000000000004900690f64 }
        if k == 15usize { ret 0.000000000000002445383f64 }
        if k == 16usize { ret 0.000000000000000009925f64 }
    }
    if id == 1usize {
        if k == 0usize { ret -0.3295190160663511504173f64 }
        if k == 1usize { ret 0.0025374284671667991990f64 }
        if k == 2usize { ret 0.0006261928782647355874f64 }
        if k == 3usize { ret -4.6495547521854042157541e-06f64 }
        if k == 4usize { ret -5.6917531549379706526677e-07f64 }
        if k == 5usize { ret 3.7283335140973803627866e-09f64 }
        if k == 6usize { ret 3.0267376484747473727186e-10f64 }
        if k == 7usize { ret -1.7400875016436622322022e-12f64 }
        if k == 8usize { ret -1.0554678305790849834462e-13f64 }
        if k == 9usize { ret 5.3701981409132410797062e-16f64 }
        if k == 10usize { ret 2.5984137983099020336115e-17f64 }
        if k == 11usize { ret -1.1821555255364833468288e-19f64 }
    }
    if id == 2usize {
        if k == 0usize { ret 0.165391825637921473505668118136f64 }
        if k == 1usize { ret -0.00084852883845000173671196530195f64 }
        if k == 2usize { ret -0.000210086507222940730213625768083f64 }
        if k == 3usize { ret 1.16582269619760204299639757584e-6f64 }
        if k == 4usize { ret 1.43319375856259870334412701165e-7f64 }
        if k == 5usize { ret -7.4770883429007141617951330184e-10f64 }
        if k == 6usize { ret -6.0969994944584252706997438007e-11f64 }
        if k == 7usize { ret 2.90748249201909353949854872638e-13f64 }
        if k == 8usize { ret 1.77126739876261435667156490461e-14f64 }
        if k == 9usize { ret -7.6896421502815579078577263149e-17f64 }
        if k == 10usize { ret -3.7363121133079412079201377318e-18f64 }
    }
    if id == 3usize {
        if k == 0usize { ret 2.16647910664395270521272590407f64 }
        if k == 1usize { ret -0.28565398551049742084877469679f64 }
        if k == 2usize { ret 0.01517767255690553732382488171f64 }
        if k == 3usize { ret -0.00200215904941415466274422081f64 }
        if k == 4usize { ret 0.00019211375164056698287947962f64 }
        if k == 5usize { ret -0.00002553258886105542567601400f64 }
        if k == 6usize { ret 2.9004512660400621301999384544e-06f64 }
        if k == 7usize { ret -3.8873813517057343800270917900e-07f64 }
        if k == 8usize { ret 4.7743678729400456026672697926e-08f64 }
        if k == 9usize { ret -6.4501969776090319441714445454e-09f64 }
        if k == 10usize { ret 8.2751976628812389601561347296e-10f64 }
        if k == 11usize { ret -1.1260499376492049411710290413e-10f64 }
        if k == 12usize { ret 1.4844576692270934446023686322e-11f64 }
        if k == 13usize { ret -2.0328515972462118942821556033e-12f64 }
        if k == 14usize { ret 2.7291231220549214896095654769e-13f64 }
        if k == 15usize { ret -3.7581977830387938294437434651e-14f64 }
        if k == 16usize { ret 5.1107345870861673561462339876e-15f64 }
        if k == 17usize { ret -7.0722150011433276578323272272e-16f64 }
        if k == 18usize { ret 9.7089758328248469219003866867e-17f64 }
        if k == 19usize { ret -1.3492637457521938883731579510e-17f64 }
        if k == 20usize { ret 1.8657327910677296608121390705e-18f64 }
    }
    if id == 4usize {
        if k == 0usize { ret -1.12100231323744103373737274541f64 }
        if k == 1usize { ret 0.19553462773379386241549597019f64 }
        if k == 2usize { ret -0.01467470453808083971825344956f64 }
        if k == 3usize { ret 0.00166678250474365477643629067f64 }
        if k == 4usize { ret -0.00018543356147700369785746902f64 }
        if k == 5usize { ret 0.00002280154021771635036301071f64 }
        if k == 6usize { ret -2.8031253116633521699214134172e-06f64 }
        if k == 7usize { ret 3.5936568872522162983669541401e-07f64 }
        if k == 8usize { ret -4.6241857041062060284381167925e-08f64 }
        if k == 9usize { ret 6.0822637459403991012451054971e-09f64 }
        if k == 10usize { ret -8.0339824424815790302621320732e-10f64 }
        if k == 11usize { ret 1.0751718277499375044851551587e-10f64 }
        if k == 12usize { ret -1.4445310914224613448759230882e-11f64 }
        if k == 13usize { ret 1.9573912180610336168921438426e-12f64 }
        if k == 14usize { ret -2.6614436796793061741564104510e-13f64 }
        if k == 15usize { ret 3.6402634315269586532158344584e-14f64 }
        if k == 16usize { ret -4.9937495922755006545809120531e-15f64 }
        if k == 17usize { ret 6.8802890218846809524646902703e-16f64 }
        if k == 18usize { ret -9.5034129794804273611403251480e-17f64 }
        if k == 19usize { ret 1.3170135013050997157326965813e-17f64 }
    }
    if id == 5usize {
        if k == 0usize { ret 1.8949340668482264365f64 }
        if k == 1usize { ret 0.7237719066890052793f64 }
        if k == 2usize { ret 0.1250000000000000000f64 }
        if k == 3usize { ret 0.0101065196435973942f64 }
        if k == 4usize { ret 0.0f64 }
        if k == 5usize { ret -0.0000600615242174119f64 }
        if k == 6usize { ret 0.0f64 }
        if k == 7usize { ret 6.816528764623e-7f64 }
        if k == 8usize { ret 0.0f64 }
        if k == 9usize { ret -9.5895779195e-9f64 }
        if k == 10usize { ret 0.0f64 }
        if k == 11usize { ret 1.515104135e-10f64 }
        if k == 12usize { ret 0.0f64 }
        if k == 13usize { ret -2.5785616e-12f64 }
        if k == 14usize { ret 0.0f64 }
        if k == 15usize { ret 4.62270e-14f64 }
        if k == 16usize { ret 0.0f64 }
        if k == 17usize { ret -8.612e-16f64 }
        if k == 18usize { ret 0.0f64 }
        if k == 19usize { ret 1.65e-17f64 }
        if k == 20usize { ret 0.0f64 }
        if k == 21usize { ret -3.0e-19f64 }
    }
    if id == 6usize {
        if k == 0usize { ret 10.409136795234611872f64 }
        if k == 1usize { ret 3.899445098225161947f64 }
        if k == 2usize { ret 0.513510935510521222f64 }
        if k == 3usize { ret 0.010618736770218426f64 }
        if k == 4usize { ret -0.001584468020659694f64 }
        if k == 5usize { ret 0.000146139297161640f64 }
        if k == 6usize { ret -1.408095734499e-6f64 }
        if k == 7usize { ret -2.177993899484e-6f64 }
        if k == 8usize { ret 3.91423660640e-7f64 }
        if k == 9usize { ret -2.3860262660e-8f64 }
        if k == 10usize { ret -4.138309573e-9f64 }
        if k == 11usize { ret 1.283965236e-9f64 }
        if k == 12usize { ret -1.39695990e-10f64 }
        if k == 13usize { ret -4.907743e-12f64 }
        if k == 14usize { ret 4.399878e-12f64 }
        if k == 15usize { ret -7.17291e-13f64 }
        if k == 16usize { ret 2.4320e-14f64 }
        if k == 17usize { ret 1.4230e-14f64 }
        if k == 18usize { ret -3.446e-15f64 }
        if k == 19usize { ret 2.93e-16f64 }
        if k == 20usize { ret 3.7e-17f64 }
        if k == 21usize { ret -1.6e-17f64 }
    }
    if id == 7usize {
        if k == 0usize { ret 56.78099449124299762f64 }
        if k == 1usize { ret 21.00718468237668011f64 }
        if k == 2usize { ret 2.24592457063193457f64 }
        if k == 3usize { ret 0.00173793640425994f64 }
        if k == 4usize { ret -0.00058716468739423f64 }
        if k == 5usize { ret 0.00016306958492437f64 }
        if k == 6usize { ret -0.00003817425583020f64 }
        if k == 7usize { ret 7.64527252009e-6f64 }
        if k == 8usize { ret -1.31348500162e-6f64 }
        if k == 9usize { ret 1.9000646056e-7f64 }
        if k == 10usize { ret -2.141328223e-8f64 }
        if k == 11usize { ret 1.23906372e-9f64 }
        if k == 12usize { ret 2.1848049e-10f64 }
        if k == 13usize { ret -1.0134282e-10f64 }
        if k == 14usize { ret 2.484728e-11f64 }
        if k == 15usize { ret -4.73067e-12f64 }
        if k == 16usize { ret 7.3555e-13f64 }
        if k == 17usize { ret -8.740e-14f64 }
        if k == 18usize { ret 4.85e-15f64 }
        if k == 19usize { ret 1.23e-15f64 }
        if k == 20usize { ret -5.6e-16f64 }
        if k == 21usize { ret 1.4e-16f64 }
        if k == 22usize { ret -3.0e-17f64 }
    }
    if id == 8usize {
        if k == 0usize { ret 1.0126626021151374442f64 }
        if k == 1usize { ret -0.0063312525536433793f64 }
        if k == 2usize { ret 0.0024837319237084326f64 }
        if k == 3usize { ret -0.0008764333697726109f64 }
        if k == 4usize { ret 0.0002913344438921266f64 }
        if k == 5usize { ret -0.0000931877907705692f64 }
        if k == 6usize { ret 0.0000290151342040275f64 }
        if k == 7usize { ret -8.8548707259955e-6f64 }
        if k == 8usize { ret 2.6603474114517e-6f64 }
        if k == 9usize { ret -7.891415690452e-7f64 }
        if k == 10usize { ret 2.315730237195e-7f64 }
        if k == 11usize { ret -6.73179452963e-8f64 }
        if k == 12usize { ret 1.94048035606e-8f64 }
        if k == 13usize { ret -5.5507129189e-9f64 }
        if k == 14usize { ret 1.5766090896e-9f64 }
        if k == 15usize { ret -4.449310875e-10f64 }
        if k == 16usize { ret 1.248292745e-10f64 }
        if k == 17usize { ret -3.48392894e-11f64 }
        if k == 18usize { ret 9.6791550e-12f64 }
        if k == 19usize { ret -2.6786240e-12f64 }
        if k == 20usize { ret 7.388852e-13f64 }
        if k == 21usize { ret -2.032828e-13f64 }
        if k == 22usize { ret 5.58115e-14f64 }
        if k == 23usize { ret -1.52987e-14f64 }
        if k == 24usize { ret 4.1886e-15f64 }
        if k == 25usize { ret -1.1458e-15f64 }
        if k == 26usize { ret 3.132e-16f64 }
        if k == 27usize { ret -8.56e-17f64 }
        if k == 28usize { ret 2.33e-17f64 }
        if k == 29usize { ret -5.9e-18f64 }
    }
    if id == 9usize {
        if k == 0usize { ret 1.0013707783890401683f64 }
        if k == 1usize { ret 0.0009138522593601060f64 }
        if k == 2usize { ret 0.0002284630648400133f64 }
        if k == 3usize { ret -1.57e-17f64 }
        if k == 4usize { ret -1.27e-17f64 }
        if k == 5usize { ret -9.7e-18f64 }
        if k == 6usize { ret -6.9e-18f64 }
        if k == 7usize { ret -4.6e-18f64 }
        if k == 8usize { ret -2.9e-18f64 }
        if k == 9usize { ret -1.7e-18f64 }
    }
    if id == 10usize {
        if k == 0usize { ret 2.1573661917148458336f64 }
        if k == 1usize { ret 0.8849670334241132182f64 }
        if k == 2usize { ret 0.1784163467613519713f64 }
        if k == 3usize { ret 0.0208333333333333333f64 }
        if k == 4usize { ret 0.0012708226459768508f64 }
        if k == 5usize { ret 0.0f64 }
        if k == 6usize { ret -5.0619314244895e-6f64 }
        if k == 7usize { ret 0.0f64 }
        if k == 8usize { ret 4.32026533989e-8f64 }
        if k == 9usize { ret 0.0f64 }
        if k == 10usize { ret -4.870544166e-10f64 }
        if k == 11usize { ret 0.0f64 }
        if k == 12usize { ret 6.4203740e-12f64 }
        if k == 13usize { ret 0.0f64 }
        if k == 14usize { ret -9.37424e-14f64 }
        if k == 15usize { ret 0.0f64 }
        if k == 16usize { ret 1.4715e-15f64 }
        if k == 17usize { ret 0.0f64 }
        if k == 18usize { ret -2.44e-17f64 }
        if k == 19usize { ret 0.0f64 }
        if k == 20usize { ret 4.0e-19f64 }
    }
    if id == 11usize {
        if k == 0usize { ret 16.508258811798623599f64 }
        if k == 1usize { ret 7.421719394793067988f64 }
        if k == 2usize { ret 1.458309885545603821f64 }
        if k == 3usize { ret 0.128773850882795229f64 }
        if k == 4usize { ret 0.001963612026198147f64 }
        if k == 5usize { ret -0.000237458988738779f64 }
        if k == 6usize { ret 0.000018539661382641f64 }
        if k == 7usize { ret -1.92805649479e-7f64 }
        if k == 8usize { ret -2.01950028452e-7f64 }
        if k == 9usize { ret 3.2963497518e-8f64 }
        if k == 10usize { ret -1.885817092e-9f64 }
        if k == 11usize { ret -2.72632744e-10f64 }
        if k == 12usize { ret 8.0554561e-11f64 }
        if k == 13usize { ret -8.313223e-12f64 }
        if k == 14usize { ret -2.24489e-13f64 }
        if k == 15usize { ret 2.18778e-13f64 }
        if k == 16usize { ret -3.4290e-14f64 }
        if k == 17usize { ret 1.225e-15f64 }
        if k == 18usize { ret 5.81e-16f64 }
        if k == 19usize { ret -1.37e-16f64 }
        if k == 20usize { ret 1.2e-17f64 }
        if k == 21usize { ret 1.0e-18f64 }
    }
    if id == 12usize {
        if k == 0usize { ret 168.87129776686440711f64 }
        if k == 1usize { ret 81.80260488091659458f64 }
        if k == 2usize { ret 15.75408505947931513f64 }
        if k == 3usize { ret 1.12325586765966440f64 }
        if k == 4usize { ret 0.00059057505725084f64 }
        if k == 5usize { ret -0.00016469712946921f64 }
        if k == 6usize { ret 0.00003885607810107f64 }
        if k == 7usize { ret -7.89873660613e-6f64 }
        if k == 8usize { ret 1.39786238616e-6f64 }
        if k == 9usize { ret -2.1534528656e-7f64 }
        if k == 10usize { ret 2.831510953e-8f64 }
        if k == 11usize { ret -2.94978583e-9f64 }
        if k == 12usize { ret 1.6755082e-10f64 }
        if k == 13usize { ret 2.234229e-11f64 }
        if k == 14usize { ret -1.035130e-11f64 }
        if k == 15usize { ret 2.41117e-12f64 }
        if k == 16usize { ret -4.3531e-13f64 }
        if k == 17usize { ret 6.447e-14f64 }
        if k == 18usize { ret -7.39e-15f64 }
        if k == 19usize { ret 4.3e-16f64 }
    }
    if id == 13usize {
        if k == 0usize { ret 0.3459960518965277589f64 }
        if k == 1usize { ret -0.00633136397691958024f64 }
        if k == 2usize { ret 0.00248382959047594408f64 }
        if k == 3usize { ret -0.00087651191884005114f64 }
        if k == 4usize { ret 0.00029139255351719932f64 }
        if k == 5usize { ret -0.00009322746111846199f64 }
        if k == 6usize { ret 0.00002904021914564786f64 }
        if k == 7usize { ret -8.86962264810663e-6f64 }
        if k == 8usize { ret 2.66844972574613e-6f64 }
        if k == 9usize { ret -7.9331564996004e-7f64 }
        if k == 10usize { ret 2.3359868615516e-7f64 }
        if k == 11usize { ret -6.824790880436e-8f64 }
        if k == 12usize { ret 1.981036528154e-8f64 }
        if k == 13usize { ret -5.71940426300e-9f64 }
        if k == 14usize { ret 1.64379426579e-9f64 }
        if k == 15usize { ret -4.7064937566e-10f64 }
        if k == 16usize { ret 1.3432614122e-10f64 }
        if k == 17usize { ret -3.823400534e-11f64 }
        if k == 18usize { ret 1.085771994e-11f64 }
        if k == 19usize { ret -3.07727465e-12f64 }
        if k == 20usize { ret 8.7064848e-13f64 }
        if k == 21usize { ret -2.4595431e-13f64 }
        if k == 22usize { ret 6.938531e-14f64 }
        if k == 23usize { ret -1.954939e-14f64 }
        if k == 24usize { ret 5.50162e-15f64 }
        if k == 25usize { ret -1.54657e-15f64 }
        if k == 26usize { ret 4.3429e-16f64 }
        if k == 27usize { ret -1.2178e-16f64 }
        if k == 28usize { ret 3.394e-17f64 }
        if k == 29usize { ret -8.81e-18f64 }
    }
    if id == 14usize {
        if k == 0usize { ret 0.3347041117223735227f64 }
        if k == 1usize { ret 0.00091385225936012645f64 }
        if k == 2usize { ret 0.00022846306484003205f64 }
        if k == 3usize { ret 5.2e-19f64 }
    }
    if id == 15usize {
        if k == 0usize { ret 1.2663290042859741974f64 }
        if k == 1usize { ret 0.3697876251911153071f64 }
        if k == 2usize { ret 0.0278131011214405055f64 }
        if k == 3usize { ret -0.0033332848565672007f64 }
        if k == 4usize { ret -0.0004438108265412038f64 }
        if k == 5usize { ret 0.0000616495177243839f64 }
        if k == 6usize { ret 8.7589611449897e-6f64 }
        if k == 7usize { ret -1.2622936986172e-6f64 }
        if k == 8usize { ret -1.837464037221e-7f64 }
        if k == 9usize { ret 2.69495091400e-8f64 }
        if k == 10usize { ret 3.9760866257e-9f64 }
        if k == 11usize { ret -5.894468795e-10f64 }
        if k == 12usize { ret -8.77321638e-11f64 }
        if k == 13usize { ret 1.31016571e-11f64 }
        if k == 14usize { ret 1.9621619e-12f64 }
        if k == 15usize { ret -2.945887e-13f64 }
        if k == 16usize { ret -4.43234e-14f64 }
        if k == 17usize { ret 6.6816e-15f64 }
        if k == 18usize { ret 1.0084e-15f64 }
        if k == 19usize { ret -1.561e-16f64 }
    }
    if id == 16usize {
        if k == 0usize { ret 3.270796131942071484f64 }
        if k == 1usize { ret 0.5809004935853417887f64 }
        if k == 2usize { ret -0.0299313438794694987f64 }
        if k == 3usize { ret -0.0013287935412612198f64 }
        if k == 4usize { ret 0.0009910221228704198f64 }
        if k == 5usize { ret -0.0001690954939688554f64 }
        if k == 6usize { ret 6.5955849946915e-6f64 }
        if k == 7usize { ret 3.5953966033618e-6f64 }
        if k == 8usize { ret -9.430672023181e-7f64 }
        if k == 9usize { ret 8.75773958291e-8f64 }
        if k == 10usize { ret 1.06247652607e-8f64 }
        if k == 11usize { ret -4.9587006215e-9f64 }
        if k == 12usize { ret 7.160432795e-10f64 }
        if k == 13usize { ret 4.5072219e-12f64 }
        if k == 14usize { ret -2.3695425e-11f64 }
        if k == 15usize { ret 4.9122208e-12f64 }
        if k == 16usize { ret -2.905277e-13f64 }
        if k == 17usize { ret -9.59291e-14f64 }
        if k == 18usize { ret 3.00028e-14f64 }
        if k == 19usize { ret -3.4970e-15f64 }
    }
    if id == 17usize {
        if k == 0usize { ret 5.828283273430595507f64 }
        if k == 1usize { ret 0.677521118293264655f64 }
        if k == 2usize { ret -0.043946248736481554f64 }
        if k == 3usize { ret 0.005825595781828244f64 }
        if k == 4usize { ret -0.000864858907380668f64 }
        if k == 5usize { ret 0.000110017890076539f64 }
        if k == 6usize { ret -6.973305225404e-6f64 }
        if k == 7usize { ret -1.716267414672e-6f64 }
        if k == 8usize { ret 8.59811582041e-7f64 }
        if k == 9usize { ret -2.33066786976e-7f64 }
        if k == 10usize { ret 4.8503191159e-8f64 }
        if k == 11usize { ret -8.130620247e-9f64 }
        if k == 12usize { ret 1.021068250e-9f64 }
        if k == 13usize { ret -5.3188423e-11f64 }
        if k == 14usize { ret -1.9430559e-11f64 }
        if k == 15usize { ret 8.750506e-12f64 }
        if k == 16usize { ret -2.324897e-12f64 }
        if k == 17usize { ret 4.83102e-13f64 }
        if k == 18usize { ret -8.1207e-14f64 }
        if k == 19usize { ret 1.0132e-14f64 }
        if k == 20usize { ret -4.64e-16f64 }
        if k == 21usize { ret -2.24e-16f64 }
        if k == 22usize { ret 9.7e-17f64 }
        if k == 23usize { ret -2.6e-17f64 }
        if k == 24usize { ret 5.0e-18f64 }
    }
    if id == 18usize {
        if k == 0usize { ret 2.2530744202862438709f64 }
        if k == 1usize { ret 0.0018745152720114692f64 }
        if k == 2usize { ret -0.0007550198497498903f64 }
        if k == 3usize { ret 0.0002759818676644382f64 }
        if k == 4usize { ret -0.0000959406283465913f64 }
        if k == 5usize { ret 0.0000324056855537065f64 }
        if k == 6usize { ret -0.0000107462396145761f64 }
        if k == 7usize { ret 3.5126865219224e-6f64 }
        if k == 8usize { ret -1.1313072730092e-6f64 }
        if k == 9usize { ret 3.577454162766e-7f64 }
        if k == 10usize { ret -1.104926666238e-7f64 }
        if k == 11usize { ret 3.31304165692e-8f64 }
        if k == 12usize { ret -9.5837381008e-9f64 }
        if k == 13usize { ret 2.6575790141e-9f64 }
        if k == 14usize { ret -7.015201447e-10f64 }
        if k == 15usize { ret 1.747111336e-10f64 }
        if k == 16usize { ret -4.04909605e-11f64 }
        if k == 17usize { ret 8.5104999e-12f64 }
        if k == 18usize { ret -1.5261885e-12f64 }
        if k == 19usize { ret 1.876851e-13f64 }
        if k == 20usize { ret 1.00574e-14f64 }
        if k == 21usize { ret -1.82002e-14f64 }
        if k == 22usize { ret 8.6634e-15f64 }
        if k == 23usize { ret -3.2058e-15f64 }
        if k == 24usize { ret 1.0572e-15f64 }
        if k == 25usize { ret -3.259e-16f64 }
        if k == 26usize { ret 9.60e-17f64 }
        if k == 27usize { ret -2.74e-17f64 }
        if k == 28usize { ret 7.6e-18f64 }
        if k == 29usize { ret -1.9e-18f64 }
    }
    if id == 19usize {
        if k == 0usize { ret 1.7177138871306189157f64 }
        if k == 1usize { ret 0.6192579515822668460f64 }
        if k == 2usize { ret 0.0932802275119206269f64 }
        if k == 3usize { ret 0.0047094853246636182f64 }
        if k == 4usize { ret -0.0004243667967864481f64 }
        if k == 5usize { ret -0.0000452569787686193f64 }
        if k == 6usize { ret 5.2426509519168e-6f64 }
        if k == 7usize { ret 6.387648249080e-7f64 }
        if k == 8usize { ret -8.05777004848e-8f64 }
        if k == 9usize { ret -1.04290272415e-8f64 }
        if k == 10usize { ret 1.3769478010e-9f64 }
        if k == 11usize { ret 1.847190359e-10f64 }
        if k == 12usize { ret -2.51061890e-11f64 }
        if k == 13usize { ret -3.4497818e-12f64 }
        if k == 14usize { ret 4.784373e-13f64 }
        if k == 15usize { ret 6.68828e-14f64 }
        if k == 16usize { ret -9.4147e-15f64 }
        if k == 17usize { ret -1.3333e-15f64 }
        if k == 18usize { ret 1.898e-16f64 }
        if k == 19usize { ret 2.72e-17f64 }
        if k == 20usize { ret -3.9e-18f64 }
        if k == 21usize { ret -6.0e-19f64 }
        if k == 22usize { ret 1.0e-19f64 }
    }
    if id == 20usize {
        if k == 0usize { ret 7.651013792074984027f64 }
        if k == 1usize { ret 2.475545606866155737f64 }
        if k == 2usize { ret 0.218335982672476128f64 }
        if k == 3usize { ret -0.007730591500584980f64 }
        if k == 4usize { ret -0.000217443383867318f64 }
        if k == 5usize { ret 0.000147663980681359f64 }
        if k == 6usize { ret -0.000021586361321527f64 }
        if k == 7usize { ret 8.07712735394e-7f64 }
        if k == 8usize { ret 3.28858050706e-7f64 }
        if k == 9usize { ret -7.9474330632e-8f64 }
        if k == 10usize { ret 6.940207234e-9f64 }
        if k == 11usize { ret 6.75594681e-10f64 }
        if k == 12usize { ret -3.10200490e-10f64 }
        if k == 13usize { ret 4.2677233e-11f64 }
        if k == 14usize { ret -2.1696e-14f64 }
        if k == 15usize { ret -1.170245e-12f64 }
        if k == 16usize { ret 2.34757e-13f64 }
        if k == 17usize { ret -1.4139e-14f64 }
        if k == 18usize { ret -3.864e-15f64 }
        if k == 19usize { ret 1.202e-15f64 }
    }
    if id == 21usize {
        if k == 0usize { ret 29.584339348839816528f64 }
        if k == 1usize { ret 8.808344283250615592f64 }
        if k == 2usize { ret 0.503771641883577308f64 }
        if k == 3usize { ret -0.021540694914550443f64 }
        if k == 4usize { ret 0.002143341709406890f64 }
        if k == 5usize { ret -0.000257365680646579f64 }
        if k == 6usize { ret 0.000027933539372803f64 }
        if k == 7usize { ret -1.678525030167e-6f64 }
        if k == 8usize { ret -2.78100117693e-7f64 }
        if k == 9usize { ret 1.35218065147e-7f64 }
        if k == 10usize { ret -3.3740425009e-8f64 }
        if k == 11usize { ret 6.474834942e-9f64 }
        if k == 12usize { ret -1.009678978e-9f64 }
        if k == 13usize { ret 1.20057555e-10f64 }
        if k == 14usize { ret -6.636314e-12f64 }
        if k == 15usize { ret -1.710566e-12f64 }
        if k == 16usize { ret 7.75069e-13f64 }
        if k == 17usize { ret -1.97973e-13f64 }
        if k == 18usize { ret 3.9414e-14f64 }
        if k == 19usize { ret -6.374e-15f64 }
        if k == 20usize { ret 7.77e-16f64 }
        if k == 21usize { ret -4.0e-17f64 }
        if k == 22usize { ret -1.4e-17f64 }
    }
    if id == 22usize {
        if k == 0usize { ret 1.5116909434145508537f64 }
        if k == 1usize { ret -0.0036043405371630468f64 }
        if k == 2usize { ret 0.0014207743256393359f64 }
        if k == 3usize { ret -0.0005045399052400260f64 }
        if k == 4usize { ret 0.0001690758006957347f64 }
        if k == 5usize { ret -0.0000546305872688307f64 }
        if k == 6usize { ret 0.0000172223228484571f64 }
        if k == 7usize { ret -5.3352603788706e-6f64 }
        if k == 8usize { ret 1.6315287543662e-6f64 }
        if k == 9usize { ret -4.939021084898e-7f64 }
        if k == 10usize { ret 1.482515450316e-7f64 }
        if k == 11usize { ret -4.41552276226e-8f64 }
        if k == 12usize { ret 1.30503160961e-8f64 }
        if k == 13usize { ret -3.8262599802e-9f64 }
        if k == 14usize { ret 1.1123226976e-9f64 }
        if k == 15usize { ret -3.204765534e-10f64 }
        if k == 16usize { ret 9.14870489e-11f64 }
        if k == 17usize { ret -2.58778946e-11f64 }
        if k == 18usize { ret 7.2550731e-12f64 }
        if k == 19usize { ret -2.0172226e-12f64 }
        if k == 20usize { ret 5.566891e-13f64 }
        if k == 21usize { ret -1.526247e-13f64 }
        if k == 22usize { ret 4.16121e-14f64 }
        if k == 23usize { ret -1.12933e-14f64 }
        if k == 24usize { ret 3.0537e-15f64 }
        if k == 25usize { ret -8.234e-16f64 }
        if k == 26usize { ret 2.215e-16f64 }
        if k == 27usize { ret -5.95e-17f64 }
        if k == 28usize { ret 1.59e-17f64 }
        if k == 29usize { ret -4.0e-18f64 }
    }
    if id == 23usize {
        if k == 0usize { ret 2.0404775940601704976f64 }
        if k == 1usize { ret 0.8122168298093491444f64 }
        if k == 2usize { ret 0.1536371165644008069f64 }
        if k == 3usize { ret 0.0156174323847845125f64 }
        if k == 4usize { ret 0.0005943427879290297f64 }
        if k == 5usize { ret -0.0000429609447738365f64 }
        if k == 6usize { ret -3.8246452994606e-6f64 }
        if k == 7usize { ret 3.802306180287e-7f64 }
        if k == 8usize { ret 4.05746157593e-8f64 }
        if k == 9usize { ret -4.5530360159e-9f64 }
        if k == 10usize { ret -5.306873139e-10f64 }
        if k == 11usize { ret 6.37297268e-11f64 }
        if k == 12usize { ret 7.8403674e-12f64 }
        if k == 13usize { ret -9.840241e-13f64 }
        if k == 14usize { ret -1.255952e-13f64 }
        if k == 15usize { ret 1.62617e-14f64 }
        if k == 16usize { ret 2.1318e-15f64 }
        if k == 17usize { ret -2.825e-16f64 }
        if k == 18usize { ret -3.78e-17f64 }
        if k == 19usize { ret 5.1e-18f64 }
    }
    if id == 24usize {
        if k == 0usize { ret 13.403206654624176674f64 }
        if k == 1usize { ret 5.574508357051880924f64 }
        if k == 2usize { ret 0.931228574387527769f64 }
        if k == 3usize { ret 0.054638356514085862f64 }
        if k == 4usize { ret -0.001477172902737439f64 }
        if k == 5usize { ret -0.000029378553381869f64 }
        if k == 6usize { ret 0.000018357033493246f64 }
        if k == 7usize { ret -2.348059218454e-6f64 }
        if k == 8usize { ret 8.3173787440e-8f64 }
        if k == 9usize { ret 2.6826486956e-8f64 }
        if k == 10usize { ret -6.011244398e-9f64 }
        if k == 11usize { ret 4.94345981e-10f64 }
        if k == 12usize { ret 3.9557340e-11f64 }
        if k == 13usize { ret -1.7894930e-11f64 }
        if k == 14usize { ret 2.348972e-12f64 }
        if k == 15usize { ret -1.2823e-14f64 }
        if k == 16usize { ret -5.4192e-14f64 }
        if k == 17usize { ret 1.0527e-14f64 }
        if k == 18usize { ret -6.39e-16f64 }
        if k == 19usize { ret -1.47e-16f64 }
        if k == 20usize { ret 4.5e-17f64 }
        if k == 21usize { ret -5.0e-18f64 }
    }
    if id == 25usize {
        if k == 0usize { ret 101.03685253378877642f64 }
        if k == 1usize { ret 43.62085156043435883f64 }
        if k == 2usize { ret 6.62241373362387453f64 }
        if k == 3usize { ret 0.25081415008708521f64 }
        if k == 4usize { ret -0.00798124846271395f64 }
        if k == 5usize { ret 0.00063462245101023f64 }
        if k == 6usize { ret -0.00006392178890410f64 }
        if k == 7usize { ret 6.04535131939e-6f64 }
        if k == 8usize { ret -3.4007683037e-7f64 }
        if k == 9usize { ret -4.072661545e-8f64 }
        if k == 10usize { ret 1.931148453e-8f64 }
        if k == 11usize { ret -4.46328355e-9f64 }
        if k == 12usize { ret 7.9434717e-10f64 }
        if k == 13usize { ret -1.1573569e-10f64 }
        if k == 14usize { ret 1.304658e-11f64 }
        if k == 15usize { ret -7.4114e-13f64 }
        if k == 16usize { ret -1.4181e-13f64 }
        if k == 17usize { ret 6.491e-14f64 }
        if k == 18usize { ret -1.597e-14f64 }
        if k == 19usize { ret 3.05e-15f64 }
        if k == 20usize { ret -4.8e-16f64 }
    }
    if id == 26usize {
        if k == 0usize { ret 0.6160645215171852381f64 }
        if k == 1usize { ret -0.0071239478492671463f64 }
        if k == 2usize { ret 0.0027906866139659846f64 }
        if k == 3usize { ret -0.0009829521424317718f64 }
        if k == 4usize { ret 0.0003260229808519545f64 }
        if k == 5usize { ret -0.0001040160912910890f64 }
        if k == 6usize { ret 0.0000322931223232439f64 }
        if k == 7usize { ret -9.8243506588102e-6f64 }
        if k == 8usize { ret 2.9420132351277e-6f64 }
        if k == 9usize { ret -8.699154670418e-7f64 }
        if k == 10usize { ret 2.545460071999e-7f64 }
        if k == 11usize { ret -7.38305056331e-8f64 }
        if k == 12usize { ret 2.12545670310e-8f64 }
        if k == 13usize { ret -6.0796532462e-9f64 }
        if k == 14usize { ret 1.7294556741e-9f64 }
        if k == 15usize { ret -4.896540687e-10f64 }
        if k == 16usize { ret 1.380786037e-10f64 }
        if k == 17usize { ret -3.88057305e-11f64 }
        if k == 18usize { ret 1.08753212e-11f64 }
        if k == 19usize { ret -3.0407308e-12f64 }
        if k == 20usize { ret 8.485626e-13f64 }
        if k == 21usize { ret -2.364275e-13f64 }
        if k == 22usize { ret 6.57636e-14f64 }
        if k == 23usize { ret -1.81807e-14f64 }
        if k == 24usize { ret 4.6884e-15f64 }
    }
    if id == 27usize {
        if k == 0usize { ret 30.364682982501076273f64 }
        if k == 1usize { ret 17.079395277408394574f64 }
        if k == 2usize { ret 4.560132133545072889f64 }
        if k == 3usize { ret 0.549281246730419979f64 }
        if k == 4usize { ret 0.372976075069301172e-01f64 }
        if k == 5usize { ret 0.161362430201041242e-02f64 }
        if k == 6usize { ret 0.481916772120371e-04f64 }
        if k == 7usize { ret 0.10512425288938e-05f64 }
        if k == 8usize { ret 0.174638504670e-07f64 }
        if k == 9usize { ret 0.22815486544e-09f64 }
        if k == 10usize { ret 0.240443082e-11f64 }
        if k == 11usize { ret 0.2086588e-13f64 }
        if k == 12usize { ret 0.15167e-15f64 }
    }
    if id == 28usize {
        if k == 0usize { ret 0.4490721623532660844f64 }
        if k == 1usize { ret 0.898353677994187218e-01f64 }
        if k == 2usize { ret 0.81044573772151290e-02f64 }
        if k == 3usize { ret 0.4261716991089162e-03f64 }
        if k == 4usize { ret 0.147609631270746e-04f64 }
        if k == 5usize { ret 0.3628633615300e-06f64 }
        if k == 6usize { ret 0.66634807498e-08f64 }
        if k == 7usize { ret 0.949077166e-10f64 }
        if k == 8usize { ret 0.1079125e-11f64 }
        if k == 9usize { ret 0.10022e-13f64 }
        if k == 10usize { ret 0.77e-16f64 }
        if k == 11usize { ret 0.5e-18f64 }
    }
    if id == 29usize {
        if k == 0usize { ret 2.1329305161355000985f64 }
        if k == 1usize { ret 0.741352864954200240e-01f64 }
        if k == 2usize { ret 0.86968099909964198e-02f64 }
        if k == 3usize { ret 0.11703826248775692e-02f64 }
        if k == 4usize { ret 0.1645105798619192e-03f64 }
        if k == 5usize { ret 0.240201021420640e-04f64 }
        if k == 6usize { ret 0.35827756389389e-05f64 }
        if k == 7usize { ret 0.5447747626984e-06f64 }
        if k == 8usize { ret 0.838802856196e-07f64 }
        if k == 9usize { ret 0.13069882684e-07f64 }
        if k == 10usize { ret 0.2053099071e-08f64 }
        if k == 11usize { ret 0.325187537e-09f64 }
        if k == 12usize { ret 0.517914041e-10f64 }
        if k == 13usize { ret 0.83002988e-11f64 }
        if k == 14usize { ret 0.13352728e-11f64 }
        if k == 15usize { ret 0.2159150e-12f64 }
        if k == 16usize { ret 0.349967e-13f64 }
        if k == 17usize { ret 0.56994e-14f64 }
        if k == 18usize { ret 0.9291e-15f64 }
        if k == 19usize { ret 0.152e-15f64 }
        if k == 20usize { ret 0.249e-16f64 }
        if k == 21usize { ret 0.41e-17f64 }
        if k == 22usize { ret 0.7e-18f64 }
    }
    if id == 30usize {
        if k == 0usize { ret 38.617839923843085480f64 }
        if k == 1usize { ret 23.037715594963734597f64 }
        if k == 2usize { ret 5.3802499868335705968f64 }
        if k == 3usize { ret 0.6156793806995710776f64 }
        if k == 4usize { ret 0.406688004668895584e-01f64 }
        if k == 5usize { ret 0.17296274552648414e-02f64 }
        if k == 6usize { ret 0.51061258836577e-04f64 }
        if k == 7usize { ret 0.110459595022e-05f64 }
        if k == 8usize { ret 0.18235530206e-07f64 }
        if k == 9usize { ret 0.2370769803e-09f64 }
        if k == 10usize { ret 0.24887296e-11f64 }
        if k == 11usize { ret 0.21529e-13f64 }
        if k == 12usize { ret 0.156e-15f64 }
    }
    if id == 31usize {
        if k == 0usize { ret 7.9063148270660804288f64 }
        if k == 1usize { ret 3.1353463612853425684f64 }
        if k == 2usize { ret 0.4854879477453714538f64 }
        if k == 3usize { ret 0.394816675827237234e-01f64 }
        if k == 4usize { ret 0.19661622334808802e-02f64 }
        if k == 5usize { ret 0.659078932293042e-04f64 }
        if k == 6usize { ret 0.15857561349856e-05f64 }
        if k == 7usize { ret 0.286865301123e-07f64 }
        if k == 8usize { ret 0.4041202360e-09f64 }
        if k == 9usize { ret 0.45568444e-11f64 }
        if k == 10usize { ret 0.420459e-13f64 }
        if k == 11usize { ret 0.3232e-15f64 }
        if k == 12usize { ret 0.21e-17f64 }
    }
    if id == 32usize {
        if k == 0usize { ret 2.020337094170713600f64 }
        if k == 1usize { ret 0.10956237121807404e-01f64 }
        if k == 2usize { ret 0.8542384730114676e-03f64 }
        if k == 3usize { ret 0.723430242132822e-04f64 }
        if k == 4usize { ret 0.63124427962699e-05f64 }
        if k == 5usize { ret 0.5648193141174e-06f64 }
        if k == 6usize { ret 0.512832480138e-07f64 }
        if k == 7usize { ret 0.47196532914e-08f64 }
        if k == 8usize { ret 0.4380744214e-09f64 }
        if k == 9usize { ret 0.410268149e-10f64 }
        if k == 10usize { ret 0.38623072e-11f64 }
        if k == 11usize { ret 0.3661323e-12f64 }
        if k == 12usize { ret 0.348023e-13f64 }
        if k == 13usize { ret 0.33301e-14f64 }
        if k == 14usize { ret 0.319e-15f64 }
        if k == 15usize { ret 0.307e-16f64 }
        if k == 16usize { ret 0.3e-17f64 }
    }
    if id == 33usize {
        if k == 0usize { ret 1.671760446434538503f64 }
        if k == 1usize { ret -0.147735359946794490f64 }
        if k == 2usize { ret 0.148213819946936338e-01f64 }
        if k == 3usize { ret -0.14195330326305613e-02f64 }
        if k == 4usize { ret 0.1306541324415708e-03f64 }
        if k == 5usize { ret -0.117155795867579e-04f64 }
        if k == 6usize { ret 0.10333498445756e-05f64 }
        if k == 7usize { ret -0.901911304223e-07f64 }
        if k == 8usize { ret 0.78177169833e-08f64 }
        if k == 9usize { ret -0.6744565684e-09f64 }
        if k == 10usize { ret 0.579946394e-10f64 }
        if k == 11usize { ret -0.49747619e-11f64 }
        if k == 12usize { ret 0.425961e-12f64 }
        if k == 13usize { ret -0.36422e-13f64 }
        if k == 14usize { ret 0.3111e-14f64 }
        if k == 15usize { ret -0.265e-15f64 }
        if k == 16usize { ret 0.23e-16f64 }
        if k == 17usize { ret -0.19e-17f64 }
    }
    if id == 34usize {
        if k == 0usize { ret 0.762012543243872007f64 }
        if k == 1usize { ret -0.105674387705058533f64 }
        if k == 2usize { ret 0.119778084819657810e-01f64 }
        if k == 3usize { ret -0.12144015203698307e-02f64 }
        if k == 4usize { ret 0.1155099769392855e-03f64 }
        if k == 5usize { ret -0.105815992124423e-04f64 }
        if k == 6usize { ret 0.9474663385302e-06f64 }
        if k == 7usize { ret -0.836221212858e-07f64 }
        if k == 8usize { ret 0.73109099278e-08f64 }
        if k == 9usize { ret -0.6350594779e-09f64 }
        if k == 10usize { ret 0.549118282e-10f64 }
        if k == 11usize { ret -0.47321395e-11f64 }
        if k == 12usize { ret 0.4067695e-12f64 }
        if k == 13usize { ret -0.348971e-13f64 }
        if k == 14usize { ret 0.29892e-14f64 }
        if k == 15usize { ret -0.256e-15f64 }
        if k == 16usize { ret 0.219e-16f64 }
        if k == 17usize { ret -0.19e-17f64 }
    }
    if id == 35usize {
        if k == 0usize { ret 0.4807570994615110579f64 }
        if k == 1usize { ret -0.8175378810321083956e-01f64 }
        if k == 2usize { ret 0.1002700665975162973e-01f64 }
        if k == 3usize { ret -0.10599339359820151e-02f64 }
        if k == 4usize { ret 0.1034506245030405e-03f64 }
        if k == 5usize { ret -0.96442705485899e-05f64 }
        if k == 6usize { ret 0.8745544408515e-06f64 }
        if k == 7usize { ret -0.779321207981e-07f64 }
        if k == 8usize { ret 0.68649886141e-08f64 }
        if k == 9usize { ret -0.5999571076e-09f64 }
        if k == 10usize { ret 0.521366241e-10f64 }
        if k == 11usize { ret -0.45118382e-11f64 }
        if k == 12usize { ret 0.3892159e-12f64 }
        if k == 13usize { ret -0.334936e-13f64 }
        if k == 14usize { ret 0.28767e-14f64 }
        if k == 15usize { ret -0.2467e-15f64 }
        if k == 16usize { ret 0.211e-16f64 }
        if k == 17usize { ret -0.18e-17f64 }
    }
    if id == 36usize {
        if k == 0usize { ret 0.347777777133910789f64 }
        if k == 1usize { ret -0.66456988976050428e-01f64 }
        if k == 2usize { ret 0.8611072656883309e-02f64 }
        if k == 3usize { ret -0.9396682223755538e-03f64 }
        if k == 4usize { ret 0.936324806081513e-04f64 }
        if k == 5usize { ret -0.88571319340833e-05f64 }
        if k == 6usize { ret 0.811914989145e-06f64 }
        if k == 7usize { ret -0.72957654233e-07f64 }
        if k == 8usize { ret 0.646971455e-08f64 }
        if k == 9usize { ret -0.568490283e-09f64 }
        if k == 10usize { ret 0.49625598e-10f64 }
        if k == 11usize { ret -0.4310940e-11f64 }
        if k == 12usize { ret 0.373100e-12f64 }
        if k == 13usize { ret -0.32198e-13f64 }
        if k == 14usize { ret 0.2772e-14f64 }
        if k == 15usize { ret -0.238e-15f64 }
        if k == 16usize { ret 0.21e-16f64 }
        if k == 17usize { ret -0.18e-17f64 }
    }
    if id == 37usize {
        if k == 0usize { ret -1.14516408366268311786898152867f64 }
        if k == 1usize { ret 0.00636085311347084238122955495f64 }
        if k == 2usize { ret 0.00186245193007206848934643657f64 }
        if k == 3usize { ret 0.000152833085873453507081227824f64 }
        if k == 4usize { ret 0.000017017464011802038795324732f64 }
        if k == 5usize { ret -6.4597502923347254354668326451e-07f64 }
        if k == 6usize { ret -5.1819848432519380894104312968e-08f64 }
        if k == 7usize { ret 4.5189092894858183051123180797e-10f64 }
        if k == 8usize { ret 3.2433227371020873043666259180e-11f64 }
        if k == 9usize { ret 6.8309434024947522875432400828e-13f64 }
        if k == 10usize { ret 2.8353502755172101513119628130e-14f64 }
        if k == 11usize { ret -7.9883905769323592875638087541e-16f64 }
        if k == 12usize { ret -3.3726677300771949833341213457e-17f64 }
        if k == 13usize { ret -3.6586334809210520744054437104e-20f64 }
    }
    if id == 38usize {
        if k == 0usize { ret 1.882645524949671835019616975350f64 }
        if k == 1usize { ret -0.077490658396167518329547945212f64 }
        if k == 2usize { ret -0.018256714847324929419579340950f64 }
        if k == 3usize { ret 0.0006338030209074895795923971731f64 }
        if k == 4usize { ret 0.0000762290543508729021194461175f64 }
        if k == 5usize { ret -9.5501647561720443519853993526e-07f64 }
        if k == 6usize { ret -8.8927268107886351912431512955e-08f64 }
        if k == 7usize { ret -1.9521334772319613740511880132e-09f64 }
        if k == 8usize { ret -9.4003052735885162111769579771e-11f64 }
        if k == 9usize { ret 4.6875133849532393179290879101e-12f64 }
        if k == 10usize { ret 2.2658535746925759582447545145e-13f64 }
        if k == 11usize { ret -1.1725509698488015111878735251e-15f64 }
        if k == 12usize { ret -7.0441338200245222530843155877e-17f64 }
        if k == 13usize { ret -2.4377878310107693650659740228e-18f64 }
        if k == 14usize { ret -7.5225243218253901727164675011e-20f64 }
    }
    if id == 39usize {
        if k == 0usize { ret 2.16786447866463034423060819465f64 }
        if k == 1usize { ret -0.05533249018745584258035832802f64 }
        if k == 2usize { ret 0.01800392431460719960888319748f64 }
        if k == 3usize { ret -0.00580919269468937714480019814f64 }
        if k == 4usize { ret 0.00186523689488400339978881560f64 }
        if k == 5usize { ret -0.00059746524113955531852595159f64 }
        if k == 6usize { ret 0.00019125169907783353925426722f64 }
        if k == 7usize { ret -0.00006124996546944685735909697f64 }
        if k == 8usize { ret 0.00001963889633130842586440945f64 }
        if k == 9usize { ret -6.3067741254637180272515795142e-06f64 }
        if k == 10usize { ret 2.0288698405861392526872789863e-06f64 }
        if k == 11usize { ret -6.5384896660838465981983750582e-07f64 }
        if k == 12usize { ret 2.1108698058908865476480734911e-07f64 }
        if k == 13usize { ret -6.8260714912274941677892994580e-08f64 }
        if k == 14usize { ret 2.2108560875880560555583978510e-08f64 }
        if k == 15usize { ret -7.1710331930255456643627187187e-09f64 }
        if k == 16usize { ret 2.3290892983985406754602564745e-09f64 }
        if k == 17usize { ret -7.5740371598505586754890405359e-10f64 }
        if k == 18usize { ret 2.4658267222594334398525312084e-10f64 }
        if k == 19usize { ret -8.0362243171659883803428749516e-11f64 }
        if k == 20usize { ret 2.6215616826341594653521346229e-11f64 }
        if k == 21usize { ret -8.5596155025948750540420068109e-12f64 }
        if k == 22usize { ret 2.7970831499487963614315315444e-12f64 }
        if k == 23usize { ret -9.1471771211886202805502562414e-13f64 }
        if k == 24usize { ret 2.9934720198063397094916415927e-13f64 }
        if k == 25usize { ret -9.8026575909753445931073620469e-14f64 }
        if k == 26usize { ret 3.2116773667767153777571410671e-14f64 }
        if k == 27usize { ret -1.0518035333878147029650507254e-14f64 }
        if k == 28usize { ret 3.4144405720185253938994854173e-15f64 }
        if k == 29usize { ret -1.0115153943081187052322643819e-15f64 }
    }
    if id == 40usize {
        if k == 0usize { ret 0.0057502277273114339831606096782f64 }
        if k == 1usize { ret 0.0004496689534965685038254147807f64 }
        if k == 2usize { ret -0.0001672763153188717308905047405f64 }
        if k == 3usize { ret 0.0000615137014913154794776670946f64 }
        if k == 4usize { ret -0.0000223726551711525016380862195f64 }
        if k == 5usize { ret 8.0507405356647954540694800545e-06f64 }
        if k == 6usize { ret -2.8671077107583395569766746448e-06f64 }
        if k == 7usize { ret 1.0106727053742747568362254106e-06f64 }
        if k == 8usize { ret -3.5265558477595061262310873482e-07f64 }
        if k == 9usize { ret 1.2179216046419401193247254591e-07f64 }
        if k == 10usize { ret -4.1619640180795366971160162267e-08f64 }
        if k == 11usize { ret 1.4066283500795206892487241294e-08f64 }
        if k == 12usize { ret -4.6982570380537099016106141654e-09f64 }
        if k == 13usize { ret 1.5491248664620612686423108936e-09f64 }
        if k == 14usize { ret -5.0340936319394885789686867772e-10f64 }
        if k == 15usize { ret 1.6084448673736032249959475006e-10f64 }
        if k == 16usize { ret -5.0349733196835456497619787559e-11f64 }
        if k == 17usize { ret 1.5357154939762136997591808461e-11f64 }
        if k == 18usize { ret -4.5233809655775649997667176224e-12f64 }
        if k == 19usize { ret 1.2664429179254447281068538964e-12f64 }
        if k == 20usize { ret -3.2648287937449326771785041692e-13f64 }
        if k == 21usize { ret 7.1528272726086133795579071407e-14f64 }
        if k == 22usize { ret -9.4831735252566034505739531258e-15f64 }
        if k == 23usize { ret -2.3124001991413207293120906691e-15f64 }
        if k == 24usize { ret 2.8406613277170391482590129474e-15f64 }
        if k == 25usize { ret -1.7245370321618816421281770927e-15f64 }
        if k == 26usize { ret 8.6507923128671112154695006592e-16f64 }
        if k == 27usize { ret -3.9506563665427555895391869919e-16f64 }
        if k == 28usize { ret 1.6779342132074761078792361165e-16f64 }
        if k == 29usize { ret -6.0483153034414765129837716260e-17f64 }
    }
    if id == 41usize {
        if k == 0usize { ret -1.5285594096661578881275075214f64 }
        if k == 1usize { ret 4.8259152300595906319768555035f64 }
        if k == 2usize { ret 0.2277712320977614992970601978f64 }
        if k == 3usize { ret -0.0138867665685617873604917300f64 }
        if k == 4usize { ret 0.0012704876495201082588139723f64 }
        if k == 5usize { ret -0.0001393841240254993658962470f64 }
        if k == 6usize { ret 0.0000169709242992322702260663f64 }
        if k == 7usize { ret -2.2108528820210580075775889168e-06f64 }
        if k == 8usize { ret 3.0196602854202309805163918716e-07f64 }
        if k == 9usize { ret -4.2705675000079118380587357358e-08f64 }
        if k == 10usize { ret 6.2026423818051402794663551945e-09f64 }
        if k == 11usize { ret -9.1993973208880910416311405656e-10f64 }
        if k == 12usize { ret 1.3875551258028145778301211638e-10f64 }
        if k == 13usize { ret -2.1218861491906788718519522978e-11f64 }
        if k == 14usize { ret 3.2821736040381439555133562600e-12f64 }
        if k == 15usize { ret -5.1260001009953791220611135264e-13f64 }
        if k == 16usize { ret 8.0713532554874636696982146610e-14f64 }
        if k == 17usize { ret -1.2798522376569209083811628061e-14f64 }
        if k == 18usize { ret 2.0417711600852502310258808643e-15f64 }
        if k == 19usize { ret -3.2745239502992355776882614137e-16f64 }
        if k == 20usize { ret 5.2759418422036579482120897453e-17f64 }
        if k == 21usize { ret -8.5354147151695233960425725513e-18f64 }
        if k == 22usize { ret 1.3858639703888078291599886143e-18f64 }
        if k == 23usize { ret -2.2574398807738626571560124396e-19f64 }
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

fn cev_trig_sinc(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(0usize, 16usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_trig_sinc(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(0usize, 16usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_trig_sin(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(1usize, 11usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_trig_sin(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(1usize, 11usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_trig_cos(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(2usize, 10usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_trig_cos(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(2usize, 10usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_log_lopx(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(3usize, 20usize, 10usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_log_lopx(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(3usize, 20usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_log_lopxmx(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(4usize, 19usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_log_lopxmx(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(4usize, 19usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_1_a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(5usize, 21usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_1_a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(5usize, 21usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_1_b(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(6usize, 21usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_1_b(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(6usize, 21usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_1_c(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(7usize, 22usize, 13usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_1_c(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(7usize, 22usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_1_d(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(8usize, 29usize, 14usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_1_d(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(8usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_1_e(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(9usize, 9usize, 4usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_1_e(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(9usize, 9usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_2_a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(10usize, 20usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_2_a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(10usize, 20usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_2_b(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(11usize, 21usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_2_b(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(11usize, 21usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_2_c(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(12usize, 19usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_2_c(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(12usize, 19usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_2_d(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(13usize, 29usize, 14usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_2_d(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(13usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_2_e(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(14usize, 3usize, 3usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_2_e(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(14usize, 3usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_mhalf_a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(15usize, 19usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_mhalf_a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(15usize, 19usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_mhalf_b(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(16usize, 19usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_mhalf_b(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(16usize, 19usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_mhalf_c(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(17usize, 24usize, 13usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_mhalf_c(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(17usize, 24usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_mhalf_d(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(18usize, 29usize, 15usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_mhalf_d(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(18usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_half_a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(19usize, 22usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_half_a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(19usize, 22usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_half_b(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(20usize, 19usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_half_b(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(20usize, 19usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_half_c(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(21usize, 22usize, 13usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_half_c(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(21usize, 22usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_half_d(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(22usize, 29usize, 15usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_half_d(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(22usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_3half_a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(23usize, 19usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_3half_a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(23usize, 19usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_3half_b(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(24usize, 21usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_3half_b(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(24usize, 21usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_3half_c(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(25usize, 20usize, 12usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_3half_c(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(25usize, 20usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_fermi_dirac_fd_3half_d(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(26usize, 24usize, 16usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_fermi_dirac_fd_3half_d(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(26usize, 24usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_synchrotron_synchrotron1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(27usize, 12usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_synchrotron_synchrotron1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(27usize, 12usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_synchrotron_synchrotron2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(28usize, 11usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_synchrotron_synchrotron2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(28usize, 11usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_synchrotron_synchrotron1a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(29usize, 22usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_synchrotron_synchrotron1a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(29usize, 22usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_synchrotron_synchrotron21(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(30usize, 12usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_synchrotron_synchrotron21(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(30usize, 12usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_synchrotron_synchrotron22(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(31usize, 12usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_synchrotron_synchrotron22(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(31usize, 12usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_synchrotron_synchrotron2a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(32usize, 16usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_synchrotron_synchrotron2a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(32usize, 16usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_transport_transport2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(33usize, 17usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_transport_transport2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(33usize, 17usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_transport_transport3(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(34usize, 17usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_transport_transport3(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(34usize, 17usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_transport_transport4(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(35usize, 17usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_transport_transport4(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(35usize, 17usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_transport_transport5(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(36usize, 17usize, 9usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_transport_transport5(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(36usize, 17usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_temme_g1(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(37usize, 13usize, 7usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_temme_g1(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(37usize, 13usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_bessel_temme_g2(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(38usize, 14usize, 8usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_bessel_temme_g2(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(38usize, 14usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_gamma_gstar_a(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(39usize, 29usize, 17usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_gamma_gstar_a(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(39usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_gamma_gstar_b(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(40usize, 29usize, 18usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_gamma_gstar_b(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(40usize, 29usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

fn cev_gamma_gamma_5_10(x: f64, mode: usize) -> (f64, f64) {
    let (v, e) = cheb_eval_mode(41usize, 23usize, 11usize, -1.0f64, 1.0f64, x, mode)
    ret (v, e)
}

fn cvv_gamma_gamma_5_10(x: f64) -> (f64, f64) {
    let (v, e) = cheb_eval(41usize, 23usize, -1.0f64, 1.0f64, x)
    ret (v, e)
}

// gsl_poly_eval of gamma_lanczos_7_c
fn pv_gamma_lanczos_7_c(x: f64) -> f64 {
    ret 0.99999999999980993227684700473478f64 + x * (676.520368121885098567009190444019f64 + x * (-1259.13921672240287047156078755283f64 + x * (771.3234287776530788486528258894f64 + x * (-176.61502916214059906584551354f64 + x * (12.507343278686904814458936853f64 + x * (-0.13857109526572011689554707f64 + x * (9.984369578019570859563e-6f64 + x * (1.50563273514931155834e-7f64))))))))
}

