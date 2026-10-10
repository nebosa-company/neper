# -*- coding: utf-8 -*-
"""Reference vectors for `x.migrate` (T031): run petcow's own importers over fixed and random documents.

Usage:  python scripts/migrate_reference.py REFERENCE_EXE

REFERENCE_EXE is a build of petcow's `migrate_ansible/salt/puppet/chef` (src/migrate.rs lines 990-2569 with the
error and naming shims; see docs/petcow.md F4) that takes `MODE FILE PROJECT` and prints `migrated: N`, one
`warning: ...` line each, `---` and the YAML. The script writes tests/selfhost/fixtures/link/x_migrate/src/main.e
from scripts/migrate_fixture_template.e: one JSON line per case, `{"k","p","src","e"}`.
"""
import json
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x7031)


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


WORDS = ["nginx", "curl", "git", "redis", "web01", "deploy", "backup", "app", "ops", "www-data", "telnet", "vim"]
PATHS = ["/etc/motd", "/etc/app.conf", "/var/www", "/opt/app", "/srv/data", "/etc/hosts", "/tmp/x y", "/etc/cron.d/job"]
MODES = ["0644", "0755", "0600", "1777"]
CRONF = ["*", "0", "5", "*/10", "1,15", "2-4"]
CMDS = ["systemctl reload nginx", "echo hi", "/usr/bin/backup --full", "touch /tmp/ok", "ls -l 'a b'"]
VERS = ["1.2.3", "2.31.0", "0.9", "3"]
URLS = ["https://example.com/app.git", "git@host:team/app.git"]
KEYS = ["ssh-rsa AAAAB3Nza user@host", "ssh-ed25519 AAAAC3Nz key"]


def dq(s):
    return json.dumps(s, ensure_ascii=True)


# --- ansible -------------------------------------------------------------------------------------------------------

