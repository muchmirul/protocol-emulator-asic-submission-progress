`timescale 1ns/1ps
module g2_ac_scalar_decode #(
    parameter bit C_SCALAR = 1'b0,
    parameter integer STORE_BYTES = 128
) (
    input  wire [4:0] op,
    input  wire [19:0] arg,
    input  wire stamp,
    input  wire [5:0] next_row,
    input  wire [3:0] alt_row,
    input  wire [8:0] committed_bytes,
    input  wire [7:0] observed,
    input  wire flag,
    input  wire [4:0] loop0, loop1,
    input  wire [7:0] cmask, cvalue,
    input  wire [4:0] tx_consumed, tx_initialized,
    input  wire [4:0] rx_count, rx_capacity,
    input  wire [3:0] nbit,
    input  wire collect,
    output reg static_illegal,
    output wire static_bounds,
    output wire is_timer_bypass,
    output wire is_wait,
    output wire is_end,
    output wire is_programmed_fault,
    output wire condition_value,
    output reg shift_bit,
    output wire [5:0] next_row_wire,
    output wire [5:0] branch_row,
    output wire [5:0] successor_row
);
    localparam integer RECORD_BYTES = C_SCALAR ? 16 : 4;
    localparam [8:0] STORE_LIMIT = STORE_BYTES;
    reg [19:0] allowed_arg;
    reg extra_illegal;
    reg old_condition;
    wire condition_op = (op == 5'h0a) || (op == 5'h0e) || (op == 5'h14);
    wire [4:0] old_loop = arg[0] ? loop1 : loop0;
    wire [10:0] next_end = ({5'b0, next_row} * RECORD_BYTES) + RECORD_BYTES;
    wire [10:0] branch_end = ({5'b0, branch_row} * RECORD_BYTES) + RECORD_BYTES;
    wire [10:0] alt_end = ({7'b0, alt_row} * RECORD_BYTES) + RECORD_BYTES;
    wire length_bad = (committed_bytes == 0) || (committed_bytes > STORE_LIMIT)
        || ((committed_bytes & (RECORD_BYTES - 1)) != 0);
    wire target_used = (op == 5'h0d) || (op == 5'h0e);

    assign next_row_wire = next_row;
    assign branch_row = C_SCALAR ? {2'b0, alt_row}
        : ((op == 5'h0d) ? arg[6:1] : arg[11:6]);
    assign static_bounds = length_bad || (next_end > {2'b0, committed_bytes})
        || (C_SCALAR && (alt_end > {2'b0, committed_bytes}))
        || (!C_SCALAR && target_used && (branch_end > {2'b0, committed_bytes}));
    assign is_timer_bypass = (op >= 5'h0f) && (op <= 5'h13);
    assign is_wait = (op == 5'h14);
    assign is_end = (op == 5'h15);
    assign is_programmed_fault = (op == 5'h16);
    assign condition_value = old_condition ^ (condition_op && arg[5]);
    assign successor_row = (op == 5'h0e) ? (condition_value ? branch_row : next_row)
        : ((op == 5'h0d) ? ((old_loop > 1) ? branch_row : next_row) : next_row);

    always @* begin
        allowed_arg = 20'h00000;
        extra_illegal = 1'b0;
        case (op)
            5'h00, 5'h04, 5'h08, 5'h09: allowed_arg = 20'h00000;
            5'h01: allowed_arg = 20'h0001f;
            5'h02: begin
                allowed_arg = 20'h0003f;
                extra_illegal = (arg[4:3] == 2'd3) || (arg[5] && (arg[4:3] == 0));
            end
            5'h03: allowed_arg = 20'h001ff;
            5'h05, 5'h06: allowed_arg = 20'h00001;
            5'h07: begin
                allowed_arg = 20'h0001f;
                extra_illegal = arg[3:0] > 4'd10;
            end
            5'h0a: begin
                allowed_arg = 20'h0003f;
                extra_illegal = arg[4:0] > 5'd18;
            end
            5'h0b: begin
                allowed_arg = 20'h0ffff;
                extra_illegal = |(arg[15:8] & ~arg[7:0]);
            end
            5'h0c: begin
                allowed_arg = 20'h0003f;
                extra_illegal = (arg[5:1] == 0) || (arg[5:1] > 5'd16);
            end
            5'h0d: allowed_arg = C_SCALAR ? 20'h00001 : 20'h0007f;
            5'h0e: begin
                allowed_arg = C_SCALAR ? 20'h0003f : 20'h00fff;
                extra_illegal = arg[4:0] > 5'd18;
            end
            5'h0f, 5'h10, 5'h11, 5'h12: allowed_arg = 20'hfffff;
            5'h13: begin
                allowed_arg = 20'h00003;
                extra_illegal = arg[1:0] == 0;
            end
            5'h14: begin
                allowed_arg = 20'hfffff;
                extra_illegal = arg[4:0] > 5'd18;
            end
            5'h15: begin
                allowed_arg = 20'h000ff;
                extra_illegal = (arg[7:0] != 8'h01) && (arg[7:0] != 8'h02);
            end
            5'h16: begin
                allowed_arg = 20'h000ff;
                extra_illegal = (arg[7:0] != 8'h11) && (arg[7:0] != 8'h12)
                    && (arg[7:0] != 8'h13) && (arg[7:0] != 8'h18);
            end
            5'h17: begin
                allowed_arg = 20'hfffff;
                extra_illegal = arg[19:1] == 0;
            end
            5'h18, 5'h19, 5'h1a, 5'h1b, 5'h1c, 5'h1d, 5'h1e, 5'h1f:
                extra_illegal = 1'b1;
            default: extra_illegal = 1'bx;
        endcase
        static_illegal = (|(arg & ~allowed_arg)) || extra_illegal
            || ((is_timer_bypass || (op == 5'h17)) && stamp)
            || (C_SCALAR && (|next_row[5:4]));
    end

    always @* begin
        case (arg[4:0])
            5'd0: old_condition = 1'b0;
            5'd1: old_condition = 1'b1;
            5'd2: old_condition = observed[0];
            5'd3: old_condition = observed[1];
            5'd4: old_condition = observed[2];
            5'd5: old_condition = observed[3];
            5'd6: old_condition = observed[4];
            5'd7: old_condition = observed[5];
            5'd8: old_condition = observed[6];
            5'd9: old_condition = observed[7];
            5'd10: old_condition = flag;
            5'd11: old_condition = loop0 == 0;
            5'd12: old_condition = loop1 == 0;
            5'd13: old_condition = tx_consumed < tx_initialized;
            5'd14: old_condition = rx_count < rx_capacity;
            5'd15: old_condition = (observed & cmask) == cvalue;
            5'd16: old_condition = loop0 == 1;
            5'd17: old_condition = loop1 == 1;
            5'd18: old_condition = (nbit == 8) && collect;
            default: old_condition = 1'bx;
        endcase
    end

    always @* begin
        case (arg[3:0])
            4'd0: shift_bit = 1'b0;
            4'd1: shift_bit = 1'b1;
            4'd2: shift_bit = observed[0];
            4'd3: shift_bit = observed[1];
            4'd4: shift_bit = observed[2];
            4'd5: shift_bit = observed[3];
            4'd6: shift_bit = observed[4];
            4'd7: shift_bit = observed[5];
            4'd8: shift_bit = observed[6];
            4'd9: shift_bit = observed[7];
            4'd10: shift_bit = flag;
            default: shift_bit = 1'bx;
        endcase
    end
endmodule
