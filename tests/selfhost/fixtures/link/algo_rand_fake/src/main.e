// `e.algo.rand.fake` against scripts/fake_vectors.py, an independent PCG and generator written from the
// documented behaviour: five seeds across the four locales, six rounds each of every generator, exact
// text per line; then shape rules (Luhn, UUID v4 version and variant, IPv4 ranges, MAC bits, colours,
// calendar dates, determinism and independence of streams) over a larger stream.
use e.algo.rand.fake as fake
use e.io
use e.mem
use e.os
use e.str

fn expected() -> str {
    ret "Susan Williams|michael.jones@example.net|mary.miller53|Brown Group|90 Cedar Lane, Riverton|+1 999 698 8393|e742375d-57ec-42b6-87f0-683db39245fc|55.150.245.139|0a:5f:d3:81:e8:25|#af9c2e|4376372598336486|1988-09-19|1976-08-14|Cillum aliqua dolor ex veniam exercitation.|Ad incididunt velit dolore sunt lorem fugiat. Ex cillum adipiscing aliquip laboris aliqua cillum.|0|n|Salem|voluptate\nJohn Johnson|jennifer.davis@example.org|robert.brown00|Williams LLC|104 Park Road, Clinton|+1 470 821 6694|e0352f8f-1427-456a-9c06-deb50887efcb|80.147.159.30|1e:4a:37:be:9f:09|#9dd390|4786295234351698|1997-05-19|1968-12-26|Aliquip sunt pariatur quis veniam dolor.|Non laboris minim reprehenderit dolore eiusmod deserunt nulla labore. Laborum minim officia aliquip ea culpa.|0|n|Springfield|sed\nJohn Smith|david.jones@example.org|elizabeth.miller58|Garcia and Sons|115 Cedar Lane, Springfield|+1 379 030 5784|64756d28-5999-4482-899e-468c152e49ab|3.239.146.52|5a:54:42:33:c1:f4|#5a2fb2|4900262381910107|1982-06-27|1965-04-01|Tempor ea ut minim aute sint.|Nostrud commodo nulla occaecat cupidatat. Adipiscing consectetur ad id magna.|0|y|Riverton|esse\nJames Smith|patricia.miller@inbox.test|patricia.garcia19|Miller Group|71 Maple Drive, Fairview|+1 360 759 4992|6b45d88a-8664-495e-aac4-639f697f25a7|206.9.73.209|32:4d:56:2d:aa:b6|#d6c89c|4305542287775519|1995-08-06|1976-01-01|Exercitation aliquip in ut laborum quis.|Dolor culpa laboris fugiat ea laborum proident amet aliquip qui. Dolore aute voluptate id labore reprehenderit.|-1|y|Clinton|nostrud\nRobert Wilson|patricia.brown@example.com|david.brown07|Jones Group|152 Elm Street, Fairview|+1 615 442 5035|41c5ea5d-bbbc-463e-b3c9-4d35fd22dd46|151.195.146.84|c2:79:e8:91:80:4a|#45ede7|4677477860712284|1979-08-15|1974-03-12|Non qui mollit anim deserunt excepteur.|Commodo enim aute ullamco veniam mollit proident veniam pariatur dolore officia. Veniam nostrud sed laborum minim anim nisi culpa reprehenderit fugiat.|0|n|Salem|aliqua\nMary Miller|patricia.davis@inbox.test|james.brown39|Johnson Group|41 Park Road, Fairview|+1 077 955 6796|b661baf1-40df-48a2-b994-9625e5c5dd5a|59.245.169.200|3e:35:4d:a8:e2:85|#238185|4026783345346863|2023-07-14|1976-08-12|Enim fugiat occaecat esse quis enim.|Elit ut irure quis ea. Tempor enim ea labore consequat veniam aute do.|1|n|Franklin|laboris\nHeidi Becker|heidi.hoffmann@example.org|sabine.wagner79|Schmidt KG|Bahnhofstrasse 194, Leipzig|+49 317 09527237|a3891b26-2eb7-4bf9-96bb-d99ad71d4ea7|11.55.128.188|26:bb:99:5c:e6:35|#113674|4053564187184745|1985-04-13|1967-11-22|Commodo pariatur et aute lorem id.|Nostrud consequat aliquip quis ullamco et. Nisi ea enim minim ea est aliqua ad proident incididunt occaecat esse.|-2|y|Muenchen|lorem\nUrsula Mueller|jurgen.fischer@mail.test|anna.meyer33|Wagner KG|Dorfstrasse 171, Muenchen|+49 326 53246021|e25b1dcf-0a5c-4e24-92a3-66405bf60409|136.93.128.229|ca:71:49:66:a7:35|#cb0393|4046334936104976|2018-03-07|1976-04-28|Ipsum dolor sed tempor laboris laborum.|Nostrud adipiscing aute minim esse sunt. Proident ea nostrud sed anim enim sit et sit.|-4|y|Frankfurt|amet\nAnna Fischer|ursula.meyer@example.net|sabine.schmidt98|Weber und Soehne|Lindenweg 83, Koeln|+49 033 47818193|17909c4c-31ee-4ea3-b188-18f749291a23|151.31.76.131|02:07:5c:24:e2:f8|#6a518e|4899520245778819|1970-01-14|1974-08-27|Ut proident exercitation ut adipiscing mollit.|Commodo sit adipiscing et ut sed ex excepteur laborum consectetur. Occaecat aute aliquip mollit sed ipsum ipsum.|-5|n|Muenchen|in\nKlaus Meyer|anna.weber@example.org|hans.schneider86|Schneider KG|Hauptstrasse 52, Koeln|+49 876 83921267|1a17724c-42dd-4017-a771-1be89cd6457c|93.59.132.146|66:4a:73:c4:35:bf|#93a30e|4279770963710029|1976-02-11|1964-05-13|Reprehenderit anim ut sed enim sit.|Esse ea duis amet incididunt sunt exercitation non cupidatat in nisi. Consequat commodo magna pariatur irure nulla commodo.|4|y|Berlin|exercitation\nMonika Fischer|klaus.becker@corp.test|klaus.weber04|Meyer KG|Bahnhofstrasse 158, Frankfurt|+49 371 83336150|bc782a59-4d4e-460a-9540-6ebe46ecd4b3|13.236.28.53|66:d8:ae:9b:87:a5|#aab578|4422487934966087|2008-10-09|1968-11-26|Lorem aliquip laboris nisi tempor adipiscing.|Eiusmod ad et commodo laboris exercitation sint fugiat reprehenderit. Laborum amet sint aliquip cillum anim tempor pariatur sint ut sit sit.|3|y|Leipzig|commodo\nKlaus Fischer|jurgen.fischer@inbox.test|hans.meyer34|Weber AG|Dorfstrasse 179, Koeln|+49 721 52137097|1f0d916f-37c3-46db-adca-9570d8445b6f|161.105.106.77|0e:97:b0:ef:fb:c2|#54bb9c|4886841005954886|1985-04-03|1970-09-29|Sit ullamco non ullamco ut ex.|Commodo aliquip ullamco tempor do consectetur sunt nostrud sit pariatur incididunt quis. Sit elit in in sed.|-2|y|Leipzig|esse\nMarie Thomas|hugo.richard@example.net|antoine.leroy22|Robert SARL|Rue Pasteur 49, Bordeaux|+33 5 12 66 40 66|e719b20a-a818-4e08-af33-d3755f9e80ec|91.243.215.193|7a:c6:28:8d:70:ff|#2ed397|4577807427502813|1978-08-28|1976-07-17|Laborum nisi minim pariatur id sunt.|Qui ipsum elit culpa consectetur consequat ea. Magna cillum ullamco cupidatat et incididunt pariatur veniam proident adipiscing.|-1|n|Lyon|irure\nMichel Bernard|luc.martin@inbox.test|sophie.moreau83|Leroy SARL|Rue Pasteur 146, Lyon|+33 5 44 66 16 88|a392de81-0693-4efa-a9cc-e347b24c5009|65.245.142.190|f6:e3:90:0c:72:fb|#581cdf|4886584423100274|1992-06-29|1973-08-15|Est do irure elit voluptate ut.|Fugiat deserunt deserunt duis aliqua non aliqua laborum ad quis officia. Nostrud culpa sunt ut amet commodo.|-5|n|Toulouse|ut\nLuc Thomas|margaux.durand@example.net|louise.moreau27|Dubois SARL|Avenue des Champs 53, Toulouse|+33 1 13 36 61 62|6fbd9500-6be8-484c-9570-1259839aeadc|203.124.76.203|22:0f:79:84:f2:10|#20bff4|4018646655244525|2003-08-08|1969-12-01|Irure ex ad esse amet incididunt.|Cupidatat duis reprehenderit ea laboris. Id magna laborum sint do.|1|n|Marseille|minim\nSophie Thomas|sophie.dubois@corp.test|camille.martin21|Richard et Fils|Avenue des Champs 162, Nantes|+33 3 32 68 31 43|fa75bdc6-c041-4554-ac0b-9176e371bc40|135.176.150.46|7e:23:d3:41:5f:6f|#c91578|4610115578402422|1988-07-08|1967-07-25|Irure consequat laborum aliquip sit officia.|Commodo ipsum consectetur eiusmod id non ullamco eiusmod. Quis reprehenderit occaecat elit adipiscing nulla.|2|n|Toulouse|id\nCamille Robert|camille.richard@example.net|camille.leroy07|Robert et Fils|Rue du Moulin 150, Paris|+33 1 73 33 45 86|bf344c41-38b8-400e-bc87-b5ae04c8cc88|138.34.175.99|76:79:03:74:68:53|#72df2b|4300881522740705|2018-07-06|1971-10-15|Id nostrud consectetur ut commodo exercitation.|Proident excepteur in voluptate aute laboris mollit. Sunt nisi duis ad fugiat nulla incididunt aliquip officia dolore sit.|5|n|Paris|in\nLuc Martin|sophie.dubois@example.com|marie.leroy69|Thomas Groupe|Rue Pasteur 141, Marseille|+33 2 34 89 41 05|980ad764-f5a1-45d9-b640-24400322ce55|48.154.90.204|a6:7b:4b:fe:f0:d5|#f39934|4486873649534604|2008-01-10|1969-02-06|Est sed qui reprehenderit ullamco ut.|Lorem velit sint quis occaecat amet sint esse sit magna occaecat. Eiusmod incididunt et amet elit fugiat non ad lorem ut labore dolore.|1|n|Nantes|voluptate\nJavier Gonzalez|marta.perez@example.com|paula.fernandez81|Sanchez e Hijos|Avenida de la Paz 161, Barcelona|+34 580 15 29 97|57b7fae1-5a4d-4c11-b9da-3fe88841042d|93.8.159.132|8a:30:29:18:b0:d8|#dd9c5e|4294590404679737|1982-11-21|1967-08-14|Aute non esse aliqua ut veniam.|Fugiat enim aliquip sit nisi magna irure. Sunt nostrud aliqua aliquip duis fugiat laborum veniam irure.|1|y|Murcia|et\nJose Lopez|javier.rodriguez@inbox.test|marta.gonzalez62|Fernandez SA|Avenida de la Paz 165, Madrid|+34 943 67 85 57|79ed29ad-1a6c-45a3-904d-1d45d724c19e|77.25.9.254|fa:cb:b9:35:16:99|#5ee230|4735515096061222|1997-02-22|1971-03-25|Lorem qui aute aute sit esse.|Proident enim minim est cillum sunt et et ipsum reprehenderit. Laboris non consectetur voluptate ut nulla labore cillum occaecat consequat.|-5|n|Valencia|ad\nJavier Garcia|carlos.sanchez@example.com|pablo.gonzalez75|Martinez SA|Calle Real 140, Murcia|+34 404 92 71 06|2ba6e8cb-9225-4070-9da3-e7f200b4e9ed|52.69.203.121|6a:f0:67:23:1a:dc|#9b95a3|4547004220981256|2010-10-07|1971-03-26|Ad consequat excepteur consequat sed et.|Do laboris deserunt sed officia magna dolor reprehenderit lorem sint. Pariatur sint cillum excepteur dolor non amet duis anim exercitation ex dolor.|5|n|Murcia|sunt\nCarlos Martinez|carlos.martinez@example.org|lucia.gomez80|Gomez Grupo|Calle Real 137, Bilbao|+34 316 69 29 34|54c45f3a-400f-42c4-9939-942076b5dc4c|215.110.88.205|7e:e9:e4:a5:c0:2d|#fe724b|4680790100277818|1989-02-20|1963-09-07|Deserunt pariatur irure anim reprehenderit est.|Veniam ex pariatur in est sunt ipsum ad in quis quis. Nulla mollit minim laborum aliqua ullamco.|-5|y|Murcia|adipiscing\nManuel Lopez|jose.gomez@corp.test|carlos.gonzalez34|Rodriguez e Hijos|Avenida de la Paz 38, Sevilla|+34 404 66 25 21|052f5e34-11f3-46c1-a80b-cf3dfcb249d7|85.173.109.45|ae:6d:0c:f3:ce:37|#c32e77|4454263748870174|1996-08-18|1973-08-07|Veniam deserunt officia et enim deserunt.|Eiusmod officia non labore officia enim ut quis labore. Dolor reprehenderit reprehenderit eiusmod duis ea id ex elit ex.|2|n|Malaga|est\nManuel Gonzalez|elena.garcia@example.org|maria.gomez30|Garcia e Hijos|Calle Real 29, Malaga|+34 953 96 18 31|3be8d698-757d-4be6-b02f-8ee528d89a83|213.171.215.18|1a:aa:d2:46:06:07|#e480d9|4756992745005229|2007-06-22|1974-12-14|Culpa ullamco sunt adipiscing laborum laborum.|Consectetur consectetur ad et eiusmod dolor deserunt et labore id velit voluptate. Est ex tempor exercitation officia deserunt.|-4|n|Valencia|nulla\nJames Miller|james.garcia@example.net|michael.garcia29|Garcia Inc|121 Elm Street, Springfield|+1 166 708 4175|a07098b9-b449-4dde-8f06-ee3663c18448|132.122.96.173|f6:1d:fb:8d:ad:09|#4d1435|4675283053549380|2017-04-19|1974-04-08|Qui aute aliqua id adipiscing sunt.|Aliqua velit laborum lorem ad aute occaecat id sunt officia occaecat. Amet velit magna nostrud ex irure esse ipsum velit culpa veniam.|-1|n|Franklin|cillum\nJohn Anderson|robert.miller@mail.test|david.jones14|Jones Group|88 Elm Street, Fairview|+1 629 440 9759|7f1a347c-29f2-49c3-8ef8-c948a40863ac|2.35.168.52|c2:85:7c:5f:8d:a1|#87dd14|4970165319707963|1990-12-29|1975-09-13|Excepteur aute quis minim aute ut.|Exercitation voluptate consectetur est culpa lorem dolor id quis sit elit. Veniam sit pariatur id deserunt reprehenderit ea quis proident reprehenderit nostrud veniam.|2|y|Franklin|labore\nJames Williams|patricia.williams@corp.test|james.smith80|Jones Ltd|159 Park Road, Clinton|+1 368 672 9386|b0cc5201-2b13-48d1-a0e7-063f72922bec|49.9.128.185|9a:6f:65:b6:db:80|#cf0075|4700849349660352|2004-11-24|1968-05-31|Et officia adipiscing nisi sed mollit.|Magna aute duis ipsum adipiscing aliqua tempor lorem id anim. Tempor enim dolore amet deserunt lorem cillum lorem labore fugiat adipiscing.|-3|n|Fairview|minim\nJohn Smith|william.wilson@inbox.test|john.jones04|Jones Inc|147 Cedar Lane, Springfield|+1 033 645 7353|558b9416-7c8f-4734-9f98-f9106e629fb1|164.80.137.108|d6:bb:12:7c:6a:41|#9271a2|4776406726736583|2011-09-13|1963-05-11|Occaecat commodo exercitation cillum et ullamco.|Pariatur est cillum duis excepteur reprehenderit nostrud labore qui laboris ad mollit. Sit laborum esse dolore duis sint.|-5|y|Riverton|consequat\nWilliam Davis|susan.brown@inbox.test|michael.anderson95|Johnson Ltd|107 Cedar Lane, Riverton|+1 637 960 0042|44c65537-e4e4-48ea-ac17-09e97d52608f|109.167.4.123|76:11:5f:84:d0:9d|#75b003|4270691414073644|1985-03-10|1977-01-06|Ad est ut dolor tempor labore.|Proident incididunt elit proident nostrud dolore proident sunt enim velit cupidatat. Magna lorem adipiscing culpa consectetur reprehenderit eiusmod mollit.|-5|n|Springfield|velit\nJames Johnson|linda.garcia@inbox.test|jennifer.garcia46|Smith Inc|105 Main Street, Riverton|+1 880 405 6866|34493635-ba28-46c9-b443-b29c0bfef0e2|120.145.41.27|96:2f:ee:e1:86:3c|#ae007b|4147022635006414|2001-06-10|1964-07-30|Tempor voluptate dolore nisi do sint.|Labore pariatur esse labore et excepteur fugiat lorem exercitation cillum aute. Est occaecat nostrud voluptate commodo nostrud nulla mollit quis eiusmod.|0|n|Clinton|adipiscing"
}

