`include "fixp_pkg.svh"

`default_nettype none

module dda
    import fixp_pkg::*;
#(
    parameter ext_pos_fixp_t FIXP_MAX_DIST
) (
    input  var logic                 clk,
    input  var logic                 rst,

    input  var logic                 start_i,

    input  var logic [POS_W_INT-1:0] init_map_x_i,
    input  var logic [POS_W_INT-1:0] init_map_y_i,
    output var logic [POS_W_INT-1:0] map_x_o,
    output var logic [POS_W_INT-1:0] map_y_o,
    input  var logic                 step_x_i,
    input  var logic                 step_y_i,
    input  var logic                 wall_hit_i,

    input  var ext_pos_fixp_t        init_side_dist_x_i,
    input  var ext_pos_fixp_t        init_side_dist_y_i,
    output var ext_pos_fixp_t        side_dist_x_o,
    output var ext_pos_fixp_t        side_dist_y_o,
    input  var ext_pos_fixp_t        delta_dist_x_i,
    input  var ext_pos_fixp_t        delta_dist_y_i,
    output var logic                 hit_side_o,
    output var logic                 done_o
);

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef enum logic {
    ST_IDLE,
    ST_CALC_DDA
} state_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

state_t               state;
state_t               next_state;

ext_pos_fixp_t        side_dist_x_next;
ext_pos_fixp_t        side_dist_y_next;
ext_pos_fixp_t        side_dist_inc;

logic                 overflow;
logic                 hit_side_next;
logic                 wait_rom_read;
logic                 valid_hit;

logic [POS_W_INT-1:0] map_x_next;
logic [POS_W_INT-1:0] map_y_next;

// ----------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------

always_comb begin
    next_state = state;

    unique case (state)
        ST_IDLE:     if (start_i)   next_state = ST_CALC_DDA;
        ST_CALC_DDA: if (valid_hit) next_state = ST_IDLE;
    endcase
end

always_ff @(posedge clk)
    if (rst)
        state <= ST_IDLE;
    else
        state <= next_state;

// ----------------------------------------------------------------------------
// Digital Differential Analysis
// ----------------------------------------------------------------------------

always_comb begin
    side_dist_x_next = side_dist_x_o;
    side_dist_y_next = side_dist_y_o;

    map_x_next       = map_x_o;
    map_y_next       = map_y_o;

    valid_hit        = wall_hit_i && !wait_rom_read;
    hit_side_next    = hit_side_o;
    side_dist_inc    = '0;
    overflow         = '0;

    if (state == ST_IDLE && start_i) begin
        side_dist_x_next = init_side_dist_x_i;
        side_dist_y_next = init_side_dist_y_i;

        map_x_next       = init_map_x_i;
        map_y_next       = init_map_y_i;
    end

    if (state == ST_CALC_DDA && !wall_hit_i && !wait_rom_read) begin
        if (side_dist_x_o < side_dist_y_o) begin

            { overflow, side_dist_inc } = side_dist_x_o + delta_dist_x_i;

            // Check for overflow, if occurred, set max value
            if (overflow) begin
                side_dist_x_next = FIXP_MAX_DIST;
            end else begin
                side_dist_x_next = side_dist_inc;
                map_x_next       = step_x_i ? (map_x_o + 1'b1) : (map_x_o - 1'b1);
                hit_side_next    = '0;
            end

        end else begin

            { overflow, side_dist_inc } = side_dist_y_o + delta_dist_y_i;

            // Check for overflow, if occurred, set max value
            if (overflow) begin
                side_dist_y_next = FIXP_MAX_DIST;
            end else begin
                side_dist_y_next = side_dist_inc;
                map_y_next       = step_y_i ? (map_y_o + 1'b1) : (map_y_o - 1'b1);
                hit_side_next    = '1;
            end

        end
    end
end

always_ff @(posedge clk) begin
    side_dist_x_o <= side_dist_x_next;
    side_dist_y_o <= side_dist_y_next;

    map_x_o       <= map_x_next;
    map_y_o       <= map_y_next;

    hit_side_o    <= hit_side_next;
end

// 1 cycle delay after every map x/y update to wait for ROM read and check for
// hitting the wall
always_ff @(posedge clk)
    if (rst)
        wait_rom_read <= '1;
    else if (done_o)
        wait_rom_read <= '1;
    else if (state == ST_CALC_DDA)
        wait_rom_read <= !wait_rom_read;


always_ff @(posedge clk)
    if (rst)
        done_o <= '0;
    else
        done_o <= (state == ST_CALC_DDA) && valid_hit;

endmodule

`resetall
