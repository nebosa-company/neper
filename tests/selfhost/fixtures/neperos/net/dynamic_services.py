"""The build server of NeperOS Dynamic for the fixtures (C151, C173): a prompt in, a signed app package out.

Routes, all on the HTTPS test host neper.test (host_services.py hands them over):

  POST /dynamic/make      body {"prompt": "...", "api": 1}; the answer is a text/event-stream (chunked) of
                            event: stage    data: {"stage": 0..3, "note": "..."}    the server's own progress
                            event: done     data: {"id", "name", "version", "size", "sha256", "scan", "attempts"}
                            event: failed   data: {"reason": "..."}                 when no attempt built
  GET  /dynamic/package/<id>   the package (application/x-npkg), `Content-Length`, to be streamed to disk
  GET  /dynamic/revoked        the revocation list, signed ("NREV" ..., package.check_list)

The model is canned (no live model in the suite): a prompt with "dice" gets the dice app, one with "broken" gets a
source that does not compile first and the repaired one when the compiler's diagnostics come back, one with
"hang" a source the scanner refuses, anything else the counter. Each attempt is compiled by the Neper compiler
against the app kit (NEPER_COMPILER names it), twice, and the two images must be byte-identical (a reproducible
build); the scanner (scan_cli, built from neperos/src/scan.e) must pass; the package is signed with the development
server's key (scripts/make_package.py's seed) and every request leaves a line in the audit log.
"""
import hashlib
import json
import os
import pathlib
import struct
import subprocess
import tempfile
import threading
import time

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[4]
KEY = Ed25519PrivateKey.from_private_bytes(bytes(range(1, 33)))
COMPILER = os.environ.get('NEPER_COMPILER', str(REPO / 'build' / 'windows' / 'tests' / 'selfhost' / 'neper-self.exe'))
WORK = pathlib.Path(os.environ.get('NEPER_DYNAMIC_WORK', tempfile.gettempdir())) / 'neper-dynamic'
AUDIT = WORK / 'audit.log'
REVOKED = [b'Revoked app']
LOCK = threading.Lock()
PACKAGES = {}
SCAN_CLI = None


def app_source(title, body_expression, button, marker):
    return ('// Generated for the prompt of a person: %s.\n'
            'use e.mem\nuse e.gfx.scene\nuse appkit\nuse text\nuse ui\n\n'
            'type State = struct { n: usize, hits: ui.Hits }\n\n'
            'fn draw(a: *mem.Arena, builder: *scene.Builder, kit: *appkit.Kit, s: *State) -> err {\n'
            '    s.hits.total = 0usize\n'
            '    let faces = kit.faces\n'
            '    try ui.ground(builder, kit.frame, kit.logical_h, 0.08, 0.09, 0.11)\n'
            '    try ui.centred(a, builder, faces.jost_bold, 28.0, "%s", 206.0, 80.0, ui.light())\n'
            '    try ui.centred(a, builder, faces.jost_bold, 110.0, %s, 206.0, 200.0, ui.light())\n'
            '    try ui.pill(a, builder, &s.hits, faces, 1usize, 106.0, 420.0, 200.0, 64.0, "%s", ui.amber(), 24.0)\n'
            '    try ui.handle(a, builder)\n'
            '    ret ok\n'
            '}\n\n'
            'fn show(a: *mem.Arena, kit: *appkit.Kit, s: *State) -> bool {\n'
            '    let (next, next_error) = appkit.begin(a, kit)\n'
            '    if next_error != ok { ret false }\n'
            '    var builder = next\n'
            '    if draw(a, &builder, kit, s) != ok { ret false }\n'
            '    ret appkit.present(kit, &builder)\n'
            '}\n\n'
            'fn main(a: *mem.Arena, args: []str) -> err {\n'
            '    let (kit_value, kit_error) = appkit.open(a, args, 1usize, "generated")\n'
            '    if kit_error != ok { ret ok }\n'
            '    var kit = kit_value\n'
            '    var s: State = zero\n'
            '    s.n = 0usize\n'
            '    if !show(a, &kit, &s) { ret ok }\n'
            '    ui.say("gen %s shown\\n")\n'
            '    var running = true\n'
            '    while running {\n'
            '        let tap = appkit.next_tap(&kit)\n'
            '        if tap.ended {\n'
            '            running = false\n'
            '        } else if tap.tick {\n'
            '            appkit.answer(appkit.ANSWER_NONE)\n'
            '        } else if tap.y >= 896.0 {\n'
            '            ui.say("gen %s home\\n")\n'
            '            appkit.leave()\n'
            '            running = false\n'
            '        } else {\n'
            '            let id = ui.hit_at(&s.hits, tap.x, tap.y)\n'
            '            if id == 1usize {\n'
            '                s.n += 1usize\n'
            '                ui.say("gen %s count ")\n'
            '                ui.say_num(s.n)\n'
            '                ui.say("\\n")\n'
            '                if !show(a, &kit, &s) { appkit.answer(appkit.ANSWER_NONE) }\n'
            '            } else {\n'
            '                appkit.answer(appkit.ANSWER_NONE)\n'
            '            }\n'
            '        }\n'
            '    }\n'
            '    ret ok\n'
            '}\n') % (title, title, body_expression, button, marker, marker, marker)


