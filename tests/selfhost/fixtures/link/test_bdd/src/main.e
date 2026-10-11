// `e.test.bdd`: a Gherkin feature with tags, a background, an outline over two example
// rows, a step table, a step nothing defines and a failing step, parsed and run against
// a step-definition struct bound through `e.meta`. The expected counts, scenario names
// and report text are hand-derived from the feature below (21 steps over 6 scenarios).
// Sections: parse shape, a full run and its summary, tag include/exclude filtering, the
// report text, table and capture arguments, and the parse refusals. Every check has its
// own exit code.
use e.os
use e.mem
use e.str
use e.test.bdd as bdd

type World = struct { items: i64, cents: i64, adds: i64 }
error Wrong

fn reset(w: *World) {
    w.items = 0i64
    w.cents = 0i64
    w.adds = 0i64
}

fn an_empty_basket(w: *World, a: *const bdd.Args) -> err {
    if w.items != 0i64 { ret Wrong }
    ret ok
}

fn i_add_int_quoted(w: *World, a: *const bdd.Args) -> err {
    if a.count != 2usize || a.values[1].len == 0usize { ret Wrong }
    w.items += bdd.int_at(a, 0usize)
    w.adds += 1i64
    ret ok
}

fn the_basket_holds_int_items(w: *World, a: *const bdd.Args) -> err {
    if w.items != bdd.int_at(a, 0usize) { ret Wrong }
    ret ok
}

// The table's first row is the header; the second column is a price in cents.
fn these_prices(w: *World, a: *const bdd.Args) -> err {
    if a.rows != 3usize || a.cols != 2usize { ret Wrong }
    var r = 1usize
    while r < a.rows {
        let (cents, parse_error) = str.parse_i64(bdd.cell(a, r, 1usize))
        if parse_error != ok { ret Wrong }
        w.cents += cents
        r += 1usize
    }
    ret ok
}

fn the_price_list_sums_to_int(w: *World, a: *const bdd.Args) -> err {
    if w.cents != bdd.int_at(a, 0usize) { ret Wrong }
    ret ok
}

type Steps = struct {
    an_empty_basket: fn(*World, *const bdd.Args) -> err,
    i_add_int_quoted: fn(*World, *const bdd.Args) -> err,
    the_basket_holds_int_items: fn(*World, *const bdd.Args) -> err,
    these_prices: fn(*World, *const bdd.Args) -> err,
    the_price_list_sums_to_int: fn(*World, *const bdd.Args) -> err
}

fn steps() -> Steps {
    ret Steps { an_empty_basket: an_empty_basket, i_add_int_quoted: i_add_int_quoted, the_basket_holds_int_items: the_basket_holds_int_items, these_prices: these_prices, the_price_list_sums_to_int: the_price_list_sums_to_int }
}

fn feature() -> str {
    ret "# a comment before the feature\n@shop\nFeature: Basket\n  As a shopper I want a basket.\n\n  Background:\n    Given an empty basket\n\n  @fast\n  Scenario: Adding items\n    When I add 3 \"apples\"\n    And I add 2 \"red pears\"\n    Then the basket holds 5 items\n\n  @slow @wip\n  Scenario: Pending step\n    When I add 1 \"kiwi\"\n    Then the total price is shown\n    And the basket holds 1 items\n\n  Scenario Outline: Totals\n    When I add <n> \"<name>\"\n    Then the basket holds <n> items\n\n    Examples:\n      | n | name  |\n      | 1 | fig   |\n      | 4 | grape |\n\n  @fast\n  Scenario: Table\n    Given these prices\n      | item  | cents |\n      | apple | 30    |\n      | pear  | 45    |\n    Then the price list sums to 75\n\n  Scenario: Failing\n    When I add 2 \"plum\"\n    Then the basket holds 9 items\n    And the basket holds 2 items\n"
}

