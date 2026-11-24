`timescale 1ns/1ps
// G3.03 nibble host loader (G1.03 wire revision 1) for the C128 core.
//
// Implements the dedicated nibble request/response path over ui_in/uo_out
// (G1.03 pin map), frame parsing (OPCODE, LEN, PAYLOAD, CRC_LO, CRC_HI),
// CRC16 (init 0xFFFF, poly 0x1021, MSB-first, no reflection, final XOR 0;
// check vector "123456789" -> 0x29B1), the host state machine
// (EMPTY/LOAD/READY/START_PENDING/RUN/DONE/STOPPED/FAULT), the sticky host
// error, the 65,536-cycle no-progress link block, and translation into the
// C128 core command interface (begin_load/image_we/tx_we/seal/arm/start/
// stop/clear_execution + pin policy masks).
//
// Frame/response byte order: bytes travel MSB-nibble first. Request:
// OPCODE, LEN, PAYLOAD[LEN], CRC_LO, CRC_HI (CRC over OPCODE+LEN+PAYLOAD).
// Response: OPCODE|0x80, LEN, STATUS, RESULT[LEN-1], CRC_LO, CRC_HI (LEN =
// number of RESULT bytes, 0..23; CRC over OPCODE|0x80, LEN, STATUS and the
// RESULT bytes). Multi-byte fields are little-endian.
//
// Design notes (docs/g303-results-v1.0-draft.md):
//  * One nibble accepted per clock. H_READY=0 in reset, on STOP, when the
//    link is blocked, or while a response is outstanding (one frame at a
//    time).
//  * Response policy: the response starts at T+1 (T = last request nibble
//    accepted) for every opcode, so first R_VALID always meets the 16/256/
//    512-cycle class budgets by construction. The final response byte
//    (CRC_HI) is held until the mapped core action completes (WRITE_IMAGE
//    K, ARM_DATA K+2 fast / N+K+2 full reload, READ_RX count+1), so a
//    command is never reported OK before it applied.
//  * COMMIT never seals the core: core tx_we requires loading=1 and core
//    arm requires executable_valid (sealed), so ARM_DATA performs
//    tx_we[K]+seal+arm (fast path, first arm of the core load session) or a
//    full reload from shadow RAM (re-arm / DONE: begin_load + N image_we +
//    K tx_we + seal + arm).
//  * START enters START_PENDING; the core start pulses on acceptance of the
//    last success-response nibble (G1.03); arm is consumed. A no-progress
//    block during START_PENDING cancels the start (image-valid/arm cleared,
//    STOPPED, link blocked) per G1.06.
//  * Debug taps (running/done/fault/reason/consumed_tx/rx_count/run_ticks)
//    are test-model observability, not G1.03 pads (the wire exposes the
//    same data via the STATUS opcode).
module g303_nibble_host #(parameter integer IMAGE_BYTES=256)(
  input wire clk, rst_n, ena,
  input wire [7:0] ui_in,    // [3:0] req nibble, [4] H_VALID, [5] R_READY, [6] STOP, [7] resv
  output wire [7:0] uo_out,  // [3:0] resp nibble, [4] H_READY, [5] R_VALID, [6] RUNNING, [7] ALERT
  output wire [7:0] pin_value, pin_oe,
  input wire [7:0] observed_pins,
  // test-model observability (not G1.03 pads):
  output wire running, done, fault,
  output wire [7:0] reason,
  output wire [4:0] consumed_tx, rx_count,
  output wire [20:0] run_ticks
);
 localparam integer CAP = IMAGE_BYTES;
 localparam [15:0] ARCH_ID = 16'hC128;
 localparam [7:0] FMT_REV = 8'd1;
 localparam [7:0] OP_DISC=8'h00, OP_STAT=8'h01, OP_RECOV=8'h02,
                  OP_BEGIN=8'h10, OP_WRITE=8'h11, OP_COMMIT=8'h12,
                  OP_ARM=8'h20, OP_START=8'h21, OP_READRX=8'h22, OP_STOP=8'h7F;
 localparam [7:0] S_OK=8'h00, S_BADOPEC=8'h01, S_BADLEN=8'h02, S_BADCRC=8'h03,
                  S_BADSTATE=8'h04, S_RANGE=8'h05, S_BADARCH=8'h06,
                  S_INCOMPLETE=8'h07, S_IMGCRCE=8'h08, S_BADENTRY=8'h09,
                  S_BADPIN=8'h0A, S_BUSYRUN=8'h0B, S_NOTARMED=8'h0C,
                  S_BADKEY=8'h0D, S_TIMEOUT=8'h0E, S_NODATA=8'h0F;
 localparam [3:0] ST_EMPTY=4'h1, ST_LOAD=4'h2, ST_READY=4'h3, ST_SPEND=4'h4,
                  ST_RUN=4'h5, ST_DONE=4'h6, ST_STOPPED=4'h7, ST_FAULT=4'h8;
 localparam [3:0] A_NONE=4'h0, A_BEGIN=4'h1, A_WRITE=4'h2, A_ARMF=4'h3,
                  A_ARMR=4'h4, A_READ=4'h5, A_STOP=4'h6, A_RECOVER=4'h7;

 wire wire_stop = ui_in[6];
 wire hvalid = ui_in[4];
 wire rready = ui_in[5];
 wire [3:0] reqnib = ui_in[3:0];

 // ------------------------------------------------------------------ reset
 reg [2:0] rst_cnt;   // B13: H_READY low for 4 edges after reset release (G1.06: >=4 rising edges)
 wire reset = !rst_n || !ena;
 wire up = !reset && (rst_cnt >= 3'd4);
 always @(posedge clk) begin
  if(reset) rst_cnt <= 3'd0;
  else if(rst_cnt < 3'd4) rst_cnt <= rst_cnt + 3'd1;
 end

 // ------------------------------------------------------------- frame parse
 reg parsing, nib_phase, resp_active, resp_nib_phase;
 reg [4:0] fbyte, rbyte;
 reg [7:0] cur_byte;
 reg [7:0] f_opcode;
 reg [4:0] f_len;
 reg [7:0] f_payload [0:23];
 reg [15:0] crc_acc, img_crc;
 reg [7:0] crc_lo;

 // ------------------------------------------------------------ host state
 reg [3:0] state;
 reg image_valid, armed, sticky, partial_rx;
 reg [7:0] sticky_reason;
 reg [15:0] declared_len, entry_offset, accepted, crc_stored;
 reg [4:0] armed_tx, armed_rx, core_tx_count;
 reg [7:0] m_allow, m_od, m_oe, m_val;

 // ------------------------------------------------------------ response
 reg [7:0] resp_ram [0:29];
 reg [4:0] resp_len, a_txk;
 reg [9:0] a_len, a_i;
 reg [15:0] a_base;
 reg resp_is_start;
 reg action_done;

 // ------------------------------------------------------- core action eng
 reg [3:0] a_op;
 reg core_begin, core_iwe, core_seal, core_txwe, core_arm, core_start,
     core_stop, core_clear, core_rxre;
 reg [7:0] core_iadr, core_idata;
 reg [3:0] core_tadr;
 reg [7:0] core_tdata;
 reg [4:0] core_atx, core_arx;
 reg [3:0] core_entry, core_rxadr;

 // ------------------------------------------------------------ link block
 reg link_blocked;
 reg [16:0] np_cnt;

 // ---------------------------------------------------------- shadow image
 reg [7:0] shadow [0:CAP-1];

 // ------------------------------------------------------------- handshake
 wire [4:0] last_rbyte = 4'd4 + resp_len;      // index of CRC_HI byte
 wire rvalid = resp_active && up && !link_blocked && !wire_stop
              && !(rbyte == last_rbyte && !action_done);
 wire hready = up && !link_blocked && !resp_active && !wire_stop;
 wire req_accept = hvalid && hready;
 wire resp_accept = rvalid && rready;
 wire [3:0] cur_nib = resp_nib_phase ? resp_ram[rbyte][7:4] : resp_ram[rbyte][3:0];
 wire [7:0] byte_done = {reqnib, cur_byte[3:0]};
 wire disp_edge = parsing && req_accept && (nib_phase == 1)
                  && (fbyte == 5'd3 + f_len);

 // ----------------------------------------------------------------- core
 wire [7:0] core_rxdata;
 wire core_rxvalid;
 g2_c128 #(.IMAGE_BYTES(CAP)) core(
  .clk(clk), .clear_execution(core_clear), .stop(core_stop),
  .begin_load(core_begin), .image_we(core_iwe), .image_address(core_iadr), .image_data(core_idata),
  .seal(core_seal), .tx_we(core_txwe), .tx_address(core_tadr), .tx_data(core_tdata),
  .arm(core_arm), .arm_tx_count(core_atx), .arm_rx_capacity(core_arx),
  .start(core_start), .entry_row(core_entry),
  .initial_value(m_val), .initial_oe(m_oe), .drive_allow(m_allow), .open_drain(m_od),
  .observed_pins(observed_pins),
  .rx_re(core_rxre), .rx_read_address(core_rxadr),
  .rx_read_data(core_rxdata), .rx_read_valid(core_rxvalid),
  .pin_value(pin_value), .pin_oe(pin_oe),
  .running(running), .done(done), .fault(fault), .reason(reason),
  .consumed_tx(consumed_tx), .rx_count(rx_count), .run_ticks(run_ticks),
  .fire(), .reject_now());

 // ------------------------------------------------------------------ CRC
 function automatic [15:0] crc16;
  input [8*31-1:0] data;
  input [4:0] nbytes;
  integer i, b;
  reg [15:0] c;
  begin
   c = 16'hFFFF;
   // B15: constant loop bound (yosys proc pass); gate on nbytes so
   // bytes >= nbytes are skipped — behavior identical to the old bound.
   for(i = 0; i < 31; i = i + 1) begin
    if (i < nbytes) begin
     for(b = 7; b >= 0; b = b - 1) begin
      c = (c[15] ^ data[8*i + b]) ? (c << 1) ^ 16'h1021 : (c << 1);
     end
    end
   end
   crc16 = c;
  end
 endfunction
 function automatic [15:0] crc16_ext;
  input [15:0] init;
  input [8*31-1:0] data;
  input [4:0] nbytes;
  integer i, b;
  reg [15:0] c;
  begin
   c = init;
   for(i = 0; i < 31; i = i + 1) begin
    if (i < nbytes) begin
     for(b = 7; b >= 0; b = b - 1) begin
      c = (c[15] ^ data[8*i + b]) ? (c << 1) ^ 16'h1021 : (c << 1);
     end
    end
   end
   crc16_ext = c;
  end
 endfunction

 reg [8*23-1:0] pvec;
 integer j1;
 always @* begin
  for(j1 = 0; j1 < 23; j1 = j1 + 1) pvec[8*j1 +: 8] = f_payload[j1];
 end
 reg [8*30-1:0] rvec;
 wire [15:0] rvec_crc = crc16(rvec, 3'd3 + a_len[4:0]);
 wire [9:0] armr_t = a_i - a_len - 10'd1;
 integer j2;
 always @* begin
  for(j2 = 0; j2 < 30; j2 = j2 + 1)
   rvec[8*j2 +: 8] = (j2 < 5 + a_len) ? resp_ram[j2] : 8'h00;
 end

 // ---------------------------------------------------- dispatch (combin)
 wire [15:0] crc_rx = {byte_done, crc_lo};
 reg [7:0] d_status;
 reg [4:0] d_len;
 reg [8*23-1:0] d_result;
 reg [3:0] d_action;
 reg [3:0] d_next;
 reg d_image_valid, d_armed, d_partial, d_sticky_clear, d_resp_start;
 reg [15:0] d_accepted, d_dlen, d_eoff, d_crcs;
 reg [4:0] d_atx, d_arx;
 reg [7:0] d_allow, d_od, d_oe, d_val;
 reg [9:0] d_a_len;
 reg [15:0] d_a_base;
 reg [8*30-1:0] d_body;
 reg [15:0] d_crc;
 reg [15:0] d_p_arch, d_p_len, d_p_entry, d_p_crc;
 reg [15:0] d_p_off;

 always @* begin
  d_status = S_OK; d_len = 5'd0; d_result = 232'd0; d_action = A_NONE;
  d_next = state; d_image_valid = image_valid; d_armed = armed;
  d_partial = partial_rx; d_sticky_clear = 0; d_resp_start = 0;
  d_accepted = accepted; d_dlen = declared_len; d_eoff = entry_offset;
  d_crcs = crc_stored; d_atx = armed_tx; d_arx = armed_rx;
  d_allow = m_allow; d_od = m_od; d_oe = m_oe; d_val = m_val;
  d_a_len = 10'd0; d_a_base = accepted;
  d_p_arch = {f_payload[1], f_payload[0]};
  d_p_len  = {f_payload[4], f_payload[3]};
  d_p_entry= {f_payload[6], f_payload[5]};
  d_p_crc  = {f_payload[8], f_payload[7]};
  d_p_off  = {f_payload[1], f_payload[0]};

  if(!((crc_acc == crc_rx) && (fbyte == 5'd3 + f_len) && parsing)) begin
   d_status = S_BADCRC;
  end else begin
   case(f_opcode)
    OP_DISC: begin
     if(f_len != 5'd0) d_status = S_BADLEN;
     else begin
      d_len = 5'd23;
      // result bytes [0..22]: wire_rev, arch LE, fmt, cap LE, tx, rx, maxp,
      // clock LE(4), watchdog LE(4), short_wait LE(2), host_gap LE(4)
      d_result = {8'h00, 8'h01, 8'h00, 8'h00, 8'h55, 8'hF0,
                  8'h00, 8'h1E, 8'h84, 8'h80,
                  8'h01, 8'h31, 8'hD0, 8'h00,
                  8'h18, 8'h10, 8'h10,
                  8'h01, 8'h00,
                  8'h01, 8'hC1, 8'h28, 8'h01};
     end
    end
    OP_STAT: begin
     if(f_len != 5'd0) d_status = S_BADLEN;
     else begin
      d_len = 5'd16;
      // B17: full 21-bit run_ticks contiguous at [100:80] (G1 interfaces.md
      // STATUS [13:16] = elapsed_RUN_cycles; G3.03 results v1.0 sec.5).
      d_result = {8'h00, run_ticks,
                  rx_count, armed_rx, consumed_tx, armed_tx,
                  accepted[15:8], accepted[7:0],
                  (state == ST_LOAD || image_valid) ? declared_len[15:8] : 8'h00,
                  (state == ST_LOAD || image_valid) ? declared_len[7:0] : 8'h00,
                  sticky_reason, reason,
                  {4'b0, partial_rx, sticky, armed, image_valid}, state};
     end
    end
    OP_RECOV: begin
     if(f_len != 5'd0) d_status = S_BADLEN;
     else if(state == ST_RUN || state == ST_SPEND) d_status = S_BUSYRUN;
     else begin
      d_action = A_RECOVER; d_next = ST_EMPTY; d_sticky_clear = 1;
      d_image_valid = 0; d_armed = 0; d_partial = 0;
      d_accepted = 16'd0;
     end
    end
    OP_BEGIN: begin
     if(f_len != 5'd13) d_status = S_BADLEN;
     else if(state == ST_RUN || state == ST_SPEND) d_status = S_BUSYRUN;
     else if(state == ST_FAULT || sticky) d_status = S_BADSTATE;
     else if(!(d_p_arch == ARCH_ID && f_payload[2] == FMT_REV))
      d_status = S_BADARCH;
     else if(((f_payload[10] | f_payload[11]) & ~f_payload[9]) != 8'h00
             || (f_payload[12] & ~f_payload[9]) != 8'h00
             || (f_payload[12] & f_payload[10]) != 8'h00)
      d_status = S_BADPIN;
     else if(d_p_len == 16'd0 || d_p_len > 16'(CAP))
      d_status = S_RANGE;
     else if(d_p_entry >= d_p_len || (d_p_entry & 16'h000F) != 16'd0)
      d_status = S_BADENTRY;
     else begin
      d_action = A_BEGIN; d_next = ST_LOAD;
      d_dlen = d_p_len; d_eoff = d_p_entry; d_crcs = d_p_crc;
      d_allow = f_payload[9]; d_od = f_payload[10];
      d_oe = f_payload[11]; d_val = f_payload[12];
      d_image_valid = 0; d_armed = 0; d_partial = 0;
      d_accepted = 16'd0;
     end
    end
    OP_WRITE: begin
     if(f_len < 5'd3 || f_len > 5'd18) d_status = S_BADLEN;
     else if(state == ST_RUN || state == ST_SPEND) d_status = S_BUSYRUN;
     else if(state != ST_LOAD || sticky) d_status = S_BADSTATE;
     else if(d_p_off != accepted) d_status = S_RANGE;
     else if(d_p_off + 16'(f_len - 5'd2) > declared_len)
      d_status = S_RANGE;
     else begin
      d_action = A_WRITE;
      d_a_len = 10'(f_len - 5'd2);
      d_a_base = accepted;
      d_accepted = accepted + 16'(f_len - 5'd2);
     end
    end
    OP_COMMIT: begin
     if(f_len != 5'd0) d_status = S_BADLEN;
     else if(state == ST_RUN || state == ST_SPEND) d_status = S_BUSYRUN;
     else if(state != ST_LOAD || sticky) d_status = S_BADSTATE;
     else if(accepted != declared_len) d_status = S_INCOMPLETE;
     else if(img_crc != crc_stored) d_status = S_IMGCRCE;
     else if(entry_offset >= declared_len || (entry_offset & 16'h000F) != 16'd0)
      d_status = S_BADENTRY;
     else begin
      d_next = ST_READY; d_image_valid = 1;
     end
     if((d_status == S_INCOMPLETE || d_status == S_IMGCRCE || d_status == S_BADENTRY)
        && state == ST_LOAD) begin
      d_next = ST_FAULT; d_image_valid = 0;   // B12: only semantic COMMIT failures trap to FAULT
     end
    end
    OP_ARM: begin
     if(f_len < 5'd2 || f_len > 5'd18) d_status = S_BADLEN;
     else if(state == ST_RUN || state == ST_SPEND) d_status = S_BUSYRUN;
     else if(state != ST_READY && state != ST_DONE) d_status = S_BADSTATE;
     else if(!image_valid || sticky) d_status = S_BADSTATE;
     else if(f_payload[0] != f_len - 5'd2) d_status = S_BADLEN;
     else if(f_payload[1] > 8'd16) d_status = S_RANGE;
     else begin
      d_armed = 1; d_arx = f_payload[1]; d_atx = f_len - 5'd2;
      d_partial = 0; d_next = ST_READY;
      if(state == ST_READY && core_tx_count == 5'd0) d_action = A_ARMF;
      else begin d_action = A_ARMR; d_a_len = 10'(declared_len); end
     end
    end
    OP_START: begin
     if(f_len != 5'd2) d_status = S_BADLEN;
     else if(state == ST_RUN || state == ST_SPEND) d_status = S_BUSYRUN;
     else if(state != ST_READY || sticky) d_status = S_BADSTATE;
     else if(!armed) d_status = S_NOTARMED;
     else if(!(f_payload[0] == 8'hC3 && f_payload[1] == 8'h3C))
      d_status = S_BADKEY;
     else begin
      d_next = ST_SPEND; d_resp_start = 1;
     end
    end
    OP_READRX: begin
     if(f_len != 5'd2) d_status = S_BADLEN;
     else if(state == ST_RUN || state == ST_SPEND) d_status = S_BUSYRUN;
     else if(state != ST_DONE && state != ST_STOPPED && state != ST_FAULT)
      d_status = S_BADSTATE;
     else if(sticky) d_status = S_BADSTATE;
     else if(rx_count == 5'd0) d_status = S_NODATA;
     else if(f_payload[1] == 8'd0 || f_payload[1] > 8'd16) d_status = S_RANGE;
     else if(16'(f_payload[0]) + 16'(f_payload[1]) > 16'(rx_count))
      d_status = S_RANGE;
     else begin
      d_action = A_READ; d_len = f_payload[1]; d_a_len = 10'(f_payload[1]);
     end
    end
    OP_STOP: begin
     if(f_len != 5'd0) d_status = S_BADLEN;
     else begin
      d_action = A_STOP; d_next = ST_STOPPED; d_sticky_clear = 1;
      d_partial = running || partial_rx;
      d_image_valid = 0; d_armed = 0;   // B11: G1.06 STOPPED: image-valid=0, armed=0
     end
    end
    default: d_status = S_BADOPEC;
   endcase
  end
  // body: byte0=op|80, byte1=LEN, byte2=STATUS, byte3..=RESULT, 30B total
  d_body = {32'h0, d_result, d_status, {3'b0, d_len}, f_opcode | 8'h80};
  d_crc = crc16(d_body, 3'd3 + d_len);
 end

 // ------------------------------------------------------------ main clock
 integer j3;
 always @(posedge clk) begin
  if(reset) begin
   state <= ST_EMPTY; image_valid <= 0; armed <= 0; sticky <= 0;
   sticky_reason <= 8'h00; partial_rx <= 0;
   declared_len <= 16'd0; entry_offset <= 16'd0; accepted <= 16'd0;
   crc_stored <= 16'd0; img_crc <= 16'hFFFF;
   armed_tx <= 5'd0; armed_rx <= 5'd0; core_tx_count <= 5'd0;
   m_allow <= 8'h00; m_od <= 8'h00; m_oe <= 8'h00; m_val <= 8'h00;
   parsing <= 0; nib_phase <= 0; fbyte <= 5'd0; cur_byte <= 8'h00;
   f_opcode <= 8'h00; f_len <= 5'd0; crc_acc <= 16'hFFFF; crc_lo <= 8'h00;
   resp_active <= 0; resp_nib_phase <= 0; rbyte <= 5'd0;
   resp_len <= 5'd0; resp_is_start <= 0;
   a_op <= A_NONE; a_i <= 10'd0; a_len <= 10'd0; a_txk <= 5'd0;
   a_base <= 16'd0; action_done <= 1;
   core_begin <= 0; core_iwe <= 0; core_seal <= 0; core_txwe <= 0;
   core_arm <= 0; core_start <= 0; core_stop <= 0; core_clear <= 1;
   core_iadr <= 8'd0; core_idata <= 8'd0; core_tadr <= 4'd0;
   core_tdata <= 8'd0; core_atx <= 5'd0; core_arx <= 5'd0;
   core_entry <= 4'd0; core_rxre <= 0; core_rxadr <= 4'd0;
   link_blocked <= 0; np_cnt <= 17'd0;
   for(j3 = 0; j3 < 30; j3 = j3 + 1) resp_ram[j3] <= 8'h00;
  end else begin
   core_begin <= 0; core_iwe <= 0; core_seal <= 0; core_txwe <= 0;
   core_arm <= 0; core_start <= 0; core_stop <= 0; core_clear <= 0;
   core_rxre <= 0;

   // ------------------------------------------------------ reset release
   if(rst_cnt < 3'd4) begin
    state <= ST_EMPTY; image_valid <= 0; armed <= 0; sticky <= 0;
    sticky_reason <= 8'h00; partial_rx <= 0;
    declared_len <= 16'd0; entry_offset <= 16'd0; accepted <= 16'd0;
    crc_stored <= 16'd0; img_crc <= 16'hFFFF;
    armed_tx <= 5'd0; armed_rx <= 5'd0; core_tx_count <= 5'd0;
    m_allow <= 8'h00; m_od <= 8'h00; m_oe <= 8'h00; m_val <= 8'h00;
    parsing <= 0; nib_phase <= 0; fbyte <= 5'd0;
    resp_active <= 0; resp_nib_phase <= 0; rbyte <= 5'd0;
    resp_is_start <= 0;
    a_op <= A_NONE; a_i <= 10'd0; action_done <= 1;
    core_clear <= 1;
    link_blocked <= 0; np_cnt <= 17'd0;
   end
   // -------------------------------------------------------- physical STOP
   else if(wire_stop) begin
    parsing <= 0; nib_phase <= 0; fbyte <= 5'd0;
    resp_active <= 0; resp_nib_phase <= 0; rbyte <= 5'd0;
    resp_is_start <= 0;
    a_op <= A_NONE; a_i <= 10'd0; action_done <= 1;
    sticky <= 0;
    core_stop <= 1;
    state <= ST_STOPPED;
    image_valid <= 0; armed <= 0;
    partial_rx <= running || partial_rx;
    link_blocked <= 0; np_cnt <= 17'd0;
   end
   else begin
    // ------------------------------------------------- no-progress timer
    if(req_accept || resp_accept) np_cnt <= 17'd0;
    else if(parsing || resp_active) begin
     if(np_cnt >= 17'd65535) begin
      link_blocked <= 1;
      np_cnt <= 17'd65535;
      resp_active <= 0;
      resp_is_start <= 0;
      parsing <= 0;
      if(state == ST_SPEND) begin
       state <= ST_STOPPED;
       image_valid <= 0; armed <= 0;
      end
     end else np_cnt <= np_cnt + 17'd1;
    end

    if(!link_blocked) begin
     // --------------------------------------------------- request parser
     if(!parsing && !resp_active && req_accept) begin
      parsing <= 1; nib_phase <= 1; cur_byte <= {4'd0, reqnib}; fbyte <= 5'd0;
      crc_acc <= 16'hFFFF;   // B14: per-frame request CRC per G1.03 (was chained across frames)
     end else if(parsing && req_accept) begin
      if(nib_phase == 0) begin
       cur_byte <= {4'd0, reqnib}; nib_phase <= 1;
      end else begin
       if(fbyte == 5'd0) begin
        f_opcode <= byte_done;
        crc_acc <= crc16_ext(crc_acc,
                 {240'h0, byte_done}, 5'd1);
       end else if(fbyte == 5'd1) begin
        if(byte_done > 8'd24) begin
         link_blocked <= 1;       // LEN > 24: block, no response promised
         parsing <= 0;
        end else begin
         f_len <= byte_done[4:0];
         crc_acc <= crc16_ext(crc_acc,
                  {240'h0, byte_done}, 5'd1);
        end
       end else if(fbyte <= 5'd1 + f_len) begin
        f_payload[fbyte - 5'd2] <= byte_done;
        crc_acc <= crc16_ext(crc_acc,
                 {240'h0, byte_done}, 5'd1);
       end else if(fbyte == 5'd2 + f_len) begin
        crc_lo <= byte_done;
       end
       fbyte <= fbyte + 5'd1;
       nib_phase <= 0;
      end
     end

     // ----------------------------------------------------- dispatch edge
     if(disp_edge) begin
      parsing <= 0;
      resp_active <= 1; resp_nib_phase <= 0; rbyte <= 5'd0;
      resp_len <= d_len; resp_is_start <= d_resp_start;
      for(j3 = 0; j3 < 30; j3 = j3 + 1) resp_ram[j3] <= d_body[8*j3 +: 8];
      // B16: READ_RX rejection responses (A_NONE) must carry the valid
      // d_crc per G1.03; only the A_READ success path defers the CRC
      // bytes to the action engine (rvec_crc over the read data).
      if(f_opcode != OP_READRX || d_action != A_READ) begin
       resp_ram[3 + d_len] <= d_crc[7:0];
       resp_ram[4 + d_len] <= d_crc[15:8];
      end
      a_op <= d_action; a_i <= 10'd0; a_len <= d_a_len;
      a_txk <= (d_action == A_ARMF || d_action == A_ARMR) ? (f_len - 5'd2)
                                                          : 5'd0;
      a_base <= d_a_base;
      action_done <= (d_action == A_NONE);
      state <= d_next;
      image_valid <= d_image_valid;
      armed <= d_armed;
      partial_rx <= d_partial;
      accepted <= d_accepted;
      declared_len <= d_dlen; entry_offset <= d_eoff; crc_stored <= d_crcs;
      m_allow <= d_allow; m_od <= d_od; m_oe <= d_oe; m_val <= d_val;
      armed_tx <= d_atx; armed_rx <= d_arx;
      core_tx_count <= (d_action == A_BEGIN || d_action == A_RECOVER) ? 5'd0
        : (d_action == A_ARMF || d_action == A_ARMR) ? (f_len - 5'd2)
        : core_tx_count;
      img_crc <= (d_action == A_BEGIN) ? 16'hFFFF
        : (d_action == A_WRITE) ? crc16_ext(img_crc, pvec[16 +: 8*23], d_a_len)
        : img_crc;
      if(d_sticky_clear) sticky <= 0;
      else if(d_status != S_OK && !sticky) begin
       sticky <= 1; sticky_reason <= d_status;
      end
     end

     // ------------------------------------------------ response transfer
     if(resp_accept) begin
      if(resp_nib_phase == 0) begin
       resp_nib_phase <= 1;
      end else if(rbyte < last_rbyte) begin
       rbyte <= rbyte + 5'd1; resp_nib_phase <= 0;
      end else begin
       resp_active <= 0;
       if(resp_is_start) begin
        core_start <= 1;
        core_entry <= entry_offset[7:4];
        state <= ST_RUN;
        armed <= 0;
       end
       resp_is_start <= 0;
      end
     end

     // ----------------------------------------------------- action engine
     if(a_op != A_NONE && !action_done) begin
      case(a_op)
       A_BEGIN: begin
        core_begin <= 1;
        action_done <= 1;
       end
       A_WRITE: begin
        if(a_i < a_len) begin
         core_iwe <= 1;
         core_iadr <= a_base[7:0] + a_i[7:0];
         core_idata <= pvec[8*(a_i + 5'd2) +: 8];
         shadow[a_base[7:0] + a_i[7:0]] <= pvec[8*(a_i + 5'd2) +: 8];
         a_i <= a_i + 10'd1;
        end else action_done <= 1;
       end
       A_ARMF: begin
        if(a_i < a_txk) begin
         core_txwe <= 1;
         core_tadr <= a_i[3:0];
         core_tdata <= pvec[8*(a_i + 5'd2) +: 8];
         a_i <= a_i + 10'd1;
        end else if(a_i == a_txk) begin
         core_seal <= 1;
         a_i <= a_i + 10'd1;
        end else if(a_i == a_txk + 10'd1) begin
         core_arm <= 1;
         core_atx <= a_txk;
         core_arx <= pvec[12:8];
         a_i <= a_i + 10'd1;
        end else action_done <= 1;
       end
       A_ARMR: begin
        if(a_i == 10'd0) begin
         core_begin <= 1;
         a_i <= a_i + 10'd1;
        end else if(a_i <= a_len) begin
         core_iwe <= 1;
         core_iadr <= a_i[7:0] - 8'd1;
         core_idata <= shadow[a_i[7:0] - 8'd1];
         a_i <= a_i + 10'd1;
        end else if(a_i <= a_len + a_txk) begin
         core_txwe <= 1;
         core_tadr <= armr_t[3:0];
         core_tdata <= pvec[8*(armr_t + 5'd2) +: 8];
         a_i <= a_i + 10'd1;
        end else if(a_i == a_len + a_txk + 10'd1) begin
         core_seal <= 1;
         a_i <= a_i + 10'd1;
        end else if(a_i == a_len + a_txk + 10'd2) begin
         core_arm <= 1;
         core_atx <= a_txk;
         core_arx <= pvec[12:8];
         a_i <= a_i + 10'd1;
        end else action_done <= 1;
       end
       A_READ: begin
        if(a_i == 10'd0) begin
         core_rxadr <= f_payload[0][3:0];
         core_rxre <= 1;
         a_i <= a_i + 10'd1;
        end else if(a_i <= a_len) begin
         if(core_rxre) resp_ram[3 + a_i - 5'd1] <= core_rxdata;
         if(a_i < a_len) core_rxadr <= f_payload[0][3:0] + a_i[3:0];
         core_rxre <= (a_i < a_len);
         a_i <= a_i + 10'd1;
        end else if(a_i == a_len + 10'd1) begin
         // one cycle after the last byte is captured: rvec is stable
         resp_ram[3 + a_len] <= rvec_crc[7:0];
         resp_ram[4 + a_len] <= rvec_crc[15:8];
         a_i <= a_i + 10'd1;
         action_done <= 1;
        end else action_done <= 1;
       end
       A_STOP: begin
        core_stop <= 1;
        action_done <= 1;
       end
       A_RECOVER: begin
        core_clear <= 1;
        action_done <= 1;
       end
       default: action_done <= 1;
      endcase
     end

     // ------------------------------------------------------ core monitor
     if(!disp_edge) begin
      if(running && state == ST_RUN) state <= ST_RUN;
      else if(done && !running && state == ST_RUN) state <= ST_DONE;
      else if(fault && !running && state == ST_RUN) begin
       state <= ST_FAULT; partial_rx <= 1;
      end
     end
    end
   end
  end
 end

 assign uo_out[3:0] = rvalid ? cur_nib : 4'b0000;
 assign uo_out[4] = hready;
 assign uo_out[5] = rvalid;
 assign uo_out[6] = up ? running : 1'b0;
 assign uo_out[7] = up ? (fault || sticky || link_blocked) : 1'b0;

endmodule