fn locale_of(index: usize) -> fake.Locale {
    if index == 1usize { ret fake.Locale.De }
    if index == 2usize { ret fake.Locale.Fr }
    if index == 3usize { ret fake.Locale.Es }
    ret fake.Locale.En
}

fn seed_of(index: usize) -> u64 {
    if index == 0usize { ret 42u64 }
    if index == 1usize { ret 7u64 }
    if index == 2usize { ret 2024u64 }
    if index == 3usize { ret 0u64 }
    ret 18446744073709551615u64
}

fn sep(b: *str.Builder) -> err {
    ret str.push(b, "|")
}

fn one_round(f: *fake.Faker, b: *str.Builder) -> err {
    try fake.name(f, b)
    try sep(b)
    try fake.email(f, b)
    try sep(b)
    try fake.username(f, b)
    try sep(b)
    try fake.company(f, b)
    try sep(b)
    try fake.address(f, b)
    try sep(b)
    try fake.phone(f, b)
    try sep(b)
    try fake.uuid4(f, b)
    try sep(b)
    try fake.ipv4(f, b)
    try sep(b)
    try fake.mac_address(f, b)
    try sep(b)
    try fake.hex_color(f, b)
    try sep(b)
    try fake.credit_card(f, b)
    try sep(b)
    try fake.date(f, b, 0i64, 20000i64)
    try sep(b)
    try fake.date(f, b, -3000i64, 3000i64)
    try sep(b)
    try fake.lorem_sentence(f, b, 6usize)
    try sep(b)
    try fake.lorem_paragraph(f, b, 2usize)
    try sep(b)
    try str.push_i64(b, fake.int_between(f, -5i64, 5i64))
    try sep(b)
    if fake.chance(f, 30u32) { try str.push(b, "y") } else { try str.push(b, "n") }
    try sep(b)
    try str.push(b, fake.city(f))
    try sep(b)
    try str.push(b, fake.word(f))
    ret ok
}

