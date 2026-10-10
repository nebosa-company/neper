# -*- coding: utf-8 -*-
"""Reference vectors for `x.migrate.terraform` (L041): run petcow's own `migrate_hcl` over fixed and random Terraform.

Usage:  python scripts/terraform_reference.py REFERENCE_EXE

REFERENCE_EXE is a build of petcow's `migrate_hcl` (src/migrate.rs lines 1-988 with the error and module-source shims;
see docs/petcow.md F1) that takes `FILE PROJECT` and prints `migrated: N`, one `warning: ...` line each, `---` and the
YAML, or `error: ...` with exit status 2. The script writes tests/selfhost/fixtures/link/x_migrate_terraform/src/main.e
from scripts/terraform_fixture_template.e: one JSON line per case, `{"p", "src", "e"}`, `e` being the reference's
output (or the text "error").
"""
import json
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = random.Random(0x7f41)


def pick(xs):
    return xs[rng.randrange(len(xs))]


def chance(p):
    return rng.random() < p


NAMES = ["main", "web", "db", "a", "b1", "my-net", "x_y", "cache"]
ATTRS = ["cidr_block", "name", "tags", "ami", "instance_type", "size", "enable_dns", "vpc_id", "subnet_id", "ttl", "port", "acl"]
RTYPES = ["aws_vpc", "aws_subnet", "aws_s3_bucket", "aws_instance", "aws_security_group", "aws_eip", "aws_ebs_volume",
          "aws_iam_role", "aws_internet_gateway", "aws_route_table", "aws_lambda_function", "google_compute_instance"]
STRS = ["10.0.0.0/16", "us-east-1", "t3.micro", "hello world", "a-b", "x", "", "ami-123", "with 'single'", "path/to/x"]
NUMS = ["0", "1", "2", "10", "443", "1.5", "0.25", "3.0", "1e3", "-1", "-2.5", "100", "65535", "0.000001", "12345678.5"]


def hcl_string(s):
    return json.dumps(s, ensure_ascii=True).replace("$", "$") if "${" not in s else '"%s"' % s


def ref():
    return pick([
        "var.%s" % pick(["region", "env", "count", "tags", "name"]),
        "var.%s.%s" % (pick(["cfg", "obj"]), pick(["a", "b"])),
        "var.items[%d]" % rng.randrange(3),
        'var.m["%s"]' % pick(["k", "name"]),
        "local.%s" % pick(["tags", "prefix", "n"]),
        "count.index", "each.key", "each.value", "each.value.id",
        "data.aws_vpc.%s.id" % pick(NAMES), "data.aws_subnet.%s.cidr_block" % pick(NAMES),
        "aws_vpc.%s.id" % pick(NAMES), "aws_subnet.%s.vpc_id" % pick(NAMES), "aws_instance.%s.private_ip" % pick(NAMES),
        'aws_vpc.%s.tags["Name"]' % pick(NAMES), "aws_instance.%s[0].id" % pick(NAMES), "aws_s3_bucket.%s.arn" % pick(NAMES),
        "module.%s.%s" % (pick(NAMES), pick(["id", "out"])), "self.id", "path.module", "terraform.workspace",
        "aws_vpc.%s" % pick(NAMES), "x", "aws_instance.%s[*].id" % pick(NAMES), "aws_instance.%s.*.id" % pick(NAMES),
        "var.l.0.name", "data.aws_vpc.%s" % pick(NAMES),
    ])