def model(prompt, attempt, diagnostics):
    """The canned model: the source it writes for `prompt` at its `attempt`-th try, given the diagnostics of the last."""
    words = prompt.lower()
    if 'dice' in words or 'die' in words:
        name, expression, button = 'Dice roller', 'ui.number(a, 1usize + (s.n * 5usize + 3usize) % 6usize)', 'Roll'
    else:
        name, expression, button = 'Counter', 'ui.number(a, s.n)', '+1'
    source = app_source(name, expression, button, name.split()[0].lower())
    if 'broken' in words and attempt == 0:
        # A misspelt local, the compiler says which name is unknown.
        source = source.replace('s.n += 1usize', 's.m += 1usize')
    if 'hang' in words:
        source = source.replace('    var running = true\n', '    var running = true\n    while true {\n        let spin = 1usize\n    }\n')
    return name, source


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=300, **kwargs)


def scan_cli():
    """The scanner of neperos/src/scan.e as a host program, built once."""
    global SCAN_CLI
    if SCAN_CLI is None:
        exe = WORK / 'scan_cli.exe'
        result = run([COMPILER, 'emit-executable', str(REPO / 'neperos' / 'src' / 'scan_cli.e'), str(REPO), 'x64', 'windows', str(exe)])
        if result.returncode != 0:
            raise RuntimeError('scan_cli did not build: ' + result.stdout + result.stderr)
        SCAN_CLI = exe
    return SCAN_CLI


def build(source, ident):
    """Compile `source` as an app of the kit, twice; (image or None, diagnostics, reproducible)."""
    path = REPO / 'neperos' / 'src' / ('dyn_%s.e' % ident)
    images = []
    text = ''
    try:
        path.write_text(source, encoding='utf-8', newline='\n')
        for n in range(2):
            out = WORK / ('%s-%d.img' % (ident, n))
            result = run([COMPILER, 'emit-executable', str(path), str(REPO), 'aarch64', 'neperos', str(out)])
            text = (result.stdout + result.stderr).strip()
            if result.returncode != 0 or not out.exists():
                return None, text, False
            images.append(out.read_bytes())
    finally:
        if path.exists():
            path.unlink()
    return images[0], text, images[0] == images[1]


def sign_package(manifest, image):
    body = b'NPKG' + bytes([1]) + struct.pack('<H', len(manifest)) + manifest + struct.pack('<I', len(image)) + image
    return body + KEY.sign(body)


def signed_list(names):
    text = b''.join(name + b'\n' for name in names)
    body = b'NREV' + bytes([1]) + struct.pack('<H', len(text)) + text
    return body + KEY.sign(body)


def audit(entry):
    WORK.mkdir(parents=True, exist_ok=True)
    entry['time'] = time.strftime('%Y-%m-%dT%H:%M:%S')
    with open(AUDIT, 'a', encoding='utf-8') as log:
        log.write(json.dumps(entry, sort_keys=True) + '\n')


