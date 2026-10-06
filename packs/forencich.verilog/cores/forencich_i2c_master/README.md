# I²C master (Forencich, AXI-Stream)

Alex Forencich's `i2c_master` from [verilog-i2c](https://github.com/alexforencich/verilog-i2c),
unchanged (MIT, see LICENSE.txt; the notice stays in the file). Commands go through an
AXI-Stream: address plus `read`, `write` or `write_multiple` (bytes until `tlast`) and optional
`start`/`stop`; starts are implied when the bus is idle or the direction changes.
`prescale = clock / (I²C rate × 4)` — 12 MHz at 100 kHz is 30.

The pins are tristate:

```verilog
assign i2c_scl = scl_t ? 1'bz : scl_o;
assign i2c_sda = sda_t ? 1'bz : sda_o;
// scl_i = i2c_scl, sda_i = i2c_sda
```

After an address nobody acknowledges, the core still sends the data byte: `missed_ack` strobes
once for each. The module is called `i2c_master`, like GateLab Essentials' (simpler, byte-level)
`i2c_master`: a project can have only one of them. The testbench is GateLab's.
