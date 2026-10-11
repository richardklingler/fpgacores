# 4011 — quad 2-input NAND

Four NAND gates, `Y = NOT(A AND B)`, CMOS 4000 series (CD4011B, HEF4011B …). The pinout is the 74x00's
(gate 1 on pins 1–3, gate 2's output on 4); KiCad leaves the gate pins unnamed, so the import maps
them by number. Used by GateLab's KiCad import (package pin table in `core.json`).
