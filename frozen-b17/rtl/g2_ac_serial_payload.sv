`timescale 1ns/1ps
// Experimental A/C data-lifetime slice. See README.md for the edge contract.
module g2_ac_serial_payload (
    input  logic clk, clear, run_start, cancel,
    input  logic running, action_accept, global_veto,
    input  logic tx_begin, tx_we,
    input  logic [3:0] tx_addr,
    input  logic [7:0] tx_data,
    input  logic [4:0] start_tx_count, start_rx_capacity,
    input  logic rx_re,
    input  logic [3:0] rx_addr,
    output logic rx_read_valid,
    output logic [7:0] rx_read_data,
    input  logic load_literal, tx_req, tx_load, drive, shift, rx_push, drop,
    input  logic dir, bit_in, load_collect,
    input  logic [7:0] literal_data,
    output logic [7:0] shift_data,
    output logic driven, shift_valid,
    output logic [3:0] nbit,
    output logic collect,
    output logic [4:0] initialized_tx_count, consumed,
    output logic [4:0] rx_capacity, rx_count,
    output logic [7:0] tx_response_data,
    output logic tx_response_valid, tx_pending,
    output logic [3:0] tx_pending_addr,
    output logic [7:0] rx_pending_data,
    output logic rx_pending_valid,
    output logic [3:0] rx_pending_addr,
    output logic proposed_driven,
    output logic raw_illegal, raw_tx_empty, raw_rx_full, raw_fault,
    output logic [7:0] raw_reason,
    output logic action_fire, tx_response_fire, rx_commit_fire
);
    logic [7:0] tx_mem [0:15];
    logic [7:0] rx_mem [0:15];
    logic [2:0] action_count;
    logic [1:0] host_count;
    logic any_action, stage_enable;

    always @* begin
        action_count = load_literal + tx_req + tx_load + drive + shift + rx_push + drop;
        host_count = tx_begin + tx_we + run_start;
        any_action = (action_count != 0);
        raw_illegal = 1'b0;
        raw_tx_empty = 1'b0;
        raw_rx_full = 1'b0;
        if (action_count > 1 && !(action_count == 2 && drive && shift))
            raw_illegal = 1'b1;
        if (host_count > 1 || (host_count != 0 && any_action))
            raw_illegal = 1'b1;
        if ((running && host_count != 0) || (!running && any_action))
            raw_illegal = 1'b1;
        if (tx_we && (initialized_tx_count >= 16 || {1'b0,tx_addr} != initialized_tx_count))
            raw_illegal = 1'b1;
        if (run_start && (start_tx_count > 16 || start_tx_count != initialized_tx_count ||
                          start_rx_capacity > 16))
            raw_illegal = 1'b1;
        if ((load_literal || tx_load) && (collect || rx_pending_valid))
            raw_illegal = 1'b1;
        if (tx_load && !tx_response_valid)
            raw_illegal = 1'b1;
        if (drive && !shift_valid)
            raw_illegal = 1'b1;
        if (shift && (!shift_valid || nbit >= 8))
            raw_illegal = 1'b1;
        if (drop && rx_pending_valid)
            raw_illegal = 1'b1;
        if (tx_req) begin
            if (tx_pending || tx_response_valid || initialized_tx_count > 16)
                raw_illegal = 1'b1;
            if (consumed >= initialized_tx_count)
                raw_tx_empty = 1'b1;
        end
        if (rx_push) begin
            if (!shift_valid || !collect || nbit != 8 || rx_pending_valid || rx_capacity > 16)
                raw_illegal = 1'b1;
            if (rx_count >= rx_capacity)
                raw_rx_full = 1'b1;
        end
        raw_fault = raw_illegal || raw_tx_empty || raw_rx_full;
        raw_reason = raw_illegal ? 8'h13 : raw_tx_empty ? 8'h16 : raw_rx_full ? 8'h17 : 8'd0;
        proposed_driven = drive ? (dir ? shift_data[0] : shift_data[7]) : driven;
        stage_enable = running && !clear && !cancel && !global_veto && !raw_fault;
        action_fire = stage_enable && action_accept && any_action;
        tx_response_fire = stage_enable && tx_pending;
        rx_commit_fire = stage_enable && rx_pending_valid;
        rx_read_valid = !running && rx_re && ({1'b0,rx_addr} < rx_count);
        rx_read_data = rx_read_valid ? rx_mem[rx_addr] : 8'bx;
    end

    always @(posedge clk) begin
        if (clear) begin
            initialized_tx_count <= 0;
            consumed <= 0;
            rx_capacity <= 0;
            rx_count <= 0;
            shift_data <= 0;
            driven <= 0;
            shift_valid <= 0;
            nbit <= 0;
            collect <= 0;
            tx_response_data <= 0;
            tx_response_valid <= 0;
            tx_pending <= 0;
            tx_pending_addr <= 0;
            rx_pending_data <= 0;
            rx_pending_valid <= 0;
            rx_pending_addr <= 0;
        end else if (cancel || raw_fault || (running && global_veto)) begin
            tx_pending <= 0;
            tx_response_valid <= 0;
            rx_pending_valid <= 0;
            shift_valid <= 0;
            nbit <= 0;
            collect <= 0;
        end else if (run_start) begin
            rx_capacity <= start_rx_capacity;
            consumed <= 0;
            rx_count <= 0;
            shift_data <= 0;
            driven <= 0;
            shift_valid <= 0;
            nbit <= 0;
            collect <= 0;
            tx_response_data <= 0;
            tx_response_valid <= 0;
            tx_pending <= 0;
            tx_pending_addr <= 0;
            rx_pending_data <= 0;
            rx_pending_valid <= 0;
            rx_pending_addr <= 0;
        end else if (!running) begin
            if (tx_begin)
                initialized_tx_count <= 0;
            if (tx_we) begin
                tx_mem[tx_addr] <= tx_data;
                initialized_tx_count <= initialized_tx_count + 1'b1;
            end
        end else begin
            if (tx_response_fire) begin
                tx_response_data <= tx_mem[tx_pending_addr];
                tx_response_valid <= 1;
                tx_pending <= 0;
            end
            if (rx_commit_fire) begin
                rx_mem[rx_pending_addr] <= rx_pending_data;
                rx_count <= rx_count + 1'b1;
                rx_pending_valid <= 0;
                collect <= 0;
            end
            if (action_fire) begin
                if (load_literal || tx_load) begin
                    shift_data <= tx_load ? tx_response_data : literal_data;
                    shift_valid <= 1;
                    nbit <= 0;
                    collect <= load_collect;
                    if (tx_load) begin
                        tx_response_valid <= 0;
                        consumed <= consumed + 1'b1;
                    end
                end
                if (tx_req) begin
                    tx_pending <= 1;
                    tx_pending_addr <= consumed[3:0];
                end
                if (drive)
                    driven <= dir ? shift_data[0] : shift_data[7];
                if (shift) begin
                    shift_data <= dir ? {bit_in,shift_data[7:1]} : {shift_data[6:0],bit_in};
                    nbit <= nbit + 1'b1;
                end
                if (rx_push) begin
                    rx_pending_data <= shift_data;
                    rx_pending_addr <= rx_count[3:0];
                    rx_pending_valid <= 1;
                end
                if (drop) begin
                    shift_valid <= 0;
                    nbit <= 0;
                    collect <= 0;
                end
            end
        end
    end
endmodule