def scalar_yaml(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    return dq(v) if isinstance(v, str) else str(v)


def mapping_yaml(m, indent):
    pad = " " * indent
    out = []
    for k, v in m.items():
        if isinstance(v, dict):
            out.append("%s%s:" % (pad, k))
            out.append(mapping_yaml(v, indent + 2))
        elif isinstance(v, list):
            out.append("%s%s:" % (pad, k))
            for item in v:
                if isinstance(item, dict):
                    first = True
                    for kk, vv in item.items():
                        out.append("%s  %s%s: %s" % (pad, "- " if first else "  ", kk, scalar_yaml(vv)))
                        first = False
                else:
                    out.append("%s  - %s" % (pad, scalar_yaml(item)))
        else:
            out.append("%s%s: %s" % (pad, k, scalar_yaml(v)))
    return "\n".join(out)


def ansible_task():
    module = pick(["apt", "yum", "dnf", "package", "service", "systemd", "copy", "command", "shell", "user", "group",
                   "cron", "lineinfile", "file", "sysctl", "hostname", "timezone", "mount", "authorized_key", "git",
                   "pip", "template", "debug", "uri"])
    prefix = pick(["", "", "ansible.builtin.", "community.general."])
    args = {}
    name = pick(WORDS)
    state = pick(["present", "absent", "removed", "started", "stopped", "latest"])
    if module in ("apt", "yum", "dnf", "package"):
        args = {"name": name, "state": state}
    elif module in ("service", "systemd"):
        args = {"name": name, "state": pick(["started", "stopped", "restarted"])}
        if chance(0.5):
            args["enabled"] = chance(0.5)
    elif module == "copy":
        args = {"dest": pick(PATHS)}
        if chance(0.7):
            args["content"] = pick(["hello", "a: b\nc: d", "x"])
        else:
            args["src"] = "files/x"
        if chance(0.5):
            args["mode"] = pick(MODES)
    elif module in ("command", "shell"):
        if chance(0.5):
            return {"name": pick(WORDS), prefix + module: pick(CMDS)}
        args = {"cmd": pick(CMDS)} if chance(0.8) else {"chdir": "/"}
    elif module == "user":
        args = {"name": name, "state": pick(["present", "absent"])}
        if chance(0.5):
            args["shell"] = "/bin/bash"
        if chance(0.4):
            args["home"] = "/home/" + name
        if chance(0.4):
            args["system"] = chance(0.5)
    elif module == "group":
        args = {"name": name, "state": pick(["present", "absent"])}
    elif module == "cron":
        args = {"name": pick(WORDS)}
        for f in ("minute", "hour", "day", "month", "weekday"):
            if chance(0.5):
                args[f] = pick(CRONF)
        if chance(0.7):
            args["job"] = pick(CMDS)
        if chance(0.3):
            args["state"] = "absent"
    elif module == "lineinfile":
        args = {"path": pick(PATHS)} if chance(0.8) else {"dest": pick(PATHS)}
        if chance(0.3):
            args["regexp"] = "^x"
        if chance(0.85):
            args["line"] = pick(["foo=bar", "PermitRootLogin no"])
        if chance(0.3):
            args["state"] = "absent"
    elif module == "file":
        args = {"path": pick(PATHS)} if chance(0.8) else {"dest": pick(PATHS)}
        args["state"] = pick(["directory", "link", "touch", "absent", "file"])
        if chance(0.5):
            args["mode"] = pick(MODES)
        if chance(0.7):
            args["src"] = "/opt/x"
    elif module == "sysctl":
        args = {"name": pick(["vm.swappiness", "net.ipv4.ip_forward"])}
        if chance(0.85):
            args["value"] = pick(["1", "10", "0"])
    elif module in ("hostname", "timezone"):
        args = {"name": pick(["web-01", "Europe/Sofia"])}
    elif module == "mount":
        args = {"path": pick(PATHS), "src": "/dev/sdb1", "fstype": pick(["ext4", "xfs"])} if chance(0.6) else {"name": pick(PATHS), "src": "/dev/x"}
        if chance(0.3):
            args["state"] = pick(["absent", "unmounted", "mounted"])
        if chance(0.4):
            args["opts"] = "noatime"
    elif module == "authorized_key":
        args = {"user": name, "key": pick(KEYS)}
        if chance(0.3):
            args["state"] = "absent"
    elif module == "git":
        args = {"repo": pick(URLS), "dest": pick(PATHS)}
        if chance(0.5):
            args["version"] = "main"
    elif module == "pip":
        args = {"name": pick(["requests", "flask"])}
        if chance(0.5):
            args["version"] = pick(VERS)
        if chance(0.3):
            args["state"] = "absent"
    else:
        args = {"msg": "x"}
    for k in list(args):
        if chance(0.04):
            del args[k]
    task = {}
    if chance(0.8):
        task["name"] = "do " + pick(WORDS)
    if chance(0.6):
        task[prefix + module] = args
    else:
        task[prefix + module] = args
    for extra in ("become", "when", "tags", "register", "notify", "ignore_errors"):
        if chance(0.12):
            task[extra] = "x" if extra != "become" else True
    return task


def ansible_playbook():
    plays = []
    for _ in range(rng.randrange(1, 4)):
        play = {}
        if chance(0.85):
            play["name"] = pick(["Web", "DB", "all things"])
        if chance(0.85):
            play["hosts"] = pick(["all", "web", "db_servers", "web:db", "!x", "webservers-1"])
        if chance(0.9):
            play["tasks"] = [ansible_task() for _ in range(rng.randrange(0, 6))]
        plays.append(play)
    lines = []
    for p in plays:
        first = True
        for k, v in p.items():
            if isinstance(v, list):
                lines.append("  %s:" % k)
                for t in v:
                    ks = list(t.items())
                    for i, (tk, tv) in enumerate(ks):
                        lead = "    - " if i == 0 else "      "
                        if isinstance(tv, dict):
                            if rng.random() < 0.5:
                                lines.append("%s%s:" % (lead, tk))
                                lines.append(mapping_yaml(tv, 8))
                            else:
                                lines.append("%s%s: %s" % (lead, tk, json.dumps(tv)))
                        else:
                            lines.append("%s%s: %s" % (lead, tk, scalar_yaml(tv)))
            else:
                lines.append("%s%s: %s" % ("- " if first else "  ", k, scalar_yaml(v)))
                first = False
        if first:
            lines.append("- {}")
    return "\n".join(lines) + "\n"


# --- salt ----------------------------------------------------------------------------------------------------------

def salt_state():
    func = pick(["pkg.installed", "pkg.latest", "pkg.removed", "pkg.purged", "service.running", "service.enabled",
                 "service.dead", "service.disabled", "file.managed", "cmd.run", "cmd.script", "user.present",
                 "user.absent", "group.present", "group.absent", "file.directory", "file.line", "cron.present",
                 "cron.absent", "sysctl.present", "timezone.system", "mount.mounted", "mount.unmounted",
                 "pip.installed", "pip.removed", "git.latest", "ssh_auth.present", "ssh_auth.absent",
                 "weird.thing", "test.nop"])
    args = []
    if chance(0.7):
        args.append(("name", pick(WORDS + PATHS[:3])))
    if func.startswith("service") and chance(0.5):
        args.append(("enable", pick(["True", "False", "true"])))
    if func == "file.managed":
        if chance(0.7):
            args.append(("contents", pick(["managed", "a\nb"])))
        else:
            args.append(("source", "salt://x"))
        if chance(0.5):
            args.append(("mode", pick(MODES)))
    if func == "file.directory" and chance(0.5):
        args.append(("mode", pick(MODES)))
    if func == "file.line":
        if chance(0.8):
            args.append(("content", "foo=bar"))
        if chance(0.4):
            args.append(("mode", pick(["delete", "ensure"])))
    if func.startswith("cron"):
        for f in ("minute", "hour", "daymonth", "month", "dayweek"):
            if chance(0.5):
                args.append((f, pick(CRONF)))
    if func == "sysctl.present" and chance(0.85):
        args.append(("value", pick(["1", "10"])))
    if func == "mount.mounted":
        if chance(0.85):
            args.append(("device", "/dev/sdb1"))
        if chance(0.85):
            args.append(("fstype", "ext4"))
        if chance(0.5):
            args.append(("opts", pick(["noatime", ["noatime", "nodev"]])))
    if func == "git.latest":
        if chance(0.85):
            args.append(("target", pick(PATHS)))
        if chance(0.5):
            args.append(("rev", "v1"))
    if func.startswith("ssh_auth") and chance(0.85):
        args.append(("user", pick(WORDS)))
    if func.startswith("pip") and chance(0.4):
        args = [("name", "requests==%s" % pick(VERS))]
    return func, args


def salt_file():
    out = []
    for i in range(rng.randrange(1, 7)):
        sid = pick(WORDS + ["requests==2.31.0", "/etc/motd"]) + (str(i) if chance(0.3) else "")
        if chance(0.05):
            out.append("include:\n  - common")
            continue
        if chance(0.05):
            out.append("%s: just-a-string" % dq(sid))
            continue
        calls = [salt_state() for _ in range(1 if chance(0.75) else 2)]
        out.append("%s:" % dq(sid))
        for func, args in calls:
            if not args and chance(0.5):
                out.append("  %s: []" % func)
                continue
            out.append("  %s:" % func)
            for k, v in args:
                if isinstance(v, list):
                    out.append("    - %s:" % k)
                    for item in v:
                        out.append("      - %s" % dq(item))
                elif v in ("True", "False", "true"):
                    out.append("    - %s: %s" % (k, v))
                else:
                    out.append("    - %s: %s" % (k, dq(v)))
    return "\n".join(out) + "\n"


# --- puppet --------------------------------------------------------------------------------------------------------

def puppet_resource():
    kind = pick(["package", "service", "file", "exec", "user", "group", "file_line", "cron", "sysctl", "mount",
                 "vcsrepo", "ssh_authorized_key", "host", "notify", "package"])
    title = pick(WORDS + PATHS[:3])
    attrs = []
    q = lambda s: pick(["'%s'" % s, '"%s"' % s])
    if kind == "package":
        if chance(0.7):
            attrs.append(("ensure", q(pick(["present", "installed", "latest", "absent", "purged", "2.0.0"]))))
        if chance(0.35):
            attrs.append(("provider", pick(["pip", "pip3", "apt", "'pip'"])))
    elif kind == "service":
        if chance(0.7):
            attrs.append(("ensure", pick(["running", "stopped", "'stopped'"])))
        if chance(0.6):
            attrs.append(("enable", pick(["true", "false", "'true'"])))
    elif kind == "file":
        if chance(0.35):
            attrs.append(("ensure", "directory"))
        if chance(0.6):
            attrs.append(("content", q(pick(["managed", "a b"]))))
        if chance(0.5):
            attrs.append(("mode", q(pick(MODES))))
        if chance(0.2):
            attrs.append(("path", q(pick(PATHS))))
    elif kind == "exec":
        if chance(0.7):
            attrs.append(("command", q(pick(CMDS))))
    elif kind in ("user", "group"):
        if chance(0.5):
            attrs.append(("ensure", pick(["present", "absent"])))
        if chance(0.2):
            attrs.append(("name", q(pick(WORDS))))
    elif kind == "file_line":
        if chance(0.85):
            attrs.append(("line", q("foo=bar")))
        if chance(0.6):
            attrs.append(("path", q(pick(PATHS))))
        if chance(0.3):
            attrs.append(("ensure", "absent"))
    elif kind == "cron":
        for f in ("minute", "hour", "monthday", "month", "weekday"):
            if chance(0.5):
                attrs.append((f, q(pick(CRONF))))
        if chance(0.7):
            attrs.append(("command", q(pick(CMDS))))
        if chance(0.3):
            attrs.append(("ensure", "absent"))
    elif kind == "sysctl":
        if chance(0.85):
            attrs.append(("value", q(pick(["1", "10"]))))
    elif kind == "mount":
        if chance(0.85):
            attrs.append(("device", q("/dev/sdb1")))
        if chance(0.85):
            attrs.append(("fstype", pick(["ext4", "'xfs'"])))
        if chance(0.4):
            attrs.append(("options", q("noatime")))
        if chance(0.2):
            attrs.append(("ensure", pick(["absent", "unmounted", "mounted"])))
    elif kind == "vcsrepo":
        if chance(0.85):
            attrs.append(("source", q(pick(URLS))))
        if chance(0.5):
            attrs.append(("revision", q("v1")))
        if chance(0.4):
            attrs.append(("path", q(pick(PATHS))))
    elif kind == "ssh_authorized_key":
        if chance(0.85):
            attrs.append(("user", q(pick(WORDS))))
        if chance(0.85):
            attrs.append(("type", q("ssh-rsa")))
        if chance(0.85):
            attrs.append(("key", q("AAAAB3Nza")))
    sep = pick([",\n  ", ",\n  ", ";\n  ", ",\n  "])
    body = sep.join("%s => %s" % (k, v) for k, v in attrs)
    if chance(0.5) and body:
        body += ","
    return "%s { %s:\n  %s\n}" % (kind, q(title), body)


def puppet_file():
    out = []
    for _ in range(rng.randrange(1, 7)):
        r = rng.random()
        if r < 0.1:
            out.append("# a comment")
        elif r < 0.17:
            out.append("class web { include nginx }")
        elif r < 0.22:
            out.append("$var = 'x'")
        elif r < 0.26:
            out.append("package { 'broken':")
        elif r < 0.3:
            out.append("file { nginx ensure => present }")
        else:
            out.append(puppet_resource())
        if chance(0.1):
            out.append("package { 'nginx': ensure => installed }\nservice { 'nginx': ensure => running }")
    return "\n".join(out) + "\n"


# --- chef ----------------------------------------------------------------------------------------------------------

def chef_block():
    kind = pick(["package", "apt_package", "yum_package", "service", "file", "template", "cookbook_file", "directory",
                 "execute", "bash", "script", "user", "group", "cron", "cron_d", "sysctl", "sysctl_param",
                 "python_package", "pip_package", "git", "hostname", "timezone", "mount", "log", "ruby_block"])
    name = pick(WORDS + PATHS[:3])
    q = lambda s: pick(["'%s'" % s, '"%s"' % s])
    lines = []
    actions = []
    if kind in ("package", "apt_package", "yum_package", "python_package", "pip_package"):
        actions = pick([[], ["install"], ["remove"], ["purge"], ["upgrade"]])
        if chance(0.3):
            lines.append("  package_name %s" % q(pick(WORDS)))
        if chance(0.3):
            lines.append("  version %s" % q(pick(VERS)))
    elif kind == "service":
        actions = pick([[], ["start"], ["enable"], ["enable", "start"], ["stop"], ["disable"], ["stop", "disable"]])
        if chance(0.3):
            lines.append("  service_name %s" % q(pick(WORDS)))
    elif kind in ("file", "template", "cookbook_file"):
        if chance(0.7):
            lines.append("  content %s" % q(pick(["managed", "a b"])))
        if chance(0.5):
            lines.append("  mode %s" % q(pick(MODES)))
        if chance(0.3):
            lines.append("  path %s" % q(pick(PATHS)))
    elif kind in ("execute", "bash", "script"):
        if chance(0.7):
            lines.append("  command %s" % q(pick(CMDS)))
        actions = ["run"]
    elif kind == "user" or kind == "group":
        actions = pick([[], ["create"], ["remove"]])
        if chance(0.3):
            lines.append("  %s %s" % ("username" if kind == "user" else "group_name", q(pick(WORDS))))
    elif kind in ("cron", "cron_d"):
        for f in ("minute", "hour", "day", "month", "weekday"):
            if chance(0.5):
                lines.append("  %s %s" % (f, q(pick(CRONF))))
        if chance(0.7):
            lines.append("  command %s" % q(pick(CMDS)))
        actions = pick([[], ["create"], ["delete"]])
    elif kind in ("sysctl", "sysctl_param"):
        if chance(0.85):
            lines.append("  value %s" % q(pick(["1", "10"])))
        if chance(0.3):
            lines.append("  key %s" % q("vm.swappiness"))
    elif kind == "git":
        if chance(0.85):
            lines.append("  repository %s" % q(pick(URLS)))
        elif chance(0.5):
            lines.append("  repo %s" % q(pick(URLS)))
        if chance(0.5):
            lines.append("  revision %s" % q("v1"))
        elif chance(0.3):
            lines.append("  reference %s" % q("main"))
        if chance(0.3):
            lines.append("  destination %s" % q(pick(PATHS)))
    elif kind in ("hostname", "timezone"):
        if chance(0.3):
            lines.append("  %s %s" % (kind, q("web-02")))
    elif kind == "mount":
        if chance(0.85):
            lines.append("  device %s" % q("/dev/sdb1"))
        if chance(0.85):
            lines.append("  fstype %s" % q("ext4"))
        if chance(0.4):
            lines.append("  options %s" % q("noatime"))
        if chance(0.3):
            lines.append("  mount_point %s" % q(pick(PATHS)))
        actions = pick([[], ["mount"], ["mount", "enable"], ["umount"], ["disable"]])
    if actions:
        if len(actions) == 1 and chance(0.5):
            lines.append("  action :%s" % actions[0])
        else:
            lines.append("  action [%s]" % ", ".join(":" + x for x in actions))
    if chance(0.15):
        lines.append("  notifies :restart, 'service[x]'  # tail comment")
    return "%s %s do\n%s\nend" % (kind, q(name), "\n".join(lines)) if lines or chance(0.5) else "%s %s do\nend" % (kind, q(name))


def chef_file():
    out = []
    for _ in range(rng.randrange(1, 7)):
        r = rng.random()
        if r < 0.1:
            out.append("# comment line")
        elif r < 0.17:
            out.append("hostname '%s'" % pick(["web-01", "db"]))
        elif r < 0.22:
            out.append("include_recipe 'base::default'")
        elif r < 0.26:
            out.append("node['x'].each do |y|")
        elif r < 0.3:
            out.append("package 'unterminated' do\n  action :install")
        else:
            out.append(chef_block())
    return "\n".join(out) + "\n"


# --- fixed cross-matrix ---------------------------------------------------------------------------------------------

FIXED = [
    ("ansible", "- hosts: web\n  name: Web\n  tasks:\n    - name: install nginx\n      apt: { name: nginx, state: present }\n    - service: { name: nginx, state: started, enabled: true }\n    - pip: { name: requests, version: \"2.31.0\" }\n    - user: { name: deploy, shell: /bin/bash }\n    - group: { name: ops }\n    - cron: { name: nightly, minute: \"0\", hour: \"2\", job: /usr/bin/backup }\n    - file: { path: /var/www, state: directory, mode: \"0755\" }\n    - file: { path: /usr/bin/x, src: /opt/x, state: link }\n"),
    ("ansible", "not a list: true\n"),
    ("ansible", "- {}\n"),
    ("ansible", "- hosts: all\n  tasks:\n    - apt: nginx\n    - name: m\n      mount: { path: /data, src: /dev/x, fstype: ext4, state: absent }\n"),
    ("salt", "requests==2.31.0:\n  pip.installed: []\nnginx:\n  pkg.installed: []\n  service.running:\n    - enable: True\nwww-data:\n  user.present: []\n  group.present: []\n/var/www:\n  file.directory:\n    - mode: \"0755\"\n"),
    ("salt", "- not\n- a\n- mapping\n"),
    ("puppet", "package { 'flask': provider => pip, ensure => '2.0.0', }\npackage { 'nginx': ensure => installed }\nservice { 'nginx': ensure => running, enable => true }\nuser { 'deploy': ensure => present }\ngroup { 'ops': ensure => absent }\ncron { 'nightly': minute => '0', hour => '2', command => '/usr/bin/backup' }\nfile { '/var/www': ensure => directory, mode => '0755' }\n"),
    ("puppet", ""),
    ("puppet", "}\n=> 'x' , ; :\nclass foo {\n"),
    ("chef", "python_package 'boto3' do\n  version '1.34.0'\nend\npackage 'nginx' do\n  action :install\nend\nservice 'nginx' do\n  action [:enable, :start]\nend\nhostname 'web-01'\nuser 'deploy' do\n  action :remove\nend\ndirectory '/var/www' do\nend\n"),
    ("chef", ""),
    ("chef", "package 'a' do\n  action :install\n"),
]


def run_reference(exe, kind, src, project):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8", newline="") as f:
        f.write(src)
        path = f.name
    try:
        done = subprocess.run([exe, kind, path, project], capture_output=True, text=True, encoding="utf-8")
    finally:
        os.unlink(path)
    out = done.stdout.replace("\r\n", "\n")
    if done.returncode != 0 or out.startswith("error:") or not out.startswith("migrated: "):
        return "error"
    head, _sep, yaml_text = out.partition("\n---\n")
    lines = head.split("\n")
    migrated = lines[0][len("migrated: "):]
    warnings = [w[len("warning: "):] for w in lines[1:]]
    return "\n".join([migrated] + warnings) + "\n---\n" + yaml_text


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    exe = argv[0]
    cases = []
    for kind, src in FIXED:
        cases.append((kind, src))
    for _ in range(90):
        cases.append(("ansible", ansible_playbook()))
    for _ in range(90):
        cases.append(("salt", salt_file()))
    for _ in range(90):
        cases.append(("puppet", puppet_file()))
    for _ in range(90):
        cases.append(("chef", chef_file()))
    lines = []
    errors = 0
    for kind, src in cases:
        project = pick(["demo", "p", "shop"])
        expected = run_reference(exe, kind, src, project)
        if expected == "error":
            errors += 1
        lines.append(json.dumps({"k": kind, "p": project, "src": src, "e": expected}, ensure_ascii=True))
    chunks = []
    size = 6
    for i in range(0, len(lines), size):
        text = "\n".join(lines[i:i + size]) + "\n"
        literal = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        chunks.append('"%s"' % literal)
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    template = open(os.path.join(ROOT, "scripts", "migrate_fixture_template.e"), encoding="utf-8").read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_migrate", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("%d cases (%d reference refusals) in %d chunks -> x_migrate" % (len(cases), errors, len(chunks)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
