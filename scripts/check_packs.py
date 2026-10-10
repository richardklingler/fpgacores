#!/usr/bin/env python3
"""Checks the library packs' files: format, ids, names and licences. Python 3 standard library only.

    python3 scripts/check_packs.py [packs]

This is the quick check every pull request runs. It catches malformed JSON, missing or mistyped
fields, ids that don't match their folder, duplicate cores, misnamed testbenches and missing
licence texts. Whether every core matches its Verilog, passes its testbench and builds on every
family is checked by the maintainer with GateLab before publishing.
"""

import json
import os
import re
import sys

ID = re.compile(r"[a-z0-9]+([._-][a-z0-9]+)*")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_$]*")
VERSION = re.compile(r"[A-Za-z0-9][A-Za-z0-9.+_-]{0,63}")
FAMILIES = {"ice40", "ecp5", "gowin", "gatemate"}
DIRECTIONS = {"in", "out", "inout"}
# SPDX ids that need no licence text in the pack.
PUBLIC_DOMAIN = {"cc0-1.0", "unlicense", "0bsd"}
# What a pack may contain: data only (GateLab refuses anything else).
ALLOWED = {".json", ".v", ".sv", ".vh", ".svh", ".hex", ".mem", ".md", ".txt",
           # firmware sources a template ships next to its image (text, never compiled by GateLab)
           ".c", ".h", ".s", ".ld"}
CORE_FILES = {".v", ".sv", ".vh", ".svh", ".hex", ".mem"}
MAX_FILE = 10 * 1024 * 1024

errors = 0
warnings = 0


def report(kind, path, message):
    global errors, warnings
    if kind == "error":
        errors += 1
    else:
        warnings += 1
    print(f"  {'✗' if kind == 'error' else '⚠︎'} {path}: {message}")
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::{kind} file={path}::{message}")


KINDS = {
    "a string": lambda v: isinstance(v, str),
    "a whole number": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "a number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "true or false": lambda v: isinstance(v, bool),
    "a list": lambda v: isinstance(v, list),
    "an object": lambda v: isinstance(v, dict),
}


def fields(path, value, table, where):
    """Checks an object against {name: (required, kind, extra check)}."""
    if not isinstance(value, dict):
        report("error", path, f"{where} must be an object")
        return
    for name, (required, kind, check) in table.items():
        if name not in value:
            if required:
                report("error", path, f"{where}: '{name}' is missing")
            continue
        item = value[name]
        if not KINDS[kind](item):
            report("error", path, f"{where}.{name} must be {kind}")
        elif check:
            problem = check(item)
            if problem:
                report("error", path, f"{where}.{name}: {problem}")
    for name in value:
        if name not in table:
            # GateLab ignores unknown fields; here they are most likely typos.
            report("warning", path, f"{where}: unknown field '{name}'")


def matches(pattern, what):
    return lambda v: None if pattern.fullmatch(v) else f"'{v}' isn't a valid {what}"


def non_empty(v):
    return None if v.strip() else "is empty"


