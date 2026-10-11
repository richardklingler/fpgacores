# 74x373 — octal transparent latch

While `LE` is high the latches follow `D0`–`D7`; when `LE` falls they hold. The outputs show the
latches while `OE_n` is low and float otherwise — the latches keep working. As in the 74LS373 and
74HC373 (KiCad names the outputs O0–O7). A latch on an FPGA is a timing hazard (many families
have none and build it from a LUT loop): the FPGA version of a design uses a flip-flop with an
enable. Used by GateLab's KiCad import (package pin table in `core.json`).
