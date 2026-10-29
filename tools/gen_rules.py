#!/usr/bin/env python3
"""Generate the plural rule tables and the CLDR sample tests for odin-plural.

The script reads CLDR's plurals.xml (cardinal rules) and ordinals.xml
(ordinal rules), translates the rules of the locales in LOCALES into Odin
procedures, and writes:

- rules.odin                      the rule procedures and the locale table
- tests/cldr_samples_test.odin    one test per locale and plural type that
                                  checks every @integer and @decimal sample

Usage:

    python3 tools/gen_rules.py                    # download CLDR_RELEASE
    python3 tools/gen_rules.py --xml-dir DIR      # use local XML files

To support another locale, add its CLDR name to LOCALES and run the script.
To move to a newer CLDR release, bump CLDR_RELEASE and run the script; the
sample tests then tell you whether anything changed.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from decimal import Decimal

CLDR_RELEASE = "release-49"
CLDR_URL = "https://raw.githubusercontent.com/unicode-org/cldr/{release}/common/supplemental/{name}"
CLDR_BLOB = "https://github.com/unicode-org/cldr/blob/{release}/common/supplemental/{name}"

# The locales that ship with the library, by CLDR name. Keep this list sorted.
# It covers the languages that most applications translate into, plus the
# legacy codes (in, iw, no, tl) that operating systems still report.
LOCALES = """
af am ar az be bg bn bs ca cs cy da de el en es et eu fa fi fil fr ga gl gu
he hi hr hu hy id in is it iw ja ka kk km kn ko ky lo lt lv mk ml mn mr ms my
nb ne nl nn no pa pl pt pt_PT ro ru si sk sl sq sr sv sw ta te th tl tr uk ur
uz vi yue zh zu
""".split()

CATEGORIES = ["zero", "one", "two", "few", "many", "other"]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------------------
# CLDR plural rule syntax, see UTS #35 part 3, section "Language Plural Rules".


TOKEN_RE = re.compile(r"\s*(\.\.|!=|=|%|,|[a-z]+|\d+)")


def tokenize(text: str) -> list[str]:
    tokens: list[str] = []
    pos = 0
    text = text.strip()
    while pos < len(text):
        m = TOKEN_RE.match(text, pos)
        if not m:
            raise ValueError(f"cannot tokenize rule {text!r} at {pos}")
        tokens.append(m.group(1))
        pos = m.end()
    return tokens


@dataclass
class Relation:
    operand: str
    modulus: int | None
    negated: bool
    ranges: list[tuple[int, int]]


def parse_condition(text: str) -> list[list[Relation]]:
    """Return the condition as a list of or-branches, each a list of relations."""
    tokens = tokenize(text)
    pos = 0

    def peek() -> str | None:
        return tokens[pos] if pos < len(tokens) else None

    def take(expected: str | None = None) -> str:
        nonlocal pos
        if pos >= len(tokens):
            raise ValueError(f"unexpected end of rule {text!r}")
        tok = tokens[pos]
        if expected is not None and tok != expected:
            raise ValueError(f"expected {expected!r}, got {tok!r} in {text!r}")
        pos += 1
        return tok

    def relation() -> Relation:
        operand = take()
        if operand not in "nivwftce" or len(operand) != 1:
            raise ValueError(f"unknown operand {operand!r} in {text!r}")
        modulus = None
        if peek() == "%":
            take("%")
            modulus = int(take())
        op = take()
        if op not in ("=", "!="):
            raise ValueError(f"unsupported operator {op!r} in {text!r}")
        ranges: list[tuple[int, int]] = []
        while True:
            lo = int(take())
            hi = lo
            if peek() == "..":
                take("..")
                hi = int(take())
            ranges.append((lo, hi))
            if peek() != ",":
                break
            take(",")
        return Relation(operand, modulus, op == "!=", ranges)

    branches: list[list[Relation]] = []
    while True:
        branch = [relation()]
        while peek() == "and":
            take("and")
            branch.append(relation())
        branches.append(branch)
        if peek() != "or":
            break
        take("or")
    if pos != len(tokens):
        raise ValueError(f"trailing tokens in {text!r}")
    return branches


def odin_relation(rel: Relation) -> str:
    # n is the absolute value. It equals an integer only when there are no
    # non-zero fraction digits (t == 0), and then it equals i. Every range in
    # CLDR rules is an integer range, so we never need floating point.
    field_name = {"n": "i", "c": "e"}.get(rel.operand, rel.operand)
    lhs = f"o.{field_name}"
    if rel.modulus is not None:
        lhs = f"{lhs} % {rel.modulus}"

    items = []
    for lo, hi in rel.ranges:
        if lo == hi:
            items.append(f"{lhs} == {lo}")
        else:
            items.append(f"between({lhs}, {lo}, {hi})")

    if rel.operand == "n":
        inner = " || ".join(items)
        if len(items) > 1:
            inner = f"({inner})"
        expr = f"o.t == 0 && {inner}"
        return f"!({expr})" if rel.negated else f"({expr})"

    if rel.negated:
        if len(items) == 1 and rel.ranges[0][0] == rel.ranges[0][1]:
            return f"{lhs} != {rel.ranges[0][0]}"
        inner = " || ".join(items)
        return f"!({inner})"
    if len(items) == 1:
        return items[0]
    return "(" + " || ".join(items) + ")"


def odin_condition(text: str) -> str:
    branches = parse_condition(text)
    parts = []
    for branch in branches:
        rels = [odin_relation(r) for r in branch]
        part = " && ".join(rels)
        parts.append(part)
    return " || ".join(parts)


# ---------------------------------------------------------------------------
# Samples.


def expand_samples(text: str) -> list[str]:
    out: list[str] = []
    for item in text.split(","):
        item = item.strip()
        if not item or item == "…":
            continue
        if "~" in item:
            lo, hi = item.split("~")
            if "c" in lo or "c" in hi:
                raise ValueError(f"exponent in sample range {item!r}")
            if "." in lo:
                places = len(lo.split(".")[1])
                if len(hi.split(".")[1]) != places:
                    raise ValueError(f"mismatched sample range {item!r}")
                step = Decimal(1).scaleb(-places)
                value, end = Decimal(lo), Decimal(hi)
                while value <= end:
                    out.append(f"{value:.{places}f}")
                    value += step
            else:
                out.extend(str(v) for v in range(int(lo), int(hi) + 1))
        else:
            out.append(item)
    return out


@dataclass
class Rule:
    category: str
    condition: str
    integer_samples: list[str] = field(default_factory=list)
    decimal_samples: list[str] = field(default_factory=list)


@dataclass
class RuleSet:
    locales: list[str]
    rules: list[Rule]

    @property
    def categories(self) -> list[str]:
        return [r.category for r in self.rules]

    @property
    def integer_categories(self) -> list[str]:
        """Categories that a plain integer (no exponent) can select."""
        return [
            r.category
            for r in self.rules
            if any("c" not in s and "e" not in s for s in r.integer_samples)
        ]


def parse_rule_sets(path: str) -> list[RuleSet]:
    tree = ET.parse(path)
    sets: list[RuleSet] = []
    for node in tree.getroot().iter("pluralRules"):
        rules: list[Rule] = []
        for rule_node in node.iter("pluralRule"):
            text = rule_node.text or ""
            parts = text.split("@")
            rule = Rule(rule_node.get("count"), parts[0].strip())
            for part in parts[1:]:
                kind, _, samples = part.partition(" ")
                if kind == "integer":
                    rule.integer_samples = expand_samples(samples)
                elif kind == "decimal":
                    rule.decimal_samples = expand_samples(samples)
                else:
                    raise ValueError(f"unknown sample kind {kind!r}")
            rules.append(rule)
        rules.sort(key=lambda r: CATEGORIES.index(r.category))
        sets.append(RuleSet(node.get("locales").split(), rules))
    return sets


def find_set(sets: list[RuleSet], locale: str) -> RuleSet | None:
    for s in sets:
        if locale in s.locales:
            return s
    return None


def resolve_set(sets: list[RuleSet], locale: str) -> RuleSet:
    """Follow CLDR inheritance: pt_PT, then pt, then root."""
    while True:
        found = find_set(sets, locale)
        if found is not None:
            return found
        if "_" not in locale:
            root = find_set(sets, "root")
            assert root is not None
            return root
        locale = locale.rsplit("_", 1)[0]


# ---------------------------------------------------------------------------
# Odin output.


def odin_name(locale: str) -> str:
    return locale.lower()


def odin_set(categories: list[str]) -> str:
    return "{" + ", ".join("." + c.capitalize() for c in categories) + "}"


def proc_suffix(rule_set: RuleSet, wanted: list[str]) -> str:
    for loc in rule_set.locales:
        if loc in wanted:
            return loc.lower()
    return rule_set.locales[0].lower()


def emit_rule_proc(kind: str, suffix: str, rule_set: RuleSet, wanted: list[str]) -> list[str]:
    covered = [l for l in rule_set.locales if l in wanted or l == "root"]
    lines = [
        f"// {kind}_{suffix} implements the CLDR {kind} rules for: {' '.join(covered)}.",
        "@(private = \"file\")",
        f"{kind}_{suffix} :: proc \"contextless\" (o: Operands) -> Category {{",
    ]
    body = [r for r in rule_set.rules if r.category != "other"]
    if not body:
        lines.append("\t_ = o")
    for rule in body:
        lines.append(f"\t// {rule.category}: {rule.condition}")
        lines.append(f"\tif {odin_condition(rule.condition)} {{")
        lines.append(f"\t\treturn .{rule.category.capitalize()}")
        lines.append("\t}")
    lines.append("\treturn .Other")
    lines.append("}")
    return lines


def generate(plurals: str, ordinals: str) -> tuple[str, str]:
    cardinal_sets = parse_rule_sets(plurals)
    ordinal_sets = parse_rule_sets(ordinals)
    wanted = sorted(set(LOCALES))
    for loc in wanted:
        if find_set(cardinal_sets, loc) is None:
            sys.exit(f"locale {loc} has no cardinal rules in plurals.xml")

    table_names = wanted + ["root"]
    entries = []
    used_cardinal: dict[int, str] = {}
    used_ordinal: dict[int, str] = {}
    for loc in table_names:
        cs = resolve_set(cardinal_sets, loc)
        os_ = resolve_set(ordinal_sets, loc)
        csuf = used_cardinal.setdefault(id(cs), proc_suffix(cs, table_names))
        osuf = used_ordinal.setdefault(id(os_), proc_suffix(os_, table_names))
        entries.append((loc, cs, csuf, os_, osuf))

    src = [
        "// Code generated by tools/gen_rules.py. DO NOT EDIT.",
        "//",
        f"// Source: Unicode CLDR {CLDR_RELEASE}",
        f"//   {CLDR_BLOB.format(release=CLDR_RELEASE, name='plurals.xml')}",
        f"//   {CLDR_BLOB.format(release=CLDR_RELEASE, name='ordinals.xml')}",
        "//",
        "// Each procedure below is the Odin form of one CLDR rule set. A comment",
        "// above each condition repeats the CLDR rule text for review.",
        "// The n operand never appears directly: n equals an integer only when",
        "// t == 0, and then it equals i.",
        "package plural",
        "",
        "// CLDR_VERSION names the Unicode CLDR release that the rule tables come from.",
        f'CLDR_VERSION :: "{CLDR_RELEASE.removeprefix("release-").replace("-", ".")}"',
        "",
    ]

    done: set[str] = set()
    for loc, cs, csuf, _, _ in entries:
        if csuf in done:
            continue
        done.add(csuf)
        src.extend(emit_rule_proc("cardinal", csuf, cs, table_names))
        src.append("")
        src.append(f"// pluralizer_{csuf} adapts cardinal_{csuf} to core:text/i18n.")
        src.append("@(private = \"file\")")
        src.append(f"pluralizer_{csuf} :: proc(n: int) -> int {{")
        src.append(
            f"\treturn slot_of(cardinal_{csuf}(operands_from_int(n)), {odin_set(cs.integer_categories)})"
        )
        src.append("}")
        src.append("")

    done.clear()
    for loc, _, _, os_, osuf in entries:
        if osuf in done:
            continue
        done.add(osuf)
        src.extend(emit_rule_proc("ordinal", osuf, os_, table_names))
        src.append("")

    src.append("// LOCALE_TABLE lists every supported locale, sorted by normalized name.")
    src.append("@(private, rodata)")
    src.append("LOCALE_TABLE := [?]Locale_Rules{")
    for loc, cs, csuf, os_, osuf in sorted(entries, key=lambda e: e[0].lower().replace("_", "-")):
        name = loc.lower().replace("_", "-")
        src.append("\t{")
        src.append(f'\t\tname = "{name}",')
        src.append(f"\t\tcardinal = cardinal_{csuf},")
        src.append(f"\t\tordinal = ordinal_{osuf},")
        src.append(f"\t\tpluralizer = pluralizer_{csuf},")
        src.append(f"\t\tcardinal_set = {odin_set(cs.categories)},")
        src.append(f"\t\tordinal_set = {odin_set(os_.categories)},")
        src.append(f"\t\tinteger_set = {odin_set(cs.integer_categories)},")
        src.append("\t},")
    src.append("}")
    src.append("")
    src.append("// LOCALE_NAMES lists the names in LOCALE_TABLE, in the same order.")
    src.append("@(private, rodata)")
    src.append("LOCALE_NAMES := [?]string{")
    for loc in sorted(e[0].lower().replace("_", "-") for e in entries):
        src.append(f'\t"{loc}",')
    src.append("}")
    src.append("")

    tests = [
        "// Code generated by tools/gen_rules.py. DO NOT EDIT.",
        "//",
        f"// Every @integer and @decimal sample from Unicode CLDR {CLDR_RELEASE}",
        "// plurals.xml and ordinals.xml, one test per locale and plural type.",
        "package plural_tests",
        "",
        "import \"core:testing\"",
        "",
    ]
    for loc, cs, _, os_, _ in entries:
        if loc == "root":
            continue
        ident = loc.lower()
        for kind, rs in (("cardinal", cs), ("ordinal", os_)):
            tests.append("@(test)")
            tests.append(f"test_cldr_{kind}_{ident} :: proc(t: ^testing.T) {{")
            tests.append(f"\texpect_{kind}_samples(")
            tests.append("\t\tt,")
            tests.append(f'\t\t"{loc}",')
            tests.append(f"\t\t{odin_set(rs.categories)},")
            if kind == "cardinal":
                tests.append(f"\t\t{odin_set(rs.integer_categories)},")
            tests.append("\t\t{")
            for rule in rs.rules:
                samples = rule.integer_samples + rule.decimal_samples
                cat = rule.category.capitalize()
                row: list[str] = []
                for s in samples:
                    row.append(f'{{"{s}", .{cat}}}')
                    if len(row) == 6:
                        tests.append("\t\t\t" + ", ".join(row) + ",")
                        row = []
                if row:
                    tests.append("\t\t\t" + ", ".join(row) + ",")
            tests.append("\t\t},")
            tests.append("\t)")
            tests.append("}")
            tests.append("")
    return "\n".join(src), "\n".join(tests)


def load(name: str, xml_dir: str | None) -> str:
    if xml_dir:
        return os.path.join(xml_dir, name)
    cache = os.path.join(ROOT, "build", "cldr", CLDR_RELEASE)
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, name)
    if not os.path.exists(path):
        url = CLDR_URL.format(release=CLDR_RELEASE, name=name)
        print(f"downloading {url}", file=sys.stderr)
        with urllib.request.urlopen(url) as resp, open(path, "wb") as out:
            out.write(resp.read())
    return path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--xml-dir", help="directory that holds plurals.xml and ordinals.xml")
    args = parser.parse_args()
    rules, tests = generate(load("plurals.xml", args.xml_dir), load("ordinals.xml", args.xml_dir))
    with open(os.path.join(ROOT, "rules.odin"), "w", encoding="utf-8") as f:
        f.write(rules)
    with open(os.path.join(ROOT, "tests", "cldr_samples_test.odin"), "w", encoding="utf-8") as f:
        f.write(tests)
    print("wrote rules.odin and tests/cldr_samples_test.odin", file=sys.stderr)


if __name__ == "__main__":
    main()
