# 74x245 — octal bus transceiver

With `OE_n` low, `DIR` high drives the B side from the A side and `DIR` low the A side from the B
side; with `OE_n` high both sides float. `A1`–`A8` and `B1`–`B8` are bidirectional (TI's names;
KiCad calls them A0–A7 and B0–B7 and the enable CE). As in the 74LS245 and 74HC245. Used by GateLab's
KiCad import (package pin table in `core.json`). Inside an FPGA there are no bidirectional
wires: the FPGA version of a design picks one direction per signal.
