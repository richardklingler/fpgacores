# 74x32 — quad 2-input OR gate

Four independent OR gates, `Yn = An | Bn`, as in the 74LS32, 74HC32 and
74HCT32. Used by GateLab's KiCad import: the package pin table in `core.json` maps KiCad's pin
numbers to the ports. Zero-delay model — for simulation and as an FPGA starting point; synthesis maps it to LUTs.
