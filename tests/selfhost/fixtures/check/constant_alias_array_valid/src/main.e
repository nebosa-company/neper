use dep as d

type Buffer = [WIDTH]u8
type ForeignBuffer = [d.FOREIGN_WIDTH]u8
const WIDTH: usize = 4usize

fn local(value: Buffer) -> [4usize]u8 {
    ret value
}

fn foreign(value: ForeignBuffer) -> [2usize]u8 {
    ret value
}