MANIFEST = {
    "schema": (True, "a whole number", lambda v: None if v == 1 else "must be 1"),
    "id": (True, "a string", matches(ID, "pack id")),
    "name": (True, "a string", non_empty),
    "version": (True, "a string", matches(VERSION, "version")),
    "type": (True, "a string", lambda v: None if v == "library" else "must be library"),
    "maintainer": (False, "a string", None),
    "description": (False, "a string", None),
    "documentation": (False, "a string", None),
}
PARAMETER = {
    "name": (True, "a string", matches(NAME, "Verilog name")),
    "default": (False, "a whole number", None),
    "description": (False, "a string", None),
}
PORT = {
    "name": (True, "a string", matches(NAME, "Verilog name")),
    "dir": (True, "a string", lambda v: None if v in DIRECTIONS else "must be in, out or inout"),
    "width": (False, "a whole number", lambda v: None if v >= 1 else "must be 1 or more"),
    "description": (False, "a string", None),
}
FAMILY = {
    "tested": (True, "true or false", None),
    "device": (False, "a string", None),
    "resources": (False, "an object", None),
    "fmaxMHz": (False, "a number", None),
}
UPSTREAM = {"url": (True, "a string", None), "commit": (True, "a string", non_empty)}
# For GateLab's KiCad schematic import: the part numbers a model stands for and its package pins
# (by number: KiCad's 74xx symbols leave gate pins unnamed), its clocks, asynchronous inputs and,
# for a one-shot, where R and C sit.
ONE_SHOT = {
    "parameter": (True, "a string", matches(NAME, "Verilog name")),
    "resistorPin": (True, "a string", non_empty),
    "capacitorPins": (True, "a list", lambda v: None if len(v) == 2 else "needs two pins"),
    "internalResistorPin": (False, "a string", None),
    "internalOhms": (False, "a number", None),
    "unconnectedNanoseconds": (True, "a number", None),
}
SCHEMATIC = {
    "parts": (True, "a list", lambda v: None if v and all(isinstance(p, str) and p for p in v) else "needs part keys like 74x00"),
    "pins": (True, "an object", lambda v: None if v and all(isinstance(p, str) for p in v.values()) else "maps pin numbers to port names"),
    "clocks": (False, "a list", None),
    "asyncInputs": (False, "a list", None),
    "oneShot": (False, "an object", None),
}
LOCALIZED = {"name": (True, "a string", non_empty), "description": (True, "a string", non_empty)}
CORE = {
    "schema": (True, "a whole number", lambda v: None if v == 1 else "must be 1"),
    "id": (True, "a string", matches(ID, "core id")),
    "version": (True, "a string", matches(VERSION, "version")),
    "name": (True, "a string", non_empty),
    "description": (True, "a string", non_empty),
    "licence": (True, "a string", non_empty),
    "top": (True, "a string", matches(NAME, "Verilog name")),
    "parameters": (False, "a list", None),
    "ports": (True, "a list", lambda v: None if v else "has no ports"),
    "dependencies": (False, "a list", None),
    "keywords": (False, "a list", None),
    "families": (False, "an object", None),
    "upstream": (False, "an object", None),
    "instantiation": (False, "a string", None),
    "localized": (False, "an object", None),
    "schematic": (False, "an object", None),
    # A simulation model only (a delay): not measured, not for a design on the FPGA.
    "simulationOnly": (False, "true or false", None),
}


def load_json(path):
    try:
        with open(path, encoding="utf-8") as file:
            return json.load(file)
    except (OSError, ValueError) as error:
        report("error", path, f"not valid JSON: {error}")
        return None


def check_files(pack_path):
    """Data only: allowed extensions, no links, no hidden files, size limit, UTF-8."""
    for root, dirs, files in os.walk(pack_path):
        for name in dirs + files:
            path = os.path.join(root, name)
            if os.path.islink(path):
                report("error", path, "symbolic links aren't allowed")
            elif name.startswith("."):
                report("error", path, "hidden files aren't allowed")
        for name in files:
            path = os.path.join(root, name)
            if os.path.splitext(name)[1].lower() not in ALLOWED:
                report("error", path, "packs contain data only: this file type isn't allowed")
            elif os.path.getsize(path) > MAX_FILE:
                report("error", path, "larger than 10 MB")
            else:
                try:
                    with open(path, encoding="utf-8") as file:
                        file.read()
                except UnicodeDecodeError:
                    report("error", path, "must be UTF-8 text")