fn hex_ok(c: u8) -> bool {
    ret (c >= 48u8 && c <= 57u8) || (c >= 97u8 && c <= 102u8)
}

fn digits_ok(s: str) -> bool {
    var i = 0usize
    while i < s.len {
        if s[i] < 48u8 || s[i] > 57u8 { ret false }
        i += 1usize
    }
    ret s.len > 0usize
}

fn uuid_ok(s: str) -> bool {
    if s.len != 36usize { ret false }
    var i = 0usize
    while i < 36usize {
        if i == 8usize || i == 13usize || i == 18usize || i == 23usize {
            if s[i] != 45u8 { ret false }
        } else if !hex_ok(s[i]) {
            ret false
        }
        i += 1usize
    }
    if s[14] != 52u8 { ret false }
    ret s[19] == 56u8 || s[19] == 57u8 || s[19] == 97u8 || s[19] == 98u8
}

fn ipv4_ok(s: str) -> bool {
    var rest = s
    var n = 0usize
    while n < 4usize {
        let (head, tail, found) = str.split_once(rest, ".")
        var part = head
        if n == 3usize {
            part = rest
        } else if !found {
            ret false
        }
        if !digits_ok(part) || part.len > 3usize { ret false }
        let (v, e) = str.parse_u64(part)
        if e != ok || v > 255u64 { ret false }
        if n == 0usize && (v < 1u64 || v > 223u64) { ret false }
        if n < 3usize { rest = tail }
        n += 1usize
    }
    ret true
}