def expr(depth=0, conditional=True):
    r = rng.randrange(24)
    if r == 11 and not conditional:
        r = 14
    if depth >= 3 or r < 5:
        return pick([json.dumps(pick(STRS)), pick(NUMS), pick(["true", "false", "null"]), ref(), ref()])
    if r == 5:
        return '"%s${%s}%s"' % (pick(["", "pre-", "s3://"]), ref(), pick(["", "-suf", "/x"]))
    if r == 6:
        return '"${%s}-${%s}"' % (ref(), pick(["count.index", "var.env", 'lookup(local.m, "k")']))
    if r == 7:
        return '"${%s}"' % ref()
    if r == 8:
        return "[%s]" % ", ".join(expr(depth + 1, conditional) for _ in range(rng.randrange(4)))
    if r == 9:
        keys = []
        out = []
        for _ in range(rng.randrange(1, 4)):
            k = pick(["a", "b", "Name", "env", "k-1"])
            if k in keys:
                continue
            keys.append(k)
            out.append("%s%s = %s" % ("", k if chance(0.7) else json.dumps(k), expr(depth + 1, conditional)))
        return "{ %s }" % ", ".join(out) if chance(0.5) else "{\n    %s\n  }" % "\n    ".join(out)
    if r == 10:
        return "%s(%s)" % (pick(["merge", "join", "length", "format", "lookup", "concat", "toset", "try", "max"]),
                           ", ".join(expr(depth + 1, conditional) for _ in range(rng.randrange(1, 4))))
    if r == 11:
        # hcl-rs does not read every nesting of unparenthesised conditionals the way the specification does, so the
        # branches here are never conditionals themselves
        return "%s ? %s : %s" % (ref() + " == " + pick([json.dumps("prod"), "1", "true"]) if chance(0.7) else ref(), expr(depth + 1, False), expr(depth + 1, False))
    if r == 12:
        return "%s %s %s" % (ref(), pick(["+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">=", "&&", "||"]), pick([ref(), pick(NUMS), json.dumps("x")]))
    if r == 13:
        return "!%s" % ref() if chance(0.5) else "-%s" % ref()
    if r == 14:
        return "(%s)" % expr(depth + 1, conditional)
    if r == 15:
        return "[for x in %s : upper(x)]" % ref() if chance(0.5) else "{for k, v in %s : k => v}" % ref()
    if r == 16:
        return "ns::%s(%s)" % (pick(["f", "g"]), ref())
    if r == 17:
        return "%s(%s...)" % (pick(["concat", "merge", "zipmap"]), ref())
    if r == 18:
        return "<<EOT\nline ${%s}\n  indented %s\nEOT" % (ref(), pick(["x", "$${lit}"]))
    if r == 19:
        return "<<-EOT\n    stripped ${%s}\n      deeper\n    EOT" % ref()
    if r == 20:
        return '"%%{ if %s }yes%%{ else }no%%{ endif }"' % ref()
    if r == 21:
        return '"line1\\nline2 \\"q\\" \\\\ ${%s}"' % ref()
    if r == 22:
        return "%s[%s]" % (ref(), pick(["0", "1", '"k"', "count.index", "var.i"]))
    return "%s(%s)[0].%s" % (pick(["element", "tolist"]), ref(), pick(["id", "name"]))


def attr_name():
    return pick(ATTRS)


def block_attrs(n, indent="  "):
    used = set()
    out = []
    for _ in range(n):
        k = attr_name()
        if k in used:
            continue
        used.add(k)
        out.append("%s%s = %s" % (indent, k, expr()))
    return out


def lifecycle():
    items = []
    if chance(0.6):
        items.append("    prevent_destroy = %s" % pick(["true", "false"]))
    if chance(0.6):
        items.append("    ignore_changes = %s" % pick(["all", "[tags]", "[tags, ami]", '["tags"]', "[tags[\"Name\"]]", "[ami, instance_type]", "tags"]))
    if chance(0.5):
        items.append("    create_before_destroy = %s" % pick(["true", "false"]))
    if chance(0.15):
        items.append("    replace_triggered_by = [aws_vpc.main.id]")
    if chance(0.1):
        items.append("    precondition {\n      condition = true\n    }")
    return "  lifecycle {\n%s\n  }" % "\n".join(items)


def dynamic():
    it = pick([None, "rule"])
    lines = ['  dynamic "ingress" {']
    lines.append("    for_each = %s" % pick(["var.rules", "local.rules", "aws_vpc.main.tags", "[1, 2]"]))
    if it:
        lines.append("    iterator = %s" % it)
    name = it or "ingress"
    body = pick(["port = %s.value.port" % name, "port = %s.value" % name, "name = %s.key" % name, "cidr = var.cidr", "n = %s.value.a + 1" % name])
    lines.append("    content {\n      %s\n      proto = %s\n    }" % (body, json.dumps("tcp")))
    if chance(0.15):
        lines.append('    labels = ["x"]')
    lines.append("  }")
    return "\n".join(lines)


def resource():
    t = pick(RTYPES)
    n = pick(NAMES)
    lines = ['resource "%s" "%s" {' % (t, n)]
    lines += block_attrs(rng.randrange(1, 5))
    if chance(0.25):
        lines.append("  count = %s" % pick(["2", "var.n", "var.enabled ? 1 : 0", "length(var.items)"]))
    if chance(0.15):
        lines.append("  for_each = %s" % pick(["var.set", "toset([\"a\", \"b\"])", "{a = 1}"]))
    if chance(0.25):
        lines.append("  depends_on = %s" % pick(["[aws_vpc.main]", "[aws_vpc.main, aws_subnet.a]", "[module.x]", "var.d", "[local.x]"]))
    if chance(0.1):
        lines.append("  provider = aws.west")
    if chance(0.3):
        lines.append(lifecycle())
    if chance(0.25):
        lines.append(dynamic())
    if chance(0.15):
        lines.append('  ingress {\n    port = 22\n  }')
    lines.append("}")
    return "\n".join(lines)


def variable():
    n = pick(["region", "env", "count", "tags", "name", "items", "enabled"])
    lines = ['variable "%s" {' % n]
    if chance(0.7):
        lines.append("  type = %s" % pick(["string", "number", "bool", "list(string)", "map(string)", "set(string)", "object({a = string})", "any", "tuple([string])", "custom"]))
    if chance(0.6):
        lines.append("  default = %s" % expr(2))
    if chance(0.5):
        lines.append('  description = %s' % json.dumps(pick(STRS)))
    if chance(0.2):
        lines.append("  sensitive = true")
    if chance(0.1):
        lines.append("  nullable = false")
    if chance(0.1):
        lines.append('  validation {\n    condition = true\n    error_message = "x"\n  }')
    lines.append("}")
    return "\n".join(lines)


def locals_block():
    lines = ["locals {"]
    used = set()
    for _ in range(rng.randrange(1, 4)):
        k = pick(["tags", "prefix", "n", "rules", "m"])
        if k in used:
            continue
        used.add(k)
        lines.append("  %s = %s" % (k, expr()))
    lines.append("}")
    return "\n".join(lines)


def data_block():
    t = pick(["aws_vpc", "aws_subnet", "aws_ami", "aws_s3_bucket"])
    lines = ['data "%s" "%s" {' % (t, pick(NAMES))]
    if chance(0.6):
        lines.append("  name = %s" % pick([json.dumps("x"), "var.n", '"p-${var.env}"']))
    if chance(0.4):
        lines.append("  most_recent = true")
    if chance(0.3):
        lines.append('  filter {\n    name = "x"\n  }')
    lines.append("}")
    return "\n".join(lines)


def output_block():
    lines = ['output "%s" {' % pick(["id", "arn", "ips"])]
    if chance(0.85):
        lines.append("  value = %s" % expr())
    if chance(0.3):
        lines.append("  sensitive = true")
    if chance(0.3):
        lines.append('  description = "d"')
    if chance(0.15):
        lines.append("  depends_on = [aws_vpc.main]")
    if chance(0.1):
        lines.append("  extra = 1")
    lines.append("}")
    return "\n".join(lines)


def provider_block():
    lines = ['provider "%s" {' % pick(["aws", "aws", "google", "azurerm", "random"])]
    if chance(0.6):
        lines.append('  alias = "%s"' % pick(["west", "east", "dr"]))
    if chance(0.7):
        lines.append("  region = %s" % pick(['"us-west-2"', "var.region", '"eu-${var.x}"']))
    if chance(0.4):
        lines.append('  profile = "p"')
    if chance(0.2):
        lines.append('  version = "~> 4"')
    lines.append("}")
    return "\n".join(lines)


def module_block():
    lines = ['module "%s" {' % pick(NAMES)]
    src = pick(["./net", "../shared/net", "/abs/net", "git::https://example.com/repo.git//mods/net?ref=v1", "github.com/o/r//x", "terraform-aws-modules/vpc/aws",
                "hashicorp/consul/aws", "./local", "git@github.com:o/r.git//p"])
    if chance(0.92):
        lines.append("  source = %s" % json.dumps(src))
    if chance(0.3):
        lines.append('  version = "1.0"')
    lines += block_attrs(rng.randrange(0, 3))
    if chance(0.2):
        lines.append("  count = 2")
    if chance(0.1):
        lines.append("  providers = { aws = aws.west }")
    if chance(0.1):
        lines.append("  depends_on = [aws_vpc.main]")
    lines.append("}")
    return "\n".join(lines)


def document():
    parts = []
    for _ in range(rng.randrange(1, 8)):
        parts.append(pick([resource, resource, resource, variable, locals_block, data_block, output_block, provider_block, module_block])())
    if chance(0.05):
        parts.append('terraform {\n  required_version = ">= 1"\n}')
    if chance(0.04):
        parts.append("top = 1")
    if chance(0.08):
        parts.insert(0, "# a comment\n// another\n/* block\ncomment */")
    return "\n\n".join(parts) + "\n"


def run_reference(exe, src, project):
    with tempfile.NamedTemporaryFile("w", suffix=".tf", delete=False, encoding="utf-8", newline="\n") as f:
        f.write(src)
        path = f.name
    try:
        r = subprocess.run([exe, path, project], capture_output=True, text=True, encoding="utf-8")
    finally:
        os.unlink(path)
    if r.returncode != 0:
        return "error"
    return r.stdout


FIXED = [
    'resource "aws_vpc" "main" {\n  cidr_block = "10.0.0.0/16"\n}\n',
    'resource "aws_s3_bucket" "b" {\n  bucket = "x"\n  tags = {\n    Name = "n"\n  }\n}\n',
    'variable "a" {\n  default = [1, 2, 3]\n}\n',
    'locals {\n  x = 1\n  y = "${local.x}"\n}\n',
    'resource "aws_vpc" "main" {\n  cidr_block = "x"\n  bad = \n}\n',
    'resource "aws_vpc" "main" {',
    '',
    'x = 1\n',
    'resource "aws_instance" "i" {\n  user_data = <<EOT\nhello\nEOT\n}\n',
    'provider "aws" {\n  region = "us-east-1"\n}\n',
]


def main(argv):
    exe = argv[1]
    cases = []
    for src in FIXED:
        cases.append(("proj", src))
    for i in range(520):
        cases.append((pick(["proj", "demo", "My App", "x-1"]), document()))
    lines = []
    stats = {"error": 0, "ok": 0, "warnings": 0}
    for project, src in cases:
        out = run_reference(exe, src, project)
        if out == "error":
            stats["error"] += 1
        else:
            stats["ok"] += 1
            stats["warnings"] += out.count("warning: ")
        lines.append(json.dumps({"p": project, "src": src, "e": out}, ensure_ascii=True))
    chunks = []
    size = 6
    for i in range(0, len(lines), size):
        body = "\n".join(lines[i:i + size]) + "\n"
        chunks.append('"%s"' % body.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n"))
    funcs = "\n".join("fn vectors_%d() -> str {\n    ret %s\n}\n" % (i, c) for i, c in enumerate(chunks))
    calls = "".join("    if run_chunk(a, vectors_%d()) != 0u8 { os.exit(%di32) }\n" % (i, i + 1) for i in range(len(chunks)))
    with open(os.path.join(ROOT, "scripts", "terraform_fixture_template.e"), encoding="utf-8") as f:
        template = f.read()
    out = template.replace("//__VECTOR_FUNCTIONS__\n", funcs + "\n").replace("    //__VECTOR_CALLS__\n", calls)
    target = os.path.join(ROOT, "tests", "selfhost", "fixtures", "link", "x_migrate_terraform", "src", "main.e")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as f:
        f.write(out)
    print("%d cases in %d chunks -> x_migrate_terraform" % (len(cases), len(chunks)), stats)


if __name__ == "__main__":
    main(sys.argv)
