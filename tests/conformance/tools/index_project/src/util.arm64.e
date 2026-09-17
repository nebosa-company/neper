// Another target's variant of `util` (D544): not this program's module on x64, so
// the project index leaves it out -- indexed alone it would fail on `nothing`.
fn twice(x: i32) -> i32 {
    ret nothing
}
