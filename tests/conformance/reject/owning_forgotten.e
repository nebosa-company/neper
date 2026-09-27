// An owning list never ended (D1568, H01): it is a resource owed to
// `list.owning_finish`, and the exit that forgets it is E-SAFETY-0002.
use e.mem
use e.os
use e.data.list

fn main(a: *mem.Arena) -> err {
    var (files, made) = list.owning[os.File](a, 1usize)
    if made != ok {
        list.owning_finish[os.File](files)
        ret made
    }
    ret ok
}
