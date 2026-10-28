"""Generate lib/x/khronos/gl.e and lib/x/khronos/egl.e from the Khronos headers in
scripts/khronos (D5883, D5885). The headers are themselves generated from the Khronos XML
registry; each `#ifndef GL_VERSION_x_y` / `GL_ES_VERSION_x_y` / `EGL_VERSION_x_y` block is
one registry feature, which is what profile membership is read from.

    python scripts/gen_khronos_gl.py          write both modules
    python scripts/gen_khronos_gl.py --check  exit 1 if either would change
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / 'scripts' / 'khronos'
OUT = ROOT / 'lib' / 'x' / 'khronos'

# Extension blocks whose constants are generated; their entry points are not.
GL_EXTENSIONS = ['GL_ARB_gpu_shader_int64', 'GL_KHR_shader_subgroup']
EGL_EXTENSIONS = ['EGL_KHR_platform_x11', 'EGL_MESA_platform_surfaceless', 'EGL_ANGLE_platform_angle',
                  'EGL_ANGLE_platform_angle_d3d', 'EGL_ANGLE_platform_angle_vulkan',
                  'EGL_ANGLE_platform_angle_device_type_swiftshader']

# Profile bits, in the order of `gl.Profile`'s members.
GL_PROFILES = [('GL', (3, 3)), ('GL', (4, 3)), ('GL', (4, 6)), ('ES', (3, 0)), ('ES', (3, 1)), ('ES', (3, 2))]

KEYWORDS = set('as break case const continue default defer else enum error extern false fn for if in isize let nil '
               'nocheck ok own resource ret shared struct switch true try type undef union unreachable use usize var '
               'when while zero'.split())

SCALARS = {
    'GLenum': 'u32', 'GLbitfield': 'u32', 'GLuint': 'u32', 'GLint': 'i32', 'GLsizei': 'i32', 'GLboolean': 'u8',
    'GLbyte': 'i8', 'GLubyte': 'u8', 'GLshort': 'i16', 'GLushort': 'u16', 'GLfloat': 'f32', 'GLclampf': 'f32',
    'GLdouble': 'f64', 'GLclampd': 'f64', 'GLintptr': 'isize', 'GLsizeiptr': 'isize', 'GLint64': 'i64',
    'GLuint64': 'u64', 'GLhalf': 'u16', 'GLchar': 'u8', 'GLfixed': 'i32', 'GLsync': 'usize',
    'GLDEBUGPROC': 'usize', 'GLint64EXT': 'i64', 'GLuint64EXT': 'u64',
    'EGLBoolean': 'u32', 'EGLint': 'i32', 'EGLenum': 'u32', 'EGLAttrib': 'isize', 'EGLTime': 'u64',
    'EGLDisplay': 'usize', 'EGLConfig': 'usize', 'EGLSurface': 'usize', 'EGLContext': 'usize',
    'EGLImage': 'usize', 'EGLSync': 'usize', 'EGLClientBuffer': 'usize', 'EGLNativeDisplayType': 'usize',
    'EGLNativeWindowType': 'usize', 'EGLNativePixmapType': 'usize',
    '__eglMustCastToProperFunctionPointerType': 'usize', 'char': 'u8', 'void': 'void',
}


def snake(name):
    """glTexStorage2DMultisample -> tex_storage_2d_multisample: a break at each lower-to-upper
    and letter-to-digit step, and before the last capital of an acronym; a capital right after
    a digit stays with it only as `nD` (2D, 3D)."""
    out = []
    for i, c in enumerate(name):
        prev = name[i - 1] if i else ''
        nxt = name[i + 1] if i + 1 < len(name) else ''
        brk = False
        if c.isupper():
            if prev.islower():
                brk = True
            elif prev.isdigit():
                brk = not (c == 'D' and not nxt.islower())
            elif prev.isupper() and nxt.islower():
                brk = True
        elif c.isdigit() and prev.isalpha():
            brk = True
        if brk and out:
            out.append('_')
        out.append(c.lower())
    return ''.join(out)


def blocks(text):
    """Yield (block name, lines) for every top-level `#ifndef NAME ... #endif /* NAME */`."""
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = re.match(r'#ifndef (\w+)$', lines[i])
        if m:
            name = m.group(1)
            end = '#endif /* %s */' % name
            j = i + 1
            while j < len(lines) and lines[j].strip() != end:
                j += 1
            if j < len(lines):
                yield name, lines[i + 1:j]
                i = j
        i += 1


def number(raw, kind):
    """A constant's value and neper type, or None for a define that is not a number."""
    raw = raw.strip()
    m = re.match(r'EGL_CAST\((\w+),\s*(-?\w+)\)$', raw) or re.match(r'\(\((\w+)\)\s*(-?\w+)\)$', raw)
    cast = None
    if m:
        cast, raw = m.group(1), m.group(2)
    m = re.match(r'(-?)(0x[0-9A-Fa-f]+|\d+)(ull|u|ULL|U)?$', raw)
    if not m:
        return None
    value = int(m.group(2), 0) * (-1 if m.group(1) else 1)
    if cast:
        ty = SCALARS.get(cast, 'usize')
        if ty == 'usize' and value < 0:
            ty = 'isize'
        if cast == 'EGLnsecsANDROID':
            ty = 'i64'
    elif value > 0xFFFFFFFF:
        ty = 'u64'
    elif value < 0:
        ty = 'i32'
    else:
        ty = kind
    return value, ty