fn mac_ok(s: str) -> bool {
    if s.len != 17usize { ret false }
    var i = 0usize
    while i < 17usize {
        if i % 3usize == 2usize {
            if s[i] != 58u8 { ret false }
        } else if !hex_ok(s[i]) {
            ret false
        }
        i += 1usize
    }
    // Second hex digit of the first byte: bit 1 set (locally administered), bit 0 clear (unicast).
    let c = s[1]
    var v = c - 48u8
    if c >= 97u8 { v = c - 87u8 }
    ret (v & 3u8) == 2u8
}

fn date_ok(s: str) -> bool {
    if s.len != 10usize || s[4] != 45u8 || s[7] != 45u8 { ret false }
    let (y, ey) = str.parse_u64(s[0..4])
    let (m, em) = str.parse_u64(s[5..7])
    let (d, ed) = str.parse_u64(s[8..10])
    if ey != ok || em != ok || ed != ok { ret false }
    if m < 1u64 || m > 12u64 || d < 1u64 { ret false }
    var limit = 31u64
    if m == 4u64 || m == 6u64 || m == 9u64 || m == 11u64 { limit = 30u64 }
    if m == 2u64 {
        limit = 28u64
        if (y % 4u64 == 0u64 && y % 100u64 != 0u64) || y % 400u64 == 0u64 { limit = 29u64 }
    }
    ret d <= limit
}

