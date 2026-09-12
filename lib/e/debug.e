// Stack frames and symbols, allocation-free. There is no symbol data in a neper
// executable yet and no intrinsic to read the frame chain, so `backtrace` answers
// no frames and `symbolize` an address with empty names and line zero -- the shape
// the fence assigns to missing data, kept honest rather than guessed. When the
// compiler emits a frame walk and a symbol table, both fill in here and no caller
// changes.
type Frame = struct { address: usize, function: str, file: str, line: u32 }

fn backtrace(dst: []Frame) -> []Frame {
    ret dst[0usize..0usize]
}

fn symbolize(address: usize) -> Frame {
    ret Frame { address: address, function: "", file: "", line: 0u32 }
}