def literal(value, ty):
    return '%d%s' % (value, ty)


def ctype(decl):
    """A C parameter or return declaration (without its name) as a neper type."""
    decl = decl.replace('const', ' const ').strip()
    stars = decl.count('*')
    words = [w for w in re.split(r'[\s*]+', decl) if w and w != 'const' and w != 'struct']
    base = words[0]
    if stars == 0:
        if base not in SCALARS:
            raise SystemExit('unknown type %r' % decl)
        return SCALARS[base]
    if stars >= 2 or base in ('void', '_cl_context', '_cl_event'):
        return '*void' if stars == 1 else 'usize'
    inner = SCALARS.get(base)
    if inner is None or inner == 'void':
        return '*void'
    return ('*const ' if decl.lstrip().startswith('const') else '*') + inner


def parameter_types(params):
    params = params.strip()
    if params in ('', 'void'):
        return []
    out = []
    for p in params.split(','):
        p = p.strip()
        m = re.match(r'(.*?)(\w+)(\s*\[\d*\])?$', p)
        decl, array = m.group(1), m.group(3)
        if not decl.strip():
            decl = p
        if array:
            decl += '*'
        out.append(ctype(decl))
    return out


def parse(path, proto, kind, wanted):
    """Constants and entry points per wanted block: {block: (constants, functions)}."""
    text = path.read_text(encoding='utf-8')
    result = {}
    for name, lines in blocks(text):
        if not wanted(name):
            continue
        constants, functions = [], []
        for line in lines:
            m = re.match(r'#define (\w+)\s+(.+?)\s*$', line)
            if m and m.group(1) != name:
                n = number(m.group(2), kind)
                if n is not None:
                    constants.append((m.group(1), n))
                continue
            m = re.match(proto, line)
            if m:
                ret, fname, params = m.group(1), m.group(2), m.group(3)
                functions.append((fname, ctype(ret), parameter_types(params)))
        result[name] = (constants, functions)
    return result


def feature_version(block, prefix):
    m = re.match(prefix + r'(\d)_(\d)$', block)
    return (int(m.group(1)), int(m.group(2))) if m else None


