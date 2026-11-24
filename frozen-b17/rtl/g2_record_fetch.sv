// Isolated G2.01 executable model; not the G1 host/reset/safety lifecycle.
// Contract: record-fetch-contract.md, g2-execution-2026-10-30.
// All control requires a preceding synchronous clear_control edge.
`timescale 1ns/1ps

module g2_record_fetch #(
    parameter integer STORE_BYTES = 128,
    parameter integer RECORD_BYTES = 8
) (
    input  logic clk,
    input  logic clear_control,
    input  logic execution_active,
    input  logic begin_load,
    input  logic write_enable,
    input  logic [7:0] write_address,
    input  logic [7:0] write_data,
    input  logic seal,
    input  logic fetch_request,
    input  logic [7:0] fetch_address,
    input  logic consume_record,
    input  logic cancel,
    output logic request_ready,
    output logic reject_now,
    output logic fetch_accepted,
    output logic consume_accepted,
    output logic error,
    output logic record_valid,
    output logic [8*RECORD_BYTES-1:0] record_data,
    output logic executable_valid,
    output logic loading,
    output logic [8:0] loaded_count,
    output logic busy,
    output logic [$clog2(RECORD_BYTES+1)-1:0] issued_count,
    output logic [$clog2(RECORD_BYTES+1)-1:0] assembled_count,
    output logic response_valid,
    output logic [$clog2(RECORD_BYTES)-1:0] response_lane,
    output logic read_issued,
    output logic [7:0] read_address,
    output logic assemble_event,
    output logic [$clog2(RECORD_BYTES)-1:0] assemble_lane
);
    localparam integer COUNT_WIDTH = $clog2(RECORD_BYTES+1);
    localparam integer LANE_WIDTH = $clog2(RECORD_BYTES);
    localparam logic [8:0] STORE_CAPACITY = STORE_BYTES;
    localparam logic [8:0] RECORD_EXTENT = RECORD_BYTES;
    localparam logic [COUNT_WIDTH-1:0] RECORD_COUNT = RECORD_BYTES;

    // One byte-wide port. Neither the array nor either data register is reset.
    logic [7:0] byte_store [0:STORE_BYTES-1];
    logic [7:0] base_address;
    logic [7:0] response_data;

    wire [2:0] command_count = {2'b0, begin_load}
                             + {2'b0, write_enable}
                             + {2'b0, seal}
                             + {2'b0, fetch_request}
                             + {2'b0, consume_record};
    wire [8:0] fetch_end = {1'b0, fetch_address} + RECORD_EXTENT;
    wire fetch_entry_valid = (fetch_address[LANE_WIDTH-1:0] == '0)
                            && (fetch_end <= loaded_count);
    wire [8:0] issue_address = {1'b0, base_address}
                            + {{(9-COUNT_WIDTH){1'b0}}, issued_count};
    wire write_legal = !execution_active && loading
                     && (loaded_count < STORE_CAPACITY)
                     && ({1'b0, write_address} == loaded_count);
    wire seal_legal = !execution_active && loading
                    && (loaded_count != 9'd0)
                    && (loaded_count[LANE_WIDTH-1:0] == '0);

    assign request_ready = executable_valid && execution_active && !loading
                         && !busy && !response_valid && !record_valid
                         && fetch_entry_valid && !clear_control && !cancel
                         && !begin_load && !write_enable && !seal
                         && !consume_record;

    // A combinational pre-edge veto is needed by any connected consumer;
    // the registered error report cannot undo consumption of old valid state.
    assign reject_now = !clear_control && !cancel
                      && ((command_count > 3'd1)
                          || (begin_load && execution_active)
                          || (write_enable && !write_legal)
                          || (seal && !seal_legal)
                          || (fetch_request && !request_ready)
                          || (consume_record
                              && !(execution_active && record_valid)));

    initial begin
        if ((STORE_BYTES != 128) && (STORE_BYTES != 256))
            $fatal(1, "STORE_BYTES must be 128 or 256");
        if ((RECORD_BYTES != 4) && (RECORD_BYTES != 8)
            && (RECORD_BYTES != 16))
            $fatal(1, "RECORD_BYTES must be 4, 8 or 16");
    end

    always_ff @(posedge clk) begin
        fetch_accepted <= 1'b0;
        consume_accepted <= 1'b0;
        read_issued <= 1'b0;
        assemble_event <= 1'b0;
        error <= 1'b0;

        if (clear_control) begin
            loading <= 1'b0;
            loaded_count <= 9'd0;
            executable_valid <= 1'b0;
            busy <= 1'b0;
            record_valid <= 1'b0;
            response_valid <= 1'b0;
            issued_count <= '0;
            assembled_count <= '0;
            base_address <= 8'd0;
            response_lane <= '0;
            read_address <= 8'd0;
            assemble_lane <= '0;
        end else if (cancel || reject_now) begin
            // Explicit cancel suppresses every command without an error.
            // Reject cancels runtime validity and vetoes all ordinary writes.
            error <= reject_now;
            busy <= 1'b0;
            record_valid <= 1'b0;
            response_valid <= 1'b0;
            issued_count <= '0;
            assembled_count <= '0;
        end else if (!execution_active) begin
            busy <= 1'b0;
            record_valid <= 1'b0;
            response_valid <= 1'b0;
            issued_count <= '0;
            assembled_count <= '0;

            if (begin_load) begin
                loading <= 1'b1;
                loaded_count <= 9'd0;
                executable_valid <= 1'b0;
            end else if (write_enable) begin
                byte_store[write_address] <= write_data;
                loaded_count <= loaded_count + 9'd1;
            end else if (seal) begin
                loading <= 1'b0;
                executable_valid <= 1'b1;
            end
        end else begin
            response_valid <= 1'b0;

            if (fetch_request) begin
                base_address <= fetch_address;
                busy <= 1'b1;
                issued_count <= '0;
                assembled_count <= '0;
                fetch_accepted <= 1'b1;
            end else if (consume_record) begin
                record_valid <= 1'b0;
                consume_accepted <= 1'b1;
            end else if (busy) begin
                if (issued_count < RECORD_COUNT) begin
                    // Read data, tag and valid commit at this request edge.
                    response_data <= byte_store[issue_address[7:0]];
                    response_lane <= issued_count[LANE_WIDTH-1:0];
                    response_valid <= 1'b1;
                    issued_count <= issued_count + 1'b1;
                    read_address <= issue_address[7:0];
                    read_issued <= 1'b1;
                end

                if (response_valid) begin
                    // Old response only: never bypass the synchronous stage.
                    record_data[8*response_lane +: 8] <= response_data;
                    assembled_count <= assembled_count + 1'b1;
                    assemble_lane <= response_lane;
                    assemble_event <= 1'b1;
                    if (assembled_count == RECORD_COUNT - 1'b1) begin
                        record_valid <= 1'b1;
                        busy <= 1'b0;
                    end
                end
            end
        end
    end
endmodule
