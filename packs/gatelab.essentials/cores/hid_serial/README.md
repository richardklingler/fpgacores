# Keyboard and mouse over serial

Click into GateLab's HDMI Input panel and your keyboard and mouse go to the board over its USB serial port; Claude's
`hid_input` tool sends the same. `hid_serial` turns those bytes back into events: USB HID key codes with press and
release, relative mouse moves, absolute pointer positions in the picture's pixels, the wheel, and an "all up" when the
capture ends (so no key stays down).

```verilog
wire        key_valid, key_up, move_valid, position_valid, wheel_valid, all_up;
wire [7:0]  key_usage;
wire signed [7:0] move_dx, move_dy, wheel_dz;
wire [13:0] position_x, position_y;
wire [2:0]  buttons;
hid_serial #(.CLK_HZ(50_000_000)) u_hid (
    .clk(clk), .rx(uart_rx),
    .key_valid(key_valid), .key_usage(key_usage), .key_up(key_up),
    .move_valid(move_valid), .move_dx(move_dx), .move_dy(move_dy),
    .position_valid(position_valid), .position_x(position_x), .position_y(position_y),
    .wheel_valid(wheel_valid), .wheel_dz(wheel_dz), .buttons(buttons), .all_up(all_up));
```

Key codes are USB HID usages (page 7): `0x04`–`0x1D` a–z, `0x1E`–`0x27` 1–0, `0x28` Return, `0x29` Escape, `0x2A`
Backspace, `0x2C` Space, `0x4F`–`0x52` the arrows, `0xE0`–`0xE7` Control, Shift, Option and Command (left, then right).
They name the key's position, not its character: map them to your system's codes (a Mac Plus, a PS/2 scan code set, a
terminal's ASCII) in your design.

The protocol (GateLab HID): a byte with bit 7 set starts a packet, data bytes have it clear.

| Packet | Bytes |
|---|---|
| key | `0x80 \| up << 1 \| usage[7]`, `usage[6:0]` |
| mouse move | `0x90 \| buttons`, `dx`, `dy` (7-bit two's complement, right/down positive) |
| mouse position | `0xA0 \| buttons`, `x[13:7]`, `x[6:0]`, `y[13:7]`, `y[6:0]` |
| wheel | `0xB0`, `dz` |
| all up | `0xBF` |

A packet cut short by the next command byte is dropped; data bytes outside a packet are ignored.
