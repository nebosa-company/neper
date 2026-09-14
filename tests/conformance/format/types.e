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