fn checks_parse(a: *mem.Arena) -> i32 {
    var scenarios: [16]bdd.Scenario = zero
    var step_pool: [64]bdd.Step = zero
    var cells: [16]str = zero
    var tags: [16]str = zero
    var d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, feature(), &d) != ok { ret 10i32 }
    if !str.eq(d.feature, "Basket") || d.feature_tag_count != 1usize || !str.eq(d.tags[0], "@shop") { ret 11i32 }
    if d.n_scenarios != 6usize { ret 12i32 }
    if !str.eq(d.scenarios[0].name, "Adding items") || d.scenarios[0].step_count != 4usize { ret 13i32 }
    let first = d.steps[d.scenarios[0].step_start]
    if first.keyword != .Given || !str.eq(first.text, "an empty basket") { ret 14i32 }
    let second = d.steps[d.scenarios[0].step_start + 1usize]
    if second.keyword != .When || !str.eq(second.text, "I add 3 \"apples\"") { ret 15i32 }
    if d.steps[d.scenarios[0].step_start + 2usize].keyword != .And { ret 16i32 }
    // The outline became two scenarios with the example values substituted.
    if !str.eq(d.scenarios[2].name, "Totals #1") || !str.eq(d.scenarios[3].name, "Totals #2") { ret 17i32 }
    if !str.eq(d.steps[d.scenarios[2].step_start + 1usize].text, "I add 1 \"fig\"") { ret 18i32 }
    if !str.eq(d.steps[d.scenarios[3].step_start + 2usize].text, "the basket holds 4 items") { ret 19i32 }
    // The table under a step: header and two rows, two columns.
    let table_step = d.steps[d.scenarios[4].step_start + 1usize]
    if table_step.rows != 3usize || table_step.cols != 2usize { ret 20i32 }
    if !str.eq(d.cells[table_step.cell_start + 4usize], "pear") || !str.eq(d.cells[table_step.cell_start + 5usize], "45") { ret 21i32 }
    // Tags: the feature's reach every scenario.
    if !bdd.has_tag(&d, 0usize, "@fast") || !bdd.has_tag(&d, 0usize, "@shop") || bdd.has_tag(&d, 0usize, "@wip") { ret 22i32 }
    if !bdd.has_tag(&d, 1usize, "@wip") || !bdd.has_tag(&d, 1usize, "@slow") || !bdd.has_tag(&d, 5usize, "@shop") { ret 23i32 }
    ret 0i32
}

fn checks_run(a: *mem.Arena) -> i32 {
    var scenarios: [16]bdd.Scenario = zero
    var step_pool: [64]bdd.Step = zero
    var cells: [16]str = zero
    var tags: [16]str = zero
    var d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, feature(), &d) != ok { ret 30i32 }
    var results: [64]bdd.Outcome = zero
    var by_scenario: [16]bdd.Outcome = zero
    var world: World = zero
    let table = steps()
    let all = bdd.Filter { include: zero, exclude: zero }
    let (sum, run_error) = bdd.run[World, Steps](&world, reset, &table, &d, all, results[0..], by_scenario[0..])
    if run_error != ok { ret 31i32 }
    if sum.scenarios != 6usize || sum.passed != 4usize || sum.failed != 1usize || sum.pending != 1usize || sum.filtered != 0usize { ret 32i32 }
    if sum.steps_passed != 17usize || sum.steps_failed != 1usize || sum.steps_pending != 1usize || sum.steps_skipped != 2usize { ret 33i32 }
    if by_scenario[0] != .Passed || by_scenario[1] != .Pending || by_scenario[5] != .Failed { ret 34i32 }
    // The pending scenario: two passed, one pending, the last skipped.
    let p = d.scenarios[1].step_start
    if results[p] != .Passed || results[p + 1usize] != .Passed || results[p + 2usize] != .Pending || results[p + 3usize] != .Skipped { ret 35i32 }
    var out: [512]u8 = zero
    let want = "pending scenario: Pending step\n  Then the total price is shown: pending\nfailed scenario: Failing\n  Then the basket holds 9 items: failed\n6 scenarios (4 passed, 1 failed, 1 pending, 0 filtered), 21 steps (17 passed, 1 failed, 1 pending, 2 skipped)\n"
    if !str.eq(bdd.report(&d, by_scenario[0..], results[0..], sum, out[0..]), want) { ret 36i32 }
    // Too-small result storage is refused, not run.
    var tiny: [2]bdd.Outcome = zero
    let (_, tiny_error) = bdd.run[World, Steps](&world, reset, &table, &d, all, tiny[0..], by_scenario[0..])
    if tiny_error != bdd.TooSmall { ret 37i32 }
    ret 0i32
}

