// A non-canonical source (D255): the format corpus pins what `fmt` makes of it.
use   e.os
use   e.mem


type   Pair=struct{a:i32,b : i32}

error Odd
fn add( x : i32 , y:i32 )->i32{
  ret x+y*2i32
}
fn   pick(values : [] const i32,index:usize)->i32   {
        let chosen=values[ index ]    // one space before a trailing comment

        if chosen<0i32{ret -chosen}


        ret chosen
}
fn main(a:*mem.Arena,args:[]str)->err {
    var pair:Pair=Pair{a:1i32,b:2i32}
    let total = add(pair.a , pair.b)
    if total!=5i32 { ret Odd }
    var values:[3]i32=zero
    values[0usize]=total
    let slice=values[0usize..2usize]
    let first=pick(slice[..],0usize)
    if first==5i32&&!(total==0i32) { ret ok }
    ret Odd
}
fn nothing() {
}
fn sign(x: i32) -> i32 {
    if x < 0i32 {
        ret -1i32
    }
    else {
        ret 1i32
    }
}
type Wide = struct { first_field_name: i32, second_field_name: i32, third_field_name: i32, fourth_field_name: i32 }
fn long_parameters(first_parameter: i32, second_parameter: i32, third_parameter: i32, fourth_parameter: i32) -> i32 {
    let total = long_parameters(first_parameter,
        second_parameter, third_parameter,
        fourth_parameter)
    ret total
}
