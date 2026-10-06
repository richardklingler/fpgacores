# fpgacores

Library packs for GateLab, the native macOS IDE for open-source FPGA flows: reusable Verilog cores
— UART, SPI, I²C, FIFOs, LED and display drivers, CPUs — each with a self-checking testbench and
its resources and Fmax **measured** on every FPGA family GateLab supports (iCE40, ECP5, Gowin,
GateMate).

GateLab reads the published index at `https://richardklingler.github.io/fpgacores/index.json`
(Settings ▸ Packages). The index is signed; GateLab checks the signature and every download's
checksum, and packs contain data only (JSON, Verilog, Markdown, memory images) — never scripts.
File ▸ Add Core… copies a core into a project (`src/lib/<core>/`, its testbench to
`sim/lib/<core>/`) and records it with its licence in the project's licence list.

## Packs

| Pack | What | Licence |
|---|---|---|
| `gatelab.essentials` | GateLab's own basic cores (also built into GateLab) | CC0 1.0 |

Third-party packs keep their upstream licence; it is named per core and its text is in the pack.

## Layout

```
packs/<pack id>/
    pack.json                       id, name, version, type "library", description, maintainer
    LICENSE.txt                     the licence text (required unless public domain)
    cores/<core id>/
        core.json                   name, licence (SPDX), top, parameters, ports, measured families
        rtl/*.v                     the synthesisable sources
        tb/<core id>_tb.v           self-checking testbench: prints PASS or FAIL lines
        README.md                   usage and an example instantiation
scripts/check_packs.py              the format check (Python 3, nothing to install)
```

## Checking a pack

```sh
python3 scripts/check_packs.py
```

checks every pack's files: valid JSON, fields and types, ids that match their folders, unique core
ids, testbench names, licence texts, data-only files. Pull requests run the same check.

Before a pack is published, the maintainer checks it with GateLab itself: every core's declared
ports and parameters against its Verilog, every testbench with iverilog, and a full synthesis and
place-and-route of every core on one reference device per family — those runs write the
`families` figures. A core without a passing testbench isn't published.

See [CONTRIBUTING.md](CONTRIBUTING.md) to add a core.

## Licence

GateLab's own packs and everything else in this repository that isn't marked otherwise:
[CC0 1.0 Universal](LICENSE) (public domain). Third-party packs are under the licence each of
their cores names, with the licence text in the pack.