fn checks_filter(a: *mem.Arena) -> i32 {
    var scenarios: [16]bdd.Scenario = zero
    var step_pool: [64]bdd.Step = zero
    var cells: [16]str = zero
    var tags: [16]str = zero
    var d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, feature(), &d) != ok { ret 40i32 }
    var results: [64]bdd.Outcome = zero
    var by_scenario: [16]bdd.Outcome = zero
    var world: World = zero
    let table = steps()
    var fast: [1]str = zero
    fast[0] = "@fast"
    let only_fast = bdd.Filter { include: fast[0..], exclude: zero }
    let (sum, run_error) = bdd.run[World, Steps](&world, reset, &table, &d, only_fast, results[0..], by_scenario[0..])
    if run_error != ok { ret 41i32 }
    if sum.scenarios != 6usize || sum.filtered != 4usize || sum.passed != 2usize || sum.failed != 0usize || sum.pending != 0usize { ret 42i32 }
    if by_scenario[1] != .Filtered || by_scenario[0] != .Passed || by_scenario[4] != .Passed { ret 43i32 }
    var wip: [1]str = zero
    wip[0] = "@wip"
    let no_wip = bdd.Filter { include: zero, exclude: wip[0..] }
    let (sum2, run2_error) = bdd.run[World, Steps](&world, reset, &table, &d, no_wip, results[0..], by_scenario[0..])
    if run2_error != ok || sum2.filtered != 1usize || sum2.pending != 0usize || sum2.failed != 1usize || sum2.passed != 4usize { ret 44i32 }
    // Include and exclude together: shop minus fast leaves four scenarios.
    var shop: [1]str = zero
    shop[0] = "@shop"
    let mixed = bdd.Filter { include: shop[0..], exclude: fast[0..] }
    let (sum3, run3_error) = bdd.run[World, Steps](&world, reset, &table, &d, mixed, results[0..], by_scenario[0..])
    if run3_error != ok || sum3.filtered != 2usize || sum3.passed != 2usize { ret 45i32 }
    ret 0i32
}

fn checks_refusals(a: *mem.Arena) -> i32 {
    var scenarios: [4]bdd.Scenario = zero
    var step_pool: [8]bdd.Step = zero
    var cells: [8]str = zero
    var tags: [4]str = zero
    var d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, "Feature: x\n  Scenario: s\n    Given a\n      \"\"\"\n      doc\n      \"\"\"\n", &d) != bdd.Unsupported { ret 50i32 }
    if d.error_line != 4u32 { ret 51i32 }
    d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, "Feature: x\n  Given a step outside any scenario\n", &d) != bdd.Invalid { ret 52i32 }
    d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, "Scenario: no feature\n", &d) != bdd.Invalid { ret 53i32 }
    d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, "Feature: x\n  Scenario: s\n    Given t\n      | a | b |\n      | 1 |\n", &d) != bdd.Invalid { ret 54i32 }
    d = bdd.document(scenarios[0..], step_pool[0..], cells[0..], tags[0..])
    if bdd.parse(a, "Feature: x\n  Scenario: a\n    Given a\n  Scenario: b\n    Given a\n  Scenario: c\n    Given a\n  Scenario: d\n    Given a\n  Scenario: e\n    Given a\n", &d) != bdd.TooSmall { ret 55i32 }
    ret 0i32
}

fn main(a: *mem.Arena) -> err {
    var code = checks_parse(a)
    if code == 0i32 { code = checks_run(a) }
    if code == 0i32 { code = checks_filter(a) }
    if code == 0i32 { code = checks_refusals(a) }
    if code != 0i32 { os.exit(code) }
    ret ok
}
