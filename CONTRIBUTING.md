# Adding a core

## Licences

GateLab's own cores (`gatelab.essentials`) are public domain under [CC0 1.0](LICENSE): by
contributing to them you release your work under CC0 1.0 and confirm it is your own.

Third-party cores keep their licence. Only cores with a clear licence file upstream are packaged;
the pack carries the verbatim licence text (`LICENSE.txt`), names the SPDX id in every
`core.json`, and records where the files came from (`upstream`: repository and commit). GateLab
shows the licence before adding a core and asks first for copyleft licences (GPL, LGPL,
CERN-OHL-S/W). Strong-copyleft cores need a separate pack.

## A new core

1. **Folder** `packs/<pack>/cores/<core id>/`: the id is lowercase with `_` or `-`
   (`uart_tx`) and unique across all packs.
2. **`rtl/`**: Verilog 2005 (or the SystemVerilog Yosys reads), one top module. Prefer initial
   values to resets, take the clock as `clk` (or `<name>_clk`) and time in `CLK_HZ`. Module names
   must not collide with other cores of the pack.
3. **`tb/<core id>_tb.v`**: a self-checking testbench that prints `PASS` when everything
   checked out and a `FAIL: …` line per failed check, and ends itself (`$finish`, with a timeout).
   Bring the other side as a model in the same file (a device, a bus target). Check it against
   planted bugs, not only that it passes: test bytes that aren't bit palindromes, sizes that
   aren't powers of two.
4. **`core.json`**:

   ```json
   {
     "schema": 1, "id": "uart_tx", "version": "1.0.0",
     "name": "UART transmitter", "description": "One sentence.",
     "licence": "CC0-1.0", "top": "uart_tx",
     "keywords": ["serial", "uart"],
     "parameters": [{ "name": "CLK_HZ", "default": 12000000, "description": "Clock frequency in Hz" }],
     "ports": [{ "name": "clk", "dir": "in", "description": "Clock" },
               { "name": "data", "dir": "in", "width": 8, "description": "Byte to send" }]
   }
   ```

   Every port of the top with its direction (`in`, `out`, `inout`) and width at the default
   parameters; GateLab refuses a core whose declaration doesn't match its Verilog. Leave
   `families` out: the maintainer's measurement writes it.
5. **`README.md`**: what it does, an example instantiation, what to watch out for.
6. **Raise the pack's version** in `pack.json` for every change to a published pack.

Check with `python3 scripts/check_packs.py`, then open a pull request.

## Publishing (maintainer)

GateLab Essentials live in the FPGALab repo (`Packs/gatelab.essentials`, built into GateLab);
publishing copies them here. From FPGALab, on the Mac with the index key:

```sh
bash tools/fpgacores.sh measure Packs/gatelab.essentials --toolchain <bin> --write yes   # after a core changed
bash tools/publish-library.sh ../fpgacores
```

This copies Essentials into `packs/`, checks every pack (cores measured, testbenches pass),
writes the site into the `gh-pages` worktree (`../fpgacores-site`), checks that it installs,
signs the index and commits there. Commit this repo and push both afterwards.

GitHub Pages serves the `gh-pages` branch (Settings ▸ Pages ▸ Deploy from a branch ▸ `gh-pages`,
`/ (root)`).
