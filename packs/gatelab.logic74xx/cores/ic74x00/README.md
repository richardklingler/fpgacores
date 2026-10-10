# 74x00 — quad 2-input NAND gate

Four independent NAND gates, `Yn = ~(An & Bn)`, as in the 74LS00, 74HC00 and
74HCT00. Used by GateLab's KiCad import: the package pin table in `core.json` maps KiCad's pin
numbers to the ports. Zero-delay model — for simulation and as an FPGA starting point; synthesis maps it to LUTs.