def make(handler, raw):
    """POST /dynamic/make: the stages as events, then the package id."""
    request = json.loads(raw.decode('utf-8') or '{}')
    prompt = str(request.get('prompt', ''))
    handler.send_response(200)
    handler.send_header('Content-Type', 'text/event-stream')
    handler.send_header('Transfer-Encoding', 'chunked')
    handler.send_header('Connection', 'close')
    handler.end_headers()

    def event(kind, data):
        payload = ('event: %s\ndata: %s\n\n' % (kind, json.dumps(data))).encode('utf-8')
        handler.wfile.write(('%x\r\n' % len(payload)).encode() + payload + b'\r\n')
        handler.wfile.flush()

    def finish():
        handler.wfile.write(b'0\r\n\r\n')
        handler.wfile.flush()

    WORK.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256(prompt.encode('utf-8')).hexdigest()[:12]
    with LOCK:
        diagnostics = ''
        image = None
        reproducible = False
        name = 'App'
        source = ''
        attempts = 0
        event('stage', {'stage': 0, 'note': 'a model is writing the app'})
        time.sleep(0.3)
        for attempt in range(3):
            attempts = attempt + 1
            name, source = model(prompt, attempt, diagnostics)
            event('stage', {'stage': 1, 'note': 'compiling with the Neper compiler, attempt %d' % attempts})
            image, diagnostics, reproducible = build(source, digest)
            if image is not None:
                break
            # The diagnostics go back to the model, readably: code, place, what was expected.
            first = diagnostics.splitlines()[0] if diagnostics else 'the compiler said nothing'
            event('stage', {'stage': 1, 'note': 'attempt %d failed: %s' % (attempts, first[:60])})
        if image is None:
            audit({'prompt_sha': digest, 'result': 'failed', 'attempts': attempts})
            event('failed', {'reason': 'The app did not build after %d tries: %s' % (attempts, diagnostics.splitlines()[0][:80] if diagnostics else '')})
            finish()
            return
        event('stage', {'stage': 2, 'note': 'scanning the source: the network, storage and raw access'})
        source_path = WORK / ('%s.e' % digest)
        source_path.write_text(source, encoding='utf-8', newline='\n')
        scan = run([str(scan_cli()), str(source_path)])
        scan_text = scan.stdout.strip()
        if scan.returncode != 0:
            audit({'prompt_sha': digest, 'result': 'refused', 'scan': scan_text})
            event('failed', {'reason': 'The scan refused the app: ' + scan_text.splitlines()[0]})
            finish()
            return
        image_sha = hashlib.sha256(image).hexdigest()
        manifest = ('name=%s\nversion=1\napi=1\nentry=main\ncapabilities=\nscan=passed\nreproducible=%s\nbuild=%s'
                    % (name, 'yes' if reproducible else 'no', image_sha[:16])).encode()
        package = sign_package(manifest, image)
        ident = hashlib.sha256(package).hexdigest()[:16]
        PACKAGES[ident] = package
        audit({'prompt_sha': digest, 'result': 'signed', 'image_sha': image_sha, 'attempts': attempts,
               'package': ident, 'reproducible': reproducible})
        event('stage', {'stage': 3, 'note': 'signed with the server key'})
        time.sleep(0.2)
        event('done', {'id': ident, 'name': name, 'version': 1, 'size': len(package), 'sha256': image_sha,
                       'scan': 'passed', 'attempts': attempts})
        finish()


def get(handler, host, path):
    """Answer a GET of the build server; False when the path is not its own."""
    if host != 'neper.test':
        return False
    if path.startswith('/dynamic/package/'):
        package = PACKAGES.get(path[len('/dynamic/package/'):])
        if package is None:
            handler.reply(404, b'{"error":"unknown package"}', 'application/json')
        else:
            handler.reply(200, package, 'application/x-npkg')
        return True
    if path == '/dynamic/revoked':
        handler.reply(200, signed_list(REVOKED), 'application/x-nrev')
        return True
    return False


def post(handler, host, path, raw):
    if host == 'neper.test' and path == '/dynamic/make':
        make(handler, raw)
        return True
    return False