def check_core(core_path, core_id, pack_has_licence, core_owners, pack_id):
    manifest_path = os.path.join(core_path, "core.json")
    if not os.path.isfile(manifest_path):
        report("error", core_path, "no core.json")
        return
    manifest = load_json(manifest_path)
    if manifest is None:
        return
    fields(manifest_path, manifest, CORE, "core")
    if manifest.get("id") != core_id:
        report("error", manifest_path, f"id '{manifest.get('id')}' doesn't match the folder '{core_id}'")
    if core_id in core_owners:
        report("error", manifest_path, f"core id {core_id} is already used by {core_owners[core_id]}")
    core_owners[core_id] = pack_id

    names = set()
    for index, port in enumerate(manifest.get("ports") or []):
        fields(manifest_path, port, PORT, f"ports[{index}]")
        if isinstance(port, dict):
            if port.get("name") in names:
                report("error", manifest_path, f"port {port.get('name')} is declared twice")
            names.add(port.get("name"))
    for index, parameter in enumerate(manifest.get("parameters") or []):
        fields(manifest_path, parameter, PARAMETER, f"parameters[{index}]")
    for family, result in (manifest.get("families") or {}).items():
        if family not in FAMILIES:
            report("error", manifest_path, f"families: unknown family '{family}'")
        fields(manifest_path, result, FAMILY, f"families.{family}")
    if "upstream" in manifest:
        fields(manifest_path, manifest["upstream"], UPSTREAM, "upstream")
    for language, text in (manifest.get("localized") or {}).items():
        fields(manifest_path, text, LOCALIZED, f"localized.{language}")
    schematic = manifest.get("schematic")
    if schematic is not None:
        fields(manifest_path, schematic, SCHEMATIC, "schematic")
        if isinstance(schematic, dict):
            ports = {p.get("name") for p in manifest.get("ports") or [] if isinstance(p, dict)}
            for pin, port in (schematic.get("pins") or {}).items():
                if port not in ports:
                    report("error", manifest_path, f"schematic.pins.{pin}: '{port}' isn't a port")
            for key in ("clocks", "asyncInputs"):
                for port in schematic.get(key) or []:
                    if port not in ports:
                        report("error", manifest_path, f"schematic.{key}: '{port}' isn't a port")
            if "oneShot" in schematic:
                fields(manifest_path, schematic["oneShot"], ONE_SHOT, "schematic.oneShot")
    if manifest.get("simulationOnly") is True:
        pass  # nothing to measure
    elif any(isinstance(p, dict) and p.get("dir") == "inout" for p in manifest.get("ports") or []):
        pass  # bidirectional ports can't be driven out of context: not measured
    elif not manifest.get("families"):
        report("warning", manifest_path, "not measured yet (the maintainer's measurement writes 'families')")

    # Files: rtl/ and tb/ with the right names, README, licence text.
    rtl = os.path.join(core_path, "rtl")
    tb = os.path.join(core_path, "tb")
    rtl_files = [f for f in os.listdir(rtl)] if os.path.isdir(rtl) else []
    tb_files = [f for f in os.listdir(tb)] if os.path.isdir(tb) else []
    if not any(f.endswith((".v", ".sv")) for f in rtl_files):
        report("error", core_path, "no Verilog in rtl/")
    if not any(f.endswith((".v", ".sv")) for f in tb_files):
        report("error", core_path, "no testbench in tb/")
    for name in tb_files:
        stem, extension = os.path.splitext(name)
        if extension in (".v", ".sv") and not stem.endswith("_tb"):
            report("error", os.path.join(tb, name), "testbenches are named <name>_tb.v")
    for folder, files in ((rtl, rtl_files), (tb, tb_files)):
        for name in files:
            if os.path.splitext(name)[1].lower() not in CORE_FILES:
                report("error", os.path.join(folder, name), "only Verilog and memory images belong here")
    for name in os.listdir(core_path):
        path = os.path.join(core_path, name)
        if os.path.isfile(path) and name not in ("core.json", "README.md") and not name.startswith("LICENSE"):
            report("error", path, "a core holds rtl/, tb/, core.json, README.md and LICENSE* only")
    if not os.path.isfile(os.path.join(core_path, "README.md")):
        report("warning", core_path, "no README.md")
    licence = str(manifest.get("licence", "")).strip().lower()
    core_licence = any(name.startswith("LICENSE") for name in os.listdir(core_path))
    if licence and licence not in PUBLIC_DOMAIN and not (pack_has_licence or core_licence):
        report("error", manifest_path, f"licence {manifest.get('licence')} needs its text: LICENSE.txt in the core or the pack")


def main():
    packs_folder = sys.argv[1] if len(sys.argv) > 1 else "packs"
    if not os.path.isdir(packs_folder):
        print(f"no folder {packs_folder}")
        return 1
    core_owners = {}
    packs = sorted(name for name in os.listdir(packs_folder) if not name.startswith("."))
    for pack_id in packs:
        pack_path = os.path.join(packs_folder, pack_id)
        if not os.path.isdir(pack_path):
            continue
        print(f"pack {pack_id}")
        check_files(pack_path)
        manifest_path = os.path.join(pack_path, "pack.json")
        manifest = load_json(manifest_path) if os.path.isfile(manifest_path) else None
        if manifest is None:
            if not os.path.isfile(manifest_path):
                report("error", pack_path, "no pack.json")
            continue
        fields(manifest_path, manifest, MANIFEST, "pack")
        if manifest.get("id") != pack_id:
            report("error", manifest_path, f"id '{manifest.get('id')}' doesn't match the folder '{pack_id}'")
        cores_path = os.path.join(pack_path, "cores")
        cores = sorted(os.listdir(cores_path)) if os.path.isdir(cores_path) else []
        if not cores:
            report("error", pack_path, "no cores in cores/")
        pack_has_licence = any(name.startswith("LICENSE") for name in os.listdir(pack_path))
        for core_id in cores:
            core_path = os.path.join(cores_path, core_id)
            if os.path.isdir(core_path):
                check_core(core_path, core_id, pack_has_licence, core_owners, pack_id)
        print(f"  {len(cores)} cores")
    print("✓ all packs valid" if errors == 0 else f"✗ {errors} errors")
    if warnings:
        print(f"  {warnings} warnings")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
