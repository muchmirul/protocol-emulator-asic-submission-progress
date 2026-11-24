`timescale 1ns/1ps
module g2_ac_pins (
    input wire clk, clear, run_start, cancel, running, action_accept, global_veto,
    input wire [7:0] start_allow, start_od, start_value, start_oe,
    input wire gpio_write,
    input wire [2:0] gpio_pin,
    input wire gpio_value, gpio_oe,
    input wire profile_write,
    input wire [2:0] profile_pin,
    input wire [1:0] profile_mode,
    input wire profile_active,
    input wire [1:0] route_cmd,
    input wire serial_drive, proposed_driven, driven,
    output reg [7:0] gvalue, goe, drive_allow, open_drain,
    output reg [2:0] route_pin,
    output reg [1:0] route_mode,
    output reg route_active,
    output reg [7:0] requested_value, requested_oe,
    output reg [7:0] proposed_value, proposed_oe,
    output reg raw_illegal, raw_policy,
    output wire raw_fault,
    output wire [7:0] raw_reason,
    output wire action_fire
);
    reg [7:0] next_value, next_oe;
    reg [2:0] next_pin;
    reg [1:0] next_mode;
    reg next_active;
    wire any_action = gpio_write || profile_write || route_cmd != 0 || serial_drive;
    wire effective_driven = serial_drive ? proposed_driven : driven;
    assign raw_fault = raw_illegal || raw_policy;
    assign raw_reason = raw_illegal ? 8'h13 : raw_policy ? 8'h15 : 8'h00;
    assign action_fire = running && any_action && action_accept && !clear &&
                         !cancel && !global_veto && !raw_fault;

    always @* begin
        next_value = gvalue;
        next_oe = goe;
        next_pin = route_pin;
        next_mode = route_mode;
        next_active = route_active;
        raw_illegal = 0;
        raw_policy = 0;
        if ((!running && any_action) || (run_start && (running || any_action)))
            raw_illegal = 1;
        if (route_cmd == 3 || (profile_write && (gpio_write || route_cmd != 0 || serial_drive)))
            raw_illegal = 1;
        if (profile_write) begin
            next_pin = profile_pin;
            next_mode = profile_mode;
            next_active = profile_active;
            if (profile_mode == 3 || (profile_active && profile_mode == 0))
                raw_illegal = 1;
            if ((profile_mode == 1 && open_drain[profile_pin]) ||
                (profile_mode == 2 && !open_drain[profile_pin]))
                raw_policy = 1;
        end
        if (gpio_write) begin
            next_value[gpio_pin] = gpio_value;
            next_oe[gpio_pin] = gpio_oe;
            if (gpio_pin == route_pin)
                next_active = 0;
        end
        if (route_cmd == 1) begin
            next_active = 1;
            if (route_mode == 0 || route_mode == 3 ||
                (gpio_write && gpio_pin == route_pin))
                raw_illegal = 1;
        end else if (route_cmd == 2)
            next_active = 0;
        proposed_value = next_value;
        proposed_oe = next_oe;
        if (next_active) begin
            if (next_mode == 1)
                proposed_value[next_pin] = effective_driven;
            else if (next_mode == 2) begin
                proposed_value[next_pin] = 0;
                proposed_oe[next_pin] = next_oe[next_pin] && !effective_driven;
            end else
                raw_illegal = 1;
            if ((next_mode == 1 && open_drain[next_pin]) ||
                (next_mode == 2 && !open_drain[next_pin]))
                raw_policy = 1;
        end
        if (running && (((proposed_oe & ~drive_allow) != 0) ||
                        ((proposed_oe & proposed_value & open_drain) != 0)))
            raw_policy = 1;
        if (run_start && (((start_od | start_oe | start_value) & ~start_allow) != 0 ||
                          (start_value & start_od) != 0))
            raw_policy = 1;
        requested_value = running ? gvalue : 8'h00;
        requested_oe = running ? goe : 8'h00;
        if (running && route_active) begin
            if (route_mode == 1)
                requested_value[route_pin] = driven;
            else if (route_mode == 2) begin
                requested_value[route_pin] = 0;
                requested_oe[route_pin] = goe[route_pin] && !driven;
            end
        end
    end

    always @(posedge clk) begin
        if (clear) begin
            gvalue <= 0;
            goe <= 0;
            drive_allow <= 0;
            open_drain <= 0;
            route_pin <= 0;
            route_mode <= 0;
            route_active <= 0;
        end else if (!cancel && !global_veto && !raw_fault) begin
            if (run_start) begin
                gvalue <= start_value;
                goe <= start_oe;
                drive_allow <= start_allow;
                open_drain <= start_od;
                route_pin <= 0;
                route_mode <= 0;
                route_active <= 0;
            end else if (action_fire) begin
                gvalue <= next_value;
                goe <= next_oe;
                route_pin <= next_pin;
                route_mode <= next_mode;
                route_active <= next_active;
            end
        end
    end
endmodule
