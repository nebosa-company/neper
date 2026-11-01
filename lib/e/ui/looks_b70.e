// Round 70 b: a runner for the Flutter comparison sheets that writes only the Neper pair (neper, neper-dark) at 100 % and 150 %,
// so a new sheet does not litter the Windows and Linux folders. The drawing is the library's own.

use e.fs
use e.mem
use e.ui.looks

fn run_neper(a: *mem.Arena, s: *const looks.Sheet) -> err {
    var scale_index = 0usize
    while scale_index < 2usize {
        var scale: f32 = 1.0
        if scale_index == 1usize { scale = 1.5 }
        var look_index = 0usize
        while look_index < 2usize {
            var look: looks.Look = .Neper
            if look_index == 1usize { look = .NeperDark }
            let ra = looks.rig_scope(a)
            var sized = *s
            sized.cell_w = s.cell_w * looks.neper_scale() + looks.neper_pad_w
            sized.cell_h = s.cell_h * looks.neper_scale() + looks.neper_pad_h
            let (rig, open_error) = looks.open(ra, looks.sheet_width(&sized), looks.sheet_height(&sized), scale)
            if open_error != ok { ret open_error }
            looks.set_look(rig, look)
            let (folder, folder_error) = looks.path_of(ra, looks.look_dir(look), "", "", 1.0, "")
            if folder_error != ok { ret folder_error }
            try fs.make_dirs(ra, folder)
            let (path, path_error) = looks.path_of(ra, looks.look_dir(look), s.name, "", scale, ".png")
            if path_error != ok { ret path_error }
            let (ours, render_error) = looks.render_sheet(rig, &sized, path)
            if render_error != ok { ret render_error }
            looks.close_rig(rig)
            look_index += 1usize
        }
        scale_index += 1usize
    }
    ret ok
}