fn check_vectors(a: *mem.Arena) -> i32 {
    var want = str.lines(expected())
    var index = 0usize
    while index < 5usize {
        var f = fake.faker(seed_of(index), locale_of(index))
        var r = 0usize
        while r < 6usize {
            let (b0, be) = str.builder(a, 1024usize)
            if be != ok { ret 10i32 }
            var b = b0
            if one_round(&f, &b) != ok { ret 11i32 }
            let got = str.done(&b)
            let (line, more) = str.split_next(&want)
            if !more { ret 12i32 }
            if !str.eq(got, line) { ret 20i32 + i32(index) * 6i32 + i32(r) }
            r += 1usize
        }
        index += 1usize
    }
    ret 0i32
}

fn check_shapes(a: *mem.Arena) -> i32 {
    var f = fake.faker(99u64, fake.Locale.En)
    var i = 0usize
    while i < 2000usize {
        let (b0, be) = str.builder(a, 128usize)
        if be != ok { ret 50i32 }
        var b = b0
        if fake.credit_card(&f, &b) != ok { ret 51i32 }
        let card = str.done(&b)
        if card.len != 16usize || !digits_ok(card) || !fake.luhn_valid(card) { ret 52i32 }
        let (c0, ce) = str.builder(a, 128usize)
        if ce != ok { ret 50i32 }
        var c = c0
        if fake.uuid4(&f, &c) != ok { ret 53i32 }
        if !uuid_ok(str.done(&c)) { ret 54i32 }
        let (d0, de) = str.builder(a, 128usize)
        if de != ok { ret 50i32 }
        var d = d0
        if fake.ipv4(&f, &d) != ok { ret 55i32 }
        if !ipv4_ok(str.done(&d)) { ret 56i32 }
        let (m0, me) = str.builder(a, 128usize)
        if me != ok { ret 50i32 }
        var m = m0
        if fake.mac_address(&f, &m) != ok { ret 57i32 }
        if !mac_ok(str.done(&m)) { ret 58i32 }
        let (t0, te) = str.builder(a, 128usize)
        if te != ok { ret 50i32 }
        var t = t0
        if fake.date(&f, &t, -719000i64, 2000000i64) != ok { ret 59i32 }
        if !date_ok(str.done(&t)) { ret 60i32 }
        let (h0, he) = str.builder(a, 128usize)
        if he != ok { ret 50i32 }
        var h = h0
        if fake.hex_color(&f, &h) != ok { ret 61i32 }
        let color = str.done(&h)
        if color.len != 7usize || color[0] != 35u8 { ret 62i32 }
        i += 1usize
    }
    ret 0i32
}

