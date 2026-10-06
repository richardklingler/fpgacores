# I²C master

Runs one bus command per `go`: `cmd` 0 START (also a repeated start), 1 WRITE `tx_data`
(`ack` tells whether the device answered), 2 READ into `rx_data` (`ack_read` 1 for every byte
but the last), 3 STOP. Wait for `done` (or `ready`) before the next command.

The bus lines are open drain, so the core never drives them high:

```verilog
inout wire i2c_scl, i2c_sda;
assign i2c_scl = scl_oe ? 1'b0 : 1'bz;
assign i2c_sda = sda_oe ? 1'b0 : 1'bz;

i2c_master #(.CLK_HZ(CLK_HZ), .I2C_HZ(100000)) u_i2c (
    .clk(clk), .cmd(cmd), .tx_data(byte), .ack_read(more), .go(go), .ready(i2c_ready),
    .done(i2c_done), .rx_data(answer), .ack(acked),
    .scl_oe(scl_oe), .scl_in(i2c_scl), .sda_oe(sda_oe), .sda_in(i2c_sda)
);
```

Both lines need pull-up resistors (2.2–10 kΩ) on the board or enabled in the constraints.
Reading register `r` of a device at address `a`: START, WRITE `a<<1`, WRITE `r`, START,
WRITE `a<<1 | 1`, READ (ack_read 0), STOP. Devices that stretch the clock are waited for.
