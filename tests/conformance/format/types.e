// A second format fixture (D284): type bodies, an enum, a generic signature and a
// switch, written badly.
type   Wide=struct{
first_field_name:i32,second_field_name:i32,third_field_name:i32,fourth_field_name:i32,fifth_field_name:i32}
type Small=struct{
    a:i32,
    b:i32,
}
type Colour=enum u8{Red,Green,Blue}
fn first[T:type](values:[]const T)->T{
ret values[0usize]
}
fn name(colour:Colour)->str{
    switch colour{
    case .Red:
    ret "red"
    case   .Green:
        ret "green"
    case .Blue:
      ret "blue"
    }
}
fn literals(Flag: bool) -> i32 {
    let small = Small {
        a: 1i32,
        b: 2i32,
    }
    if Flag { ret small.a }
    let wide = Wide { first_field_name: 100000000i32, second_field_name: 200000000i32, third_field_name: 3i32, fourth_field_name: 4i32, fifth_field_name: 5i32 }
    ret wide.first_field_name + small.b
}
@packed
@align(8)
type Packed=struct{a:u8,b:u32}