fn check_luhn() -> i32 {
    if !fake.luhn_valid("4539578763621486") { ret 70i32 }
    if !fake.luhn_valid("79927398713") { ret 71i32 }
    if fake.luhn_valid("79927398710") { ret 72i32 }
    if fake.luhn_valid("") || fake.luhn_valid("4") || fake.luhn_valid("12a4") { ret 73i32 }
    ret 0i32
}

fn check_streams(a: *mem.Arena) -> i32 {
    // Same seed, same stream; another seed, another stream; locale overlays differ in the tables.
    var x = fake.faker(5u64, fake.Locale.En)
    var y = fake.faker(5u64, fake.Locale.En)
    var z = fake.faker(6u64, fake.Locale.En)
    var same = true
    var other = false
    var i = 0usize
    while i < 16usize {
        let nx = fake.first_name(&x)
        let ny = fake.first_name(&y)
        let nz = fake.first_name(&z)
        if !str.eq(nx, ny) { same = false }
        if !str.eq(nx, nz) { other = true }
        i += 1usize
    }
    if !same || !other { ret 80i32 }
    if fake.blob_count("a,b,c") != 3usize || !str.eq(fake.blob_item("a,b,c", 1usize), "b") { ret 81i32 }
    if !str.eq(fake.blob_item("a,b,c", 9usize), "c") || !str.eq(fake.blob_item("solo", 0usize), "solo") { ret 82i32 }
    var low = 0i64
    var f = fake.faker(1u64, fake.Locale.Fr)
    var k = 0usize
    while k < 500usize {
        let v = fake.int_between(&f, -3i64, 3i64)
        if v < -3i64 || v > 3i64 { ret 83i32 }
        low += v
        k += 1usize
    }
    if fake.int_between(&f, 9i64, 2i64) != 9i64 { ret 84i32 }
    ret 0i32
}

fn main(a: *mem.Arena, args: []str) -> err {
    var code = check_vectors(a)
    if code == 0i32 { code = check_shapes(a) }
    if code == 0i32 { code = check_luhn() }
    if code == 0i32 { code = check_streams(a) }
    if code != 0i32 { os.exit(code) }
    let e = io.print("algo rand fake ok")
    ret ok
}
