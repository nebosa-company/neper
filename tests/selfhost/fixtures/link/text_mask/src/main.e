// e.text.mask against Python's fnmatch on the shared syntax (600 seeded pairs) and hand tables for
// escapes, ^ negation, ASCII case folding, UTF-8 code points, ; lists and malformed masks (L076, D2266;
// scripts/text_mask_reference.py writes this file). A mismatch prints its table and index and exits 1.
use e.io
use e.mem
use e.os
use e.text.mask

fn report(table: str, index: usize) -> err {
    var digits: [20]u8 = zero
    var count = 0usize
    var n = index
    if n == 0usize {
        digits[0usize] = 48u8
        count = 1usize
    }
    while n > 0usize {
        digits[count] = 48u8 + u8(n % 10usize)
        n /= 10usize
        count += 1usize
    }
    let glyphs = "0123456789"
    try io.print("text mask mismatch in ")
    try io.print(table)
    try io.print(" at ")
    var i = count
    while i > 0usize {
        i -= 1usize
        try io.print(glyphs[usize(digits[i] - 48u8)..usize(digits[i] - 48u8) + 1usize])
    }
    try io.print("\n")
    os.exit(1)
    ret ok
}

fn main(a: *mem.Arena, args: []str) -> err {
    let shared0_masks = [100]str{ "[!ß][éq]*.a-", "yb[zq]_-_", "*", "**[!-]?[éq]9日", "[bq][!a]?[yq]?", "?9[!.][éq][aq]a", "*日bb[!x]", "日[xq]9***?[bq]y", "0x[日q]*", "b?", "", "", "[éq]", "[ßq]", "?éz?[zq]*[b-d]日", "0日-[-q]_-é", "*", "日[yq]-", "*[日q][!b]aé?b[!x][b-d]", "c", "", "*.?z", "[bq]ß.0", "*.*[_q]*.*", "[!9]*", "a", "[ßq]z-?ß", "?[a-z][!y]", "[!b][bq]za*é_b", "[!9]**b-[xq][ßq]?", "_*z", "?*0", "é", "x9?-?[!c]*", "?c[!.]?é*日", "[_q][aq]日y?*", "*x00_**", "*.yy?*", "[!9]x[ßq]日日??[ßq]", "c*cy9.?[bq]", "-*", "a9日a[ßq]ß?[éq]*", "ß", "*?c*?9y", "*9?*", "y[a-b]y*[b-d]9[yq]*", "9**_*[yq][aq]y[!c]", "*z[!c].[!y]c*", "?-[a-z]", "*??", "é_", "", "x?xy*日[!b][aq]", "éa?cß", "**cc??", "", "x9[!b][!c]*[0q]a?", "?", "by*?ß*", "日*xß*?*", "[_q][!z][!日][!c]?-", "-", "*b-a?", "*bxß*[b-d]", "é_日[!a].[_q]ba", "[!é]_ß[!日]*?[yq]é", "*.*?b[a-z]日", "__by?", "[éq]", "[!z][ßq]*", "_?c[a-c]", "é?z?0?*", "*b?ßy*?", "[!_][-q]ß[!0]0[aq]z", "???[yq]x?*[-q]", "*-[!_]", "*", "?*-?[a-z]", "*_[!y]9bß", "[!z]", "?[a-b]-.[zq]9[!y]*", "a*a??b_**", "*?a*9-", "*日", "*[!x]", "ß", "_*x??[_q]y", "***[xq]", "*?x?_[.q]", "?[zq]?", "[a-z]?", ".?z*?", "0[x-z][_q]é*ab", "y??[a-b]**-", "", "[x-z]yz*x", "-z_[!_][!x]", "*[!é]?9", "**", "" }
    let shared0_texts = [100]str{ "ßéz.a-", "ybzz-_", "", "ca-0é9日", "ba日yß", "99.éaa", "__bbx", "日x9éé-by", "ax日_", "bb", "", "", "_", "x", "cézczcc日", "0日--_-é", "", "日yb", "日baé.bxc", "z", "", "é.-z", "bß.0", "x.zé_.", "9z", "a", "ßz-9ß", "x9y", "bbzaé_b", "9bcb-xß日", "bz", "ßz0", "-", "x9a-bc_", "cc.ßé日", "_a日y.", "x00_", ".yy9c", "9xß日éc.ß", "cacy9.xb", "-", "a9日aßß9é", "ß", ".cß9y", "é90", "yay9c9y", "9-x_y0yc", ".zc.yc", "y-日", "éy", "a_", "", "xxxy-日ba", "éaxcß", "ßcc日z", "", "x9bc-0ac", "_", "byß日ßa", "日yxßz9é", "bz日cc-", "b", "b-a_", "bbxßc", "é_日.._ba", "é_ß日-ßyé", "z.-b-日", "b_byy", "é", "zß", "_x0b", "é0za09y", "cbaßy9", "_-ß00az", "-c0yxéz-", "日-_", "b", "9a-ßb", "_y9bß", "z", "za-.z9y", "aéaé0b__", "-a9é", "9.", "_x", "-", "_x.-_y", "09_x", "xzx9_.", "xz_", "日.", ".ézcz", "0y_éab", "yb_aax-", "", "yyzéx", "-z__é", "x_.9", "é", "" }
    let shared0_cs = [100]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    let shared0_want = [100]bool{ false, false, true, false, false, false, false, true, false, true, true, true, false, false, true, true, true, false, false, false, true, true, true, true, false, true, true, false, false, false, false, true, false, false, false, true, true, true, false, true, true, true, true, true, true, true, false, false, false, true, false, true, false, true, true, true, false, true, true, true, false, false, true, true, true, false, false, false, true, false, false, true, true, false, true, false, true, true, false, false, false, true, false, false, false, false, true, true, true, true, false, true, true, true, true, true, false, true, true, true }
    var shared0_i = 0usize
    while shared0_i < 100 {
        let (shared0_hit, shared0_error) = mask.matches(shared0_masks[shared0_i], shared0_texts[shared0_i], shared0_cs[shared0_i])
        if shared0_error != ok || shared0_hit != shared0_want[shared0_i] { try report("shared0", shared0_i) }
        shared0_i += 1usize
    }
    let shared1_masks = [100]str{ "cé0", "_?[a-z]cßc", "*", "y[aq]c", "??-", "*..", "*[ßq]?*?", "*a[bq]00[w-y][ßq]*", "**ba*", "**[aq][a-z]", "[a-b][_q]?y[aq]", "ß.", "*ßc?日", ".*日日日???-*", "*", "?ßa**bbb", "9c", "**?x", "[-q]b", "0?[bq][.q]x*[.q]?.*", "[!é]c**éé[!y]", "*[!é][0q]", "b?a*b", "", "z[zq][!y]_cz??", "*a_?é[.q]*", "0?.bé", "9*ßé", "[aq][!0]?", "", "b0[!c][a-z]xy-", "-***z*", ".cbz[a-z]9?", "y9*", "[cq]9***[xq]", "[!c]*", "ß日é日?*", "*[!b]日", "[!.]ß日0*", "", "ß[!0]yé_*[0q]", "", "_*[aq]*?90", "é?*日*", "**[!c]*z.*y", "_?*[0q]c*.9", "", "9**yz", "[a-z][aq]?", "??é", "*[aq]y[bq]?_9[.q]", "*", "*??c[9q]", "?_c", "9?[cq]", "[a-b]", "?*0?y*é*", "*日éz", "**[!é][!_][a-z]y*[a-z].", "é-*?éz**", "?", "?日?x*[日q][ßq]", "*", "[b-d]b*x?", "*é??-?*日[cq]", "[!ß]*éb[!-]-*.", "*x-*", "x?[ßq][a-z]y[a-b][w-y]", "*[!-]y9[!a]?b日c", "[!-]?.[!a]**", "[!.]9[9q][a-z]*", "?*b.é", "日", "xß*z_c-?c", "[!x][cq]9?日[.q]日", "*", "b*", ".-0[0q]?*éz", "?0c*.?[éq]", "-", "*[xq][xq]??", "*日*[9q]ya*0*[bq]", "[!0]?日-[!0]", "zza*[zq]**", "y?[b-d]*[9q]9[0q]", "", "ß*a[a-c]", "[a-c]ß9ßßé", "?日?a0[!.]*", "ac**[a-b]?", "?[ßq]z?[!z]x*", "[!-]?[zq]z*", "*", "[a-z]*", "*[a-z]_[!b]-", "**z[bq]x*", "??[!-][xq]*bß", "*ßc[!é]*é*", "[-q]*", "a." }
    let shared1_texts = [100]str{ "cé0", "_ßécßc", "é", "yac", "-x-", "..a", "ß0日日", "ab00xß-", "b-a", "日éé", "a_ßya", "ß.", "ßc.日", ".日日日céc-", "", "ßßaabbb", "yc", "_xx", "-日", "0aß.x.x.", "éc0ééy", "é0", "bzbcb", "", "zzy_cz_.", "a__é.z", "09.bé", "xéßé", "a0é", "", "b0c9xy-", "bc0z-", ".cbzé9y", "ß9", "c9日0ax", "y", "ß日é日a日", "z日", ".ß日z", "", ".0yé_0", "", "éyaxé90", "é-ß日-", "ac日z.éy", "_0x0cé.9", "", "90yz", ".a日", "0-é", "aybx_9.", ".", "_-日c9", "9_c", "9-c", "a", "-.0éy_é", "日日éz", "日0_éyy-.", "é--zaz_", "x", "9日ßx日b", "-", "cbcxé", "é0日-x_日c", "ayéb--c.", "_x-", "xxßéyax", "-y9azb日c", "-ß.a_", ".99z", "b_bzé", "日", "xßz_c0.c", "xc9ß日.日", "", "b", ".-009.éz", "ßac.éé", "é", "zxxyß", "日09ya0日b", "09c-0", "zzazz.", "yzca990", "", "_日ab", "bß9ßßé", "日日日a0.", "ac00ay", "y_zßzx", "-bzx", "", "9.", "-_b-", "c_zbx9", "-x-x.bß", "ßc.aé.", "-x", "a." }
    let shared1_cs = [100]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    let shared1_want = [100]bool{ true, false, true, true, true, false, true, true, false, false, true, true, true, true, true, true, false, true, false, false, false, false, false, true, false, true, true, false, false, true, false, false, false, false, true, true, true, true, false, true, false, true, false, true, true, true, true, true, false, true, true, true, true, true, true, true, true, true, false, false, true, false, true, true, true, false, true, false, false, false, false, false, true, false, false, true, true, true, false, false, true, true, false, true, true, true, false, true, false, true, false, false, true, false, false, true, false, true, true, true }
    var shared1_i = 0usize
    while shared1_i < 100 {
        let (shared1_hit, shared1_error) = mask.matches(shared1_masks[shared1_i], shared1_texts[shared1_i], shared1_cs[shared1_i])
        if shared1_error != ok || shared1_hit != shared1_want[shared1_i] { try report("shared1", shared1_i) }
        shared1_i += 1usize
    }
    let shared2_masks = [100]str{ "b[!.]?*?", "*?_[a-z][a-c]*é[bq]", "*.a", "日éé_b.*", "**日y[xq]", "*[zq]ya9", "*", "*日y[!x]*[-q]?-", "[aq][bq][ßq]*[_q]?.ß", "0zb[!é].[!0][zq]", "bé*?", "-?[a-z][w-y].a", "y*0é90*?*", "-", "*", "?.[!ß]", "[!日]99", "", "日[!z]éß[xq]y-?", "a*ß[9q]9ßc", "", "[zq]", "ééß*?*", "ß", "*b?**ab*c", "[a-b]ß??", "c[xq]?_*", "ßa?[a-z]y[!x].*[!x]", "_[_q]?*9**[.q]", "*c*", "b-?", "*cx.*?*", "*ba*-[_q]", "[x-z].ß.[éq]ac", "[éq]*???", "90?0[!-]-", "**[a-z]9*[!0]", "**0*", "yxx9", "x9*", "", "*?[9q]x", "", "cby0_x[aq]", "ß?..-", "", "b0[a-z].*9*", "日zß?*", "az-", "z*", "0z[!z]?", "[yq]aß?y*", "*?", "0*", "*", "*-", "_0*", "[yq]*[a-z]0xa[!b]?*", "[a-c][!_]0", "0b[a-z]??.", "_???9by", "**日[!-]**[0q]z", "*[aq]c[!c]*", "zé_*日*0[!0][!z]", "x*", "*", "*?[!9]*y", "[日q]?*0?xay", "*?za*", "y???.[a-z]", "x[!-]?0x", "[9q]*y9*", "[a-z]日**yz?", "??*[éq]y日*", "-", "-ß[!c]9[ßq]b", "", "**[w-y]?-?-y[x-z]", "9é[yq]?ß", "9_z", "", "[a-z][a-b][!0]9??*x*", "b*?*_*[日q]", "c?[!a]", "", "_b", "-**x[a-c]*", "[0q]*??ß*[xq]", "[zq]?b?.b*", "ß[bq]", "?b*", "*9é", "*?é?[_q]", "?*é?[yq]*", ".ß-*x_[a-z]?", "xé**[zq][aq]", "a", "?[ßq]-", "[yq]", "0[日q]*[a-z]" }
    let shared2_texts = [100]str{ "b.日00", "..a0b日éb", "_.a", "日éc_b.", ".日yx", ".zya9", "", "日yx日-b-", "ab9c_b.ß", "0zbé.yz", "bé-é", "--.x.a", "y-0é90cb", "-", "", "9-ß", ".99", "", "日zéßxy-b", "aßß99ß_", "", "a", ".éß日ß", "ß", "b9.zabcc", "aßy0", "cx._9", "ßa0_yy.x", "___b99日.", "日c_", "y-日", "xcx.-y", "ébxé-_", "y.-.éac", "zcxxa", "90a0--", "日ß990", "z0", "yxx9", "x9", "", "_é9x", "", "cby0_xc", "ßz..-", "", "b0y.9z", "日zß0", "azz", "z", "0zzé", "yaß.y日", "c", "0", "", "b-", "a0", "y日.0xab_", "bß0", "bb日.ß.", "_0xc9b9", "b日-aß0z", "éßcc", "za_日y00z", "x", "", "0b90y", "日_z00xay", "-za", "ßcca.9", "x-y0x", "9xy9日", "日日aayz_", "zz0éy日", "z", "-ßc9ßb", "", "_xa-0-yy", "9by_ß", "9_z", "", "9a090bzx", "ßé9_日", "cza", "", "bb", "0日ßxb", "0日z日ßzx", "zéb_.b", "ßb", "ßb", "9c", "béc_", "_ééßy", ".ß-x__x", "xézza", "a", "日ß-", "b", "0日cb" }
    let shared2_cs = [100]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    let shared2_want = [100]bool{ false, false, true, false, true, true, true, false, false, false, true, false, true, true, true, false, true, true, false, false, true, false, false, true, true, true, true, false, true, true, false, true, false, false, false, false, false, true, true, true, true, true, true, false, true, true, true, true, false, true, false, true, true, true, true, true, false, false, true, false, false, false, false, false, true, true, true, true, true, false, false, true, false, true, false, false, true, true, false, true, true, false, false, false, true, false, false, true, true, true, true, false, true, true, false, true, true, true, false, true }
    var shared2_i = 0usize
    while shared2_i < 100 {
        let (shared2_hit, shared2_error) = mask.matches(shared2_masks[shared2_i], shared2_texts[shared2_i], shared2_cs[shared2_i])
        if shared2_error != ok || shared2_hit != shared2_want[shared2_i] { try report("shared2", shared2_i) }
        shared2_i += 1usize
    }
    let shared3_masks = [100]str{ "bzx[yq].[日q]", "*?", "9ß???y", "*09[_q]*?**", "*y*x9[0q]", "*", "", "", "*09aé*?", "*", "a[9q]*?**", "*[a-z]_z*?", "[zq]y._ß*??", "*-??[ßq]x[zq]é?", "z", "[a-z]?[a-z]?[日q][!c]*", "*[a-z]é.z*", "*[aq]*0", "[a-z]z?ß*", ".[!9]", "b?", "z", "?", "9a?", "?é[!b]zc[yq]", "*_?0b9", "*?[_q]日-", "c?[9q]??-_?*", "", "éé??a", ".éxß[a-b]?", "[!x]*x[-q]0[!a][!0][!-]*", "ßß**?y_", "", "??[.q]?*", "a9[!z][!.]?[!x]", "*c?_cß9a", "日日9é?[_q]?*", ".*[cq]?9[ßq]", "??z", "xx[!ß]y", "z*[!z]*", "[!0]a日.9.", "???c*[a-z]", "*ßy-ß?0[a-z]", "**", "x*", "[a-z]**", "*0*é", "[!_]-z", "日c?x日9?*", "9??", "zz9y?[cq][y-z]", "[.q][0q]?[!-][a-z][!x].ß", "*zc*0[zq]", "*[!z]_x", ".[cq]y[0q][a-z]", "[xq]*a", "*a[a-z]日***", "c9ß?.b*", "", "_[!y][!日].**", "??", "[a-z]0日c[w-y]", "?-*_[!x]0日a_", "[yq]0**9**", "_9?*[xq]*ß", "*[.q]", "éba*", "a?*日?y?", "*é[-q]c", "*?", "éyßa*", "b*", "[.q]日b", "?acz?*[!z]9", "a_[日q]?x*00", "*_x--b", "", "0yxß[a-z]", "日x_[-q]*x", "__ß?[!c][!y]日**", "_", "é*", "", "*?", "*y*z", "c[!y]é-c[éq]?é", "[!-]**", "[!a][!.]a[9q]9?é", "0[!x]", "?日[a-z][9q]a[.q][!.]", "?[xq]*?b*", "_*0[a-z][日q]*é", "yc", "[0q]ß[ßq]?[zq][!b][zq]c", "?[a-z][9q]", "", "", "*日*" }
    let shared3_texts = [100]str{ "bzxy.ß", "_", "9a9azy", "09_xb9日", "yx90", "", "", "", ".09aé_日", "", "a9z_9ß", "b-_z90", "zé._ßß-", "-0cßxzéc", "z", "9日_é日c", "日é.z", "ab0", "_zzß", ".c", "b-", "z", "b", "9a0", "éébzcé", "_b099", "日_日-", "ca9ab-_a", "", "éé_xa", ".éxßay", "xzx-0a0-", "ßß_xxy_", "", "a日.日a", "a9z.0x", ".c-_cß9a", "z日9éé_0", "._c.9ß", "é0z", "xcßy", "z日z", "0a日.9.", "日日ac日0", "ßy-ß日0_", "_z", "0", "0_é", "0_y", "c-z", "日c0x日90", "9-y", "zz9yécz", "z0x-日x.ß", "_cc0z", "z_.", ".cy0é", "xaa", "a_日y", "c_ßy.b", "", "_y日.日", "__", "00日cy", "--_x0日a_", "y0ßy9yy", "_9日xx0ß", "-", "éba", "a-_日cyz", "xé-c", "ß_", "éyéa", "bß", ".日b", "_aczéczb", "a_日0x00", "__x--b", "", "0ycß9", "日x_-bx", "__ßé0y日", "_", "é", "", "a", "0z", "byé-céßé", "--", "a.a99日é", "bx", "b日日9a..", "9xc-b9", "_0日日ßé", "yc", "0ßß.abzc", "日99", "", "", "日_" }
    let shared3_cs = [100]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    let shared3_want = [100]bool{ false, true, false, true, true, true, true, true, true, true, true, false, false, true, true, false, false, true, false, true, true, true, true, true, false, false, true, true, true, true, true, false, true, true, true, false, true, false, true, true, false, true, false, false, false, true, false, false, false, true, true, true, true, false, false, false, false, true, false, false, true, false, true, false, false, true, true, false, true, true, true, true, false, true, true, false, true, true, true, false, true, false, true, true, true, true, false, false, false, false, false, false, true, false, true, false, false, true, true, true }
    var shared3_i = 0usize
    while shared3_i < 100 {
        let (shared3_hit, shared3_error) = mask.matches(shared3_masks[shared3_i], shared3_texts[shared3_i], shared3_cs[shared3_i])
        if shared3_error != ok || shared3_hit != shared3_want[shared3_i] { try report("shared3", shared3_i) }
        shared3_i += 1usize
    }
    let shared4_masks = [100]str{ "z*_**", "", "[!.]**", "日??9*", "*?", "日xébyb?", "", "x.b", "日-?b[b-d]c", "*c*?日?9*[!日]", "?", "", "y*0", "日日.", "[x-z]b日**9", "?x", "*c[a-z][bq]yc", "*ß0_0*?", "*-日日日*[cq]", "b[xq]?_?b", "yßb.", "éybyc", "日a[_q]9*a_", "[a-z]_*z", "a?z[cq]bxa*", "[9q]aé-[!-]", "日[!_]0xa[a-c]", "[!y]x?*a", "[!y]*", "*-.日?", "_bß[!9]é**[a-z]", "", "", "*[a-z]y[!_]*", "*?[!_][a-z]ß[!x]**", "*日_0??.*", "c日ab.", "*0ca[a-z]?_*9", "_[a-z][a-z][a-z]?b[a-z]", "yb*éa*", "[9q]", "y?.?[ßq]*", "[w-y][a-z]?x", "日?é*-", "[éq][a-b]", "*a?b??[a-z][!é]*", "0[cq]**cé日_", "*z[x-z][aq]?9[9q][aq]*", "[a-z]", "-0[!_][ßq]", "?", "z*[a-b][a-z][!y][!.]", "ab9y", "aßß??*", "?[!x]x*yz", "?[a-z]?.[bq][éq][0q]a", "", "*9*[!_]_cz.[aq]", "ß*[9q]", "[b-d]", "?", "cß[_q]x", "日*9[a-z]", "a[x-z]byyazb*", "9", "[a-z][zq]ß*9*a*", "[-q]***?é0", "[!9]yz*?b[bq]c?", "?x9?*", "_ß", "_0[!x][0q]*.é", "yß", "", "", "[yq]", "*c", "", "?*9[bq]*é?[cq]*", "00ß-", "x", "*[!_][w-y]0", "", "?[!z]?0", "?[a-z]0*-**?[!y]", ".??b", "0b[éq]_[!b]-*", "??0[zq]**", "c_0z__[-q]", "[0q]b[!c][!a]_?_", "?", "y.0.", "-[!ß]", "y", "*?-*", "aé[.q]", "*?[xq]cxbé", "", "bé.c", "", "[a-z]*" }
    let shared4_texts = [100]str{ "zc_", "", ".99", "日日x9", "aé", "cxébybé", "", "x.b", "日-cbcy", "cyß日b9y日", "ß", "", "y0", "日日.", "yb日c9", "zx", "c-byc", "ß0_0ac", "-日日日ßc", "bxc_9b", "yßb.", "éybyc", "日a_9a_", "日_cz", "azzcbxa_", "9aß--", "日_0xab", "yxbya", "y0", "x-.日_", "_bß9é.--", "", "", "c.y_", "__-ßxb", "日_xc-.", "céab.", "0ca9-y9", "_ééß9b9", "yb9éa", "9", "ya.yß", "xbßx", "日yéé-", "éa", "a.b.0_é.", "0cybcé日_", "zybß99a", "c", "-0__", "-", "z_a9y.", "ab9y", "aßßyx", "0xxéz", "b_ß.b90a", "", "9a__cß.a", "ß9", "c", "_", "cß_x", "日9_", "aybyyazb", "y", "0zß99日", "-c9ébß0", "9yzzbbcß", "0x9é", "_ß", "_0x0é.é", "yß", "", "", "9", "c", "", "0y9bzééc", "00.-", "x", "z_x0", "", "ézyc", "日é0-ßacy", ".yzb", "0bé_b-", "z_0z.0", "c_0z__-", "0bcc_é_", "b", "y.0.", "aß", "y", "ca-", "a日.", "0xcxbé", "", "bc.c", "", ".é" }
    let shared4_cs = [100]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    let shared4_want = [100]bool{ true, true, false, true, true, false, true, true, false, false, true, true, true, true, true, true, false, true, true, true, true, true, true, false, true, false, false, false, false, true, false, true, true, false, false, false, false, false, false, true, true, true, true, true, true, false, true, false, true, false, true, false, true, true, false, false, true, false, true, true, true, true, false, true, false, false, false, false, true, true, false, true, true, true, false, true, true, true, false, true, false, true, false, false, true, false, true, true, false, true, true, false, true, true, false, true, true, false, true, false }
    var shared4_i = 0usize
    while shared4_i < 100 {
        let (shared4_hit, shared4_error) = mask.matches(shared4_masks[shared4_i], shared4_texts[shared4_i], shared4_cs[shared4_i])
        if shared4_error != ok || shared4_hit != shared4_want[shared4_i] { try report("shared4", shared4_i) }
        shared4_i += 1usize
    }
    let shared5_masks = [100]str{ "*", "?[!-][_q]?b_", "**[_q][!y]?z", "*b", "a?*ß*b", "[!c]", "9[!c][!é][!é]", "*éy??", "[a-z]-*日[x-z]_?", "é?9??[éq][-q]", "*", "[!.][cq]日-[!x]b?*", "**é[bq]*", "é?[ßq]*z_", "[y-z]b*[!a]cc**", "[x-z]a*??", "[cq]ß-[!9][0q]ß", "???[!0]*", "yy?z9*", "xz?.[éq]-x", "*a*[!_]", "09?y", "_xß[a-z][!9]日?_", "[!0]c[日q]", "zz[éq]", "_yé9", "**_", "日", "-[a-z]a[!b]?a_-", "x日", "?[!c][9q]a[-q]?[bq]?", "*.*z9b?", "9b日", "ba*c**[a-z]?b", "*[xq]é0", "?", "*.x?xz", "?cc?[!a]", "", "", "*_", "[!x]?", "?[y-z][ßq]z[éq]aa*", "*z?0_[aq]-[!_]", "*x", "yyé", "ß_?ßézé[a-z]", "", "*éc_a***", "-a", "y??", "*ß**[9q]9[yq]z[a-z]", "c-?-?-y", "*-[xq]0*", "ca", "z0[cq]*__", "*b", "[yq]*", "b[a-z]*", "", "[x-z]0[!.]", "*?zc?", "z[!-]_*-", "*_0*", "_[zq]_*[a-z]", "[!x]00.[a-z]9", "a-*-y.", "a[!.].[!ß]??", "0*[!ß]", "*.日b?[!b]*?[!-]", "?[a-c]日-??9[!9]", "??*b***", "", "y", "?[xq].0**ya0", "z*ßß*?", "a[!.]*-*0", "[aq]caz[ßq][zq][日q]*", "[ßq]?[éq]", "[9q]**", "-*日[!日][!ß]z*0", "", "?*", "?[-q]_", "a日.", "", "*[!ß]é?9[!-]", "*", "**", "ßy*[éq]b日0z", ".*[aq]日*-z", "***9", "0*c*[w-y]", "*ß*a**", "[yq]-", "*b_[0q].*?[!ß]*", "[xq]-*bß[.q]9", "[a-z]a[!a]?-a", "", "" }
    let shared5_texts = [100]str{ "", "c-_.b_", "-_yaz", "b", "a0bßb", "c", "9céé", "日yby", ".-日é_é", "éb9_ßé-", "", ".c日0xb9", "日éy", "é_ßbz_", "z.acc.", "yacc", "cß.90ß", "bx日0", "yyxz9", "_z9.é-x", "é-_", "09éy", "_xßé9日ß_", "bc日", "_zé", "ayé9", "é_", "é", "-0abéa_-", "z日", "bc9a-bb.", ".az9ay", "9by", "ba日c日日_b", "xéc", "é", "日.x_cz", "ßccaa", "", "", "_", "xß", "9zßzéaa", "zz0_a-_", "日", "yyé", "ß_0ßéz_0", "", "éc_a-y", "-b", "y._", ".ß.99yz9", "--x---y", "a-x0.", "ca", "z00日__", "-z", "9", "b日", "", "y0.", "..zc.", "z-_a-", "__", "_z__", "000.日9", "a-.yy.", "a..ßya", "0yß", ".bbßbbb-", "éb日-yé99", "0ccb9ß", "", "y", "bx.0.ya0", "zßßéé", "a.b-z", "acazßz日", "ß_é", "9日a", "-x日日ßz.0", "", "_0", "0-_", "a日.", "", "ßé99-", "", "", "ßbxéb日0z", ".9a日y-z", "_9c9", "0cc", "yß9a_", "--", "ab_0.czß", "_-bbß.9", ".aaß-a", "", "" }
    let shared5_cs = [100]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true }
    let shared5_want = [100]bool{ true, false, false, true, true, false, false, false, false, true, true, false, false, true, false, true, false, false, true, false, false, true, false, true, false, false, true, false, false, false, false, false, false, false, false, true, false, false, true, true, true, false, true, false, false, true, false, true, true, false, true, false, false, true, true, false, false, false, false, true, false, true, false, false, false, false, false, false, false, false, false, true, true, true, true, true, false, true, true, true, false, true, true, true, true, true, false, true, true, false, true, true, false, true, false, true, false, false, true, true }
    var shared5_i = 0usize
    while shared5_i < 100 {
        let (shared5_hit, shared5_error) = mask.matches(shared5_masks[shared5_i], shared5_texts[shared5_i], shared5_cs[shared5_i])
        if shared5_error != ok || shared5_hit != shared5_want[shared5_i] { try report("shared5", shared5_i) }
        shared5_i += 1usize
    }
    let hand_masks = [83]str{ "a\\*b", "a\\*b", "a\\?b", "a\\?b", "\\[a\\]", "\\[a\\]", "[\\]]", "[\\]]", "[a\\-c]", "[a\\-c]", "[a\\-c]", "\\\\", "\\a", "*\\.txt", "*\\.txt", "[^abc]", "[^abc]", "[!abc]", "[!abc]", "[^a-c]x", "[^a-c]x", "[]a]", "[]a]", "[]a]", "[!]a]", "[!]a]", "[a-]", "[a-]", "[a-]", "[-a]", "[-a]", "[a-c-e]", "[a-c-e]", "", "", "*", "?", "**", "**a**", "*a*b*c", "*a*b*c", "a*b*c", "a*aab", "a*aab", "a*aab", "*abc", "*abc", "a?c", "a?c", "*?", "*?", "?*?", "?*?", "?", "??", "caf?", "caf?", "caf??", "?", "???", "?", "*", "[é-ü]", "[é-ü]", "[日本]", "[^日本]", "*語", "日*", "é", "é", "*.TXT", "*.TXT", "[A-C]x", "[A-C]x", "[a-c]x", "[a-c]x", "ABC", "ABC", "É", "É", "[!A]", "[!A]", "\\A" }
    let hand_texts = [83]str{ "a*b", "aXb", "a?b", "aXb", "[a]", "a", "]", "a", "-", "b", "c", "\\", "a", "notes.txt", "notestxt", "x", "a", "x", "c", "dx", "bx", "]", "a", "b", "]", "b", "-", "a", "b", "-", "a", "d", "-", "", "a", "", "", "abc", "bab", "xaybzc", "xaybz", "abbbc", "aaaab", "aaab", "aab", "abcabc", "abcab", "abc", "ac", "a", "", "ab", "a", "é", "é", "café", "cafe", "café", "日", "日本語", "日本語", "日本語", "ê", "e", "本", "語", "日本語", "日本語", "é", "e", "readme.txt", "readme.txt", "bx", "bx", "Bx", "Bx", "abc", "abd", "é", "É", "a", "b", "a" }
    let hand_cs = [83]bool{ true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, false, true, false, true, false, true, false, false, false, false, false, false, false }
    let hand_want = [83]bool{ true, false, true, false, true, false, true, false, true, false, true, true, true, true, false, true, false, true, false, true, false, true, true, false, false, true, true, true, false, true, true, false, true, true, false, true, false, true, true, true, false, true, true, true, false, true, false, true, false, true, false, true, false, true, false, true, true, false, true, true, false, true, true, false, true, true, true, true, true, false, true, false, true, false, true, false, true, false, false, true, false, true, true }
    var hand_i = 0usize
    while hand_i < 83 {
        let (hand_hit, hand_error) = mask.matches(hand_masks[hand_i], hand_texts[hand_i], hand_cs[hand_i])
        if hand_error != ok || hand_hit != hand_want[hand_i] { try report("hand", hand_i) }
        hand_i += 1usize
    }
    let list_masks = [13]str{ "*.c;*.h", "*.c;*.h", "*.c;*.h", "a\\;b", "a\\;b", "", ";", "a;", ";a", "*.TXT;*.MD", "*.TXT;*.MD", "[a\\;b]", "x" }
    let list_texts = [13]str{ "x.h", "x.o", "x.c", "a;b", "a", "", "", "a", "", "r.md", "r.md", ";", "x" }
    let list_cs = [13]bool{ true, true, true, true, true, true, true, true, true, false, true, true, true }
    let list_want = [13]bool{ true, false, true, true, false, true, true, true, true, true, false, true, true }
    var list_i = 0usize
    while list_i < 13 {
        let (list_hit, list_error) = mask.matches_any(list_masks[list_i], list_texts[list_i], list_cs[list_i])
        if list_error != ok || list_hit != list_want[list_i] { try report("list", list_i) }
        list_i += 1usize
    }
    let invalid_masks = [16]str{ "[abc", "[", "[!", "[^", "[]", "[!]", "abc\\", "\\", "[c-a]", "[a-", "a[", "x[bc", "[a-c", "[\\", "[a\\", "a*[" }
    var invalid_i = 0usize
    while invalid_i < 16 {
        let (invalid_hit, invalid_error) = mask.matches(invalid_masks[invalid_i], "zzz", true)
        if invalid_error != mask.Invalid || invalid_hit || mask.valid(invalid_masks[invalid_i]) != mask.Invalid { try report("invalid", invalid_i) }
        let (invalid_empty_hit, invalid_empty_error) = mask.matches(invalid_masks[invalid_i], "", true)
        if invalid_empty_error != mask.Invalid || invalid_empty_hit { try report("invalid-empty", invalid_i) }
        invalid_i += 1usize
    }
    let list_invalid = [3]str{ "*.c;[", "[;a]", "a\\" }
    var list_invalid_i = 0usize
    while list_invalid_i < 3 {
        let (list_hit, list_error) = mask.matches_any(list_invalid[list_invalid_i], "a", true)
        if list_error != mask.Invalid || list_hit { try report("list-invalid", list_invalid_i) }
        list_invalid_i += 1usize
    }
    let valid_odd = [13]str{ "[a-]", "[-a]", "[]a]", "[!]a]", "[a-c-e]", "[\\]]", "[^a]", "*", "?", "", "\\\\", "[[]", "[a-a]" }
    var valid_i = 0usize
    while valid_i < 13 {
        if mask.valid(valid_odd[valid_i]) != ok { try report("valid-odd", valid_i) }
        valid_i += 1usize
    }
    try io.print("text mask ok\n")
    ret ok
}
