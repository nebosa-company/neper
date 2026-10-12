// `e.time.chinese` against lunar_python for Chinese years 1900..2100 (scripts/gen_chinese_calendar_test.py): the new
// year, the leap month and every month length of each year, the first and last day of every month both ways, and every
// day of the years divisible by 25. Years 1906 and 2057 are skipped in the walk (D3600). Every check has its own exit
// code.
use e.os
use e.mem
use e.time
use e.time.chinese as chinese

fn years() -> str {
    ret "044638096d04847004ae0520100a570555650a4d0593900d260629300d950664840d55070320056a07386009ad077412095d08125004ae084796149b0886300a4d0921700d250957151aa50995500b541030900d6a10664212da110480095b114037093711787004971214100a4b124955164b12879006a513233006d413587415b513972002b61432600957146812092f15065004971541960c961580200d4a1615600ea51651150da916895005ad17250002b6176043126e179880092e183427192d1872600c951908000d4a1943461b4a1981800b55201730056a205274155b209120025d212660092d216202192b2200400a95223587169522742006ca2309600b552345150ab523835004da2418900a5b2454430a57249280052b252828152a2566500e9526020006aa26374615aa2675800ab527113004b627467414ae2785100a5728206005262855931d262894300d952929870b55296820056a300360096d303915095d30775004ad3112900a4d3148341a4d3186700d253222181aa53260500b543295900b6a33314612da336980095b340530049b34407414973479100a4b35145a164b35529006a535883006d436237615b43662100ab63697600957373315092f3771500497380690064b3842330d4a3880600ea53916180d6539545005ac3989900ab6402545126d406380092e4099200c964134641a954173000d4a4208400da54243920b55428230056a431777155b435620025d439160092d442705192b4465400a954500800b4a45362416aa4574600ad54610190ab546485004ba4683900a5b4719460a57475780052b4793200a934828640e9548670006aa4902400ad549379209b549763004b650117614ae5050100a4e5085500d265120951d265159300d5351948005aa5230230d6a526860096d53041b095d53425004ad5377900a4d5413361a4b5451700d255487100d525522551b545560900b5a559640056d563192095b567030049b57057714975744100a4b5779500aa558149516a558533006d25888700ada5924230ab65962600937599818092f6036500497607190064b6107360d4a6145600ea561811006b2621654156c6254900aae629040092e632583192e6364200c966399671a956438000d4a6473400da56508950b55654730056a6582700a6d6618240a5d665660052d669208152b6730400a956765800b4a68012616aa6839600ad5687510055a69105414ba6948900a5b698440052b701983152770582006937093670e5371320006aa7167400ad572029509b572413004b67276700a577312240a4e7350500d167385981d267424300d527459700daa7495260d6a753360056d75691004ae760454149d7642900a2d7678300d157713721b257752100d52"
}

fn hex_at(table: str, at: usize) -> i64 {
    let b = table[at]
    if b >= 97u8 { ret i64(b) - 87i64 }
    ret i64(b) - 48i64
}

fn dec5(table: str, at: usize) -> i64 {
    var v = 0i64
    var k = 0usize
    while k < 5usize {
        v = v * 10i64 + (i64(table[at + k]) - 48i64)
        k += 1usize
    }
    ret v
}

fn pow2(n: i64) -> i64 {
    var r = 1i64
    var i = 0i64
    while i < n {
        r = r * 2i64
        i += 1i64
    }
    ret r
}

fn known(year: i32) -> bool {
    ret year == 1906i32 || year == 2057i32
}

fn is(days: i64, year: i32, month: u8, leap: bool, day: u8) -> bool {
    let (d, e) = chinese.from_days(days)
    ret e == ok && d.year == year && d.month == month && d.leap == leap && d.day == day
}

fn main(a: *mem.Arena, args: []str) -> err {
    let table = years()
    var y = 0usize
    while y < 201usize {
        let year = i32(1900 + y)
        let at = y * 10usize
        let new_year_days = dec5(table, at) - 30000i64
        let leap_number = hex_at(table, at + 5usize)
        let bits = hex_at(table, at + 6usize) * 4096i64 + hex_at(table, at + 7usize) * 256i64 + hex_at(table, at + 8usize) * 16i64 + hex_at(table, at + 9usize)
        var months = 12i64
        if leap_number != 0i64 { months = 13i64 }
        if !known(year) {
            let (ny, ny_e) = chinese.new_year(year)
            if ny_e != ok || ny != new_year_days { os.exit(11) }
            if i64(chinese.leap_month(year)) != leap_number { os.exit(12) }
            var start = new_year_days
            var j = 0i64
            while j < months {
                var number = j + 1i64
                var leap = false
                if leap_number != 0i64 && j == leap_number {
                    number = leap_number
                    leap = true
                }
                if leap_number != 0i64 && j > leap_number { number = j }
                var length = 29i64
                if time.floor_mod(bits / pow2(months - 1i64 - j), 2i64) == 1i64 { length = 30i64 }
                let (ml, ml_e) = chinese.month_length(year, u8(number), leap)
                if ml_e != ok || i64(ml) != length { os.exit(13) }
                let (first, first_e) = chinese.to_days(chinese.Date{ year: year, month: u8(number), leap: leap, day: 1u8 })
                if first_e != ok || first != start { os.exit(14) }
                if !is(start, year, u8(number), leap, 1u8) { os.exit(15) }
                if !is(start + length - 1i64, year, u8(number), leap, u8(length)) { os.exit(16) }
                if time.floor_mod(i64(year), 25i64) == 0i64 {
                    var d = 1i64
                    while d <= length {
                        if !is(start + d - 1i64, year, u8(number), leap, u8(d)) { os.exit(17) }
                        let (back, back_e) = chinese.to_days(chinese.Date{ year: year, month: u8(number), leap: leap, day: u8(d) })
                        if back_e != ok || back != start + d - 1i64 { os.exit(18) }
                        d += 1i64
                    }
                }
                start += length
                j += 1i64
            }
        }
        y += 1usize
    }
    // The model's own answers where the references differ by a new moon minutes from midnight.
    if !is(0i64 - 23264i64, 1906i32, 4u8, false, 1u8) { os.exit(21) }
    if !is(32047i64, 2057i32, 9u8, false, 1u8) { os.exit(22) }
    // Edges: outside 1900..2100 is refused, a 30th day of a 29-day month and a leap month that is not there too.
    let (before, before_e) = chinese.from_days(time.days_from_civil(1899i64, 12i64, 31i64))
    if before_e == ok { os.exit(23) }
    let (after, after_e) = chinese.from_days(time.days_from_civil(2101i64, 6i64, 1i64))
    if after_e == ok { os.exit(24) }
    let (nope, nope_e) = chinese.to_days(chinese.Date{ year: 2024i32, month: 5u8, leap: true, day: 1u8 })
    if nope_e == ok { os.exit(25) }
    let (long, long_e) = chinese.to_days(chinese.Date{ year: 2023i32, month: 1u8, leap: false, day: 30u8 })
    if long_e == ok { os.exit(26) }
    let (stem, branch) = chinese.stem_branch(1984i32)
    if stem != 0u8 || branch != 0u8 { os.exit(27) }
    let (stem2, branch2) = chinese.stem_branch(2024i32)
    if stem2 != 0u8 || branch2 != 4u8 { os.exit(28) }
    ret ok
}
