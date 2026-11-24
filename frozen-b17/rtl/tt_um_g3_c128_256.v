`default_nettype none
// G3.06 integrated G3 top for the 8x4 checkpoint (LibreLane, ihp-sg13cmos5l).
// G1.03 host interface on the chip ui/uo buses; uio[7:0] are the eight
// bidirectional protocol pins (P0..P7). DUT = g303_nibble_host (G1.03 loader)
// + C128 core at IMAGE_BYTES=256 (G2.04 candidate-C RTL, frozen G3.03 copies).
// No test hooks: the debug taps (running/done/fault/reason/counters) are
// test-model observability and are left unconnected here.
module tt_um_g3_c128_256 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire ena,
    input  wire clk,
    input  wire rst_n
);
  wire [7:0] pin_value, pin_oe;

  g303_nibble_host #(.IMAGE_BYTES(256)) dut (
    .clk(clk), .rst_n(rst_n), .ena(ena),
    .ui_in(ui_in),
    .uo_out(uo_out),
    .pin_value(pin_value),
    .pin_oe(pin_oe),
    .observed_pins(uio_in),
    .running(), .done(), .fault(), .reason(),
    .consumed_tx(), .rx_count(), .run_ticks()
  );

  assign uio_out = pin_value;
  assign uio_oe  = pin_oe;
endmodule
`default_nettype wire