class Module:
    def __init__(self, cprefix, fprefix):
        self.cprefix, self.fprefix = cprefix, fprefix
        self.constants = {}
        self.functions = {}
        self.masks = {}

    def constant(self, cname, value):
        name = cname[len(self.cprefix):]
        if not re.match(r'[A-Z_]', name):
            raise SystemExit('constant %s does not start with a letter' % cname)
        old = self.constants.get(name)
        if old is not None and old[0] != value[0]:
            raise SystemExit('constant %s has two values' % cname)
        self.constants[name] = value

    def function(self, entry, bit):
        cname, ret, params = entry
        old = self.functions.get(cname)
        if old is not None and old != (ret, params):
            raise SystemExit('%s has two signatures' % cname)
        self.functions[cname] = (ret, params)
        self.masks[cname] = self.masks.get(cname, 0) | bit

    def emit(self, prelude, header, chunk=100):
        prelude_text = prelude.read_text(encoding='utf-8')
        dispatch = self.fprefix == 'gl'
        taken = set(re.findall(r'^fn (\w+)', prelude_text, re.M))
        out = [header, prelude_text.rstrip('\n'), '', '// ---- generated below ----', '']
        for name in sorted(self.constants):
            value, ty = self.constants[name]
            out.append('const %s: %s = %s' % (name, ty, literal(value, ty)))
        out.append('')
        names = sorted(self.functions)
        signatures = {}
        for cname in names:
            ret, params = self.functions[cname]
            signatures.setdefault((ret, tuple(params)), len(signatures))
        for (ret, params), k in sorted(signatures.items(), key=lambda s: s[1]):
            tail = '' if ret == 'void' else ' -> ' + ret
            out.append('@cc(c)')
            out.append('type F%d = extern fn(%s)%s' % (k, ', '.join(params), tail))
            out.append('type U%d = union { function: F%d, bits: usize }' % (k, k))
        out.append('')
        out.append('const ENTRY_COUNT: usize = %dusize' % len(names))
        if dispatch:
            out.append('var procs: [64][%d]usize = zero' % len(names))
        else:
            out.append('var procs: [%d]usize = zero' % len(names))
        out.append('')
        # Each entry's slot, for `present` on one a profile does not require.
        for i, cname in enumerate(names):
            entry = snake(cname[len(self.fprefix):]).upper() + '_ENTRY'
            if entry in self.constants:
                raise SystemExit('%s collides with a constant' % entry)
            out.append('const %s: usize = %dusize' % (entry, i))
        out.append('')
        for c in range(0, len(names), chunk):
            if dispatch:
                out.append('fn load_entries_%d(a: *mem.Arena, resolve: Resolve, context: usize, slot: usize, bit: u8) -> err {' % (c // chunk))
            else:
                out.append('fn load_entries_%d(a: *mem.Arena, resolve: Resolve, context: usize, bit: u8) -> err {' % (c // chunk))
            for i in range(c, min(c + chunk, len(names))):
                cname = names[i]
                if dispatch:
                    out.append('    if fetch(a, resolve, context, slot, %dusize, "%s", bit & %du8) != ok { ret Unsupported }'
                               % (i, cname, self.masks[cname]))
                else:
                    out.append('    if fetch(a, resolve, context, %dusize, "%s", bit & %du8) != ok { ret Unsupported }'
                               % (i, cname, self.masks[cname]))
            out.append('    ret ok')
            out.append('}')
            out.append('')
        if dispatch:
            out.append('fn load_entries(a: *mem.Arena, resolve: Resolve, context: usize, slot: usize, bit: u8) -> err {')
        else:
            out.append('fn load_entries(a: *mem.Arena, resolve: Resolve, context: usize, bit: u8) -> err {')
        for c in range(0, len(names), chunk):
            if dispatch:
                out.append('    if load_entries_%d(a, resolve, context, slot, bit) != ok { ret Unsupported }' % (c // chunk))
            else:
                out.append('    if load_entries_%d(a, resolve, context, bit) != ok { ret Unsupported }' % (c // chunk))
        out.append('    ret ok')
        out.append('}')
        out.append('')
        seen = set()
        for i, cname in enumerate(names):
            ret, params = self.functions[cname]
            k = signatures[(ret, tuple(params))]
            fname = snake(cname[len(self.fprefix):])
            if fname in KEYWORDS or fname in taken or fname in seen:
                raise SystemExit('%s maps to %s, which is taken' % (cname, fname))
            seen.add(fname)
            args = ', '.join('p%d: %s' % (j, t) for j, t in enumerate(params))
            call = 'pun.function(%s)' % ', '.join('p%d' % j for j in range(len(params)))
            tail = '' if ret == 'void' else ' -> ' + ret
            body = call if ret == 'void' else 'ret ' + call
            out.append('fn %s(%s)%s {' % (fname, args, tail))
            out.append('    var pun: U%d = zero' % k)
            if dispatch:
                out.append('    pun.bits = address(%dusize)' % i)
            else:
                out.append('    pun.bits = procs[%dusize]' % i)
            out.append('    %s' % body)
            out.append('}')
        return '\n'.join(out) + '\n'


def gl_module():
    m = Module('GL_', 'gl')
    wanted = lambda b: b.startswith('GL_VERSION_') or b.startswith('GL_ES_VERSION_') or b in GL_EXTENSIONS
    core = parse(SRC / 'glcorearb.h', r'GLAPI (.+?) ?APIENTRY (gl\w+) \((.*)\);$', 'u32', wanted)
    es = parse(SRC / 'gl32.h', r'GL_APICALL (.+?) ?GL_APIENTRY (gl\w+) \((.*)\);$', 'u32', wanted)
    for source, prefix, api in ((core, 'GL_VERSION_', 'GL'), (es, 'GL_ES_VERSION_', 'ES')):
        for block, (constants, functions) in source.items():
            version = feature_version(block, prefix)
            if version is None and block not in GL_EXTENSIONS:
                continue
            for cname, value in constants:
                m.constant(cname, value)
            if version is None:
                continue
            bit = 0
            for k, (papi, pversion) in enumerate(GL_PROFILES):
                if papi == api and version <= pversion:
                    bit |= 1 << k
            for entry in functions:
                m.function(entry, bit)
    return m


def egl_module():
    m = Module('EGL_', 'egl')
    proto = r'EGLAPI (.+?) ?EGLAPIENTRY (egl\w+) ?\((.*)\);$'
    core = parse(SRC / 'egl.h', proto, 'i32', lambda b: b.startswith('EGL_VERSION_'))
    for block, (constants, functions) in core.items():
        for cname, value in constants:
            if cname in ('EGL_TRUE', 'EGL_FALSE'):
                value = (value[0], 'u32')
            m.constant(cname, value)
        # EGL 1.4 is required; 1.5's entries are filled when present (SwiftShader stops at 1.4).
        for entry in functions:
            m.function(entry, 2 if block == 'EGL_VERSION_1_5' else 1)
    for path in ('eglext.h', 'eglext_angle.h'):
        for block, (constants, functions) in parse(SRC / path, proto, 'i32', lambda b: b in EGL_EXTENSIONS).items():
            for cname, value in constants:
                m.constant(cname, value)
    return m


HEADER = ('// GENERATED by scripts/gen_khronos_gl.py from the Khronos headers in scripts/khronos (D5883, D5885).\n'
          '// Edit the generator or %s, never this file.\n')


def main():
    outputs = {
        OUT / 'gl.e': gl_module().emit(SRC / 'gl.prelude.e', HEADER % 'scripts/khronos/gl.prelude.e'),
        OUT / 'egl.e': egl_module().emit(SRC / 'egl.prelude.e', HEADER % 'scripts/khronos/egl.prelude.e'),
    }
    check = '--check' in sys.argv
    stale = False
    for path, text in outputs.items():
        current = path.read_text(encoding='utf-8') if path.exists() else None
        if current != text:
            stale = True
            if not check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(text, encoding='utf-8', newline='\n')
                print('wrote %s (%d bytes)' % (path.relative_to(ROOT), len(text)))
    if check and stale:
        print('generated Khronos modules are stale; run scripts/gen_khronos_gl.py')
        sys.exit(1)


if __name__ == '__main__':
    main()
