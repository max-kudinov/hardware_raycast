`include "fixedpoint.svh"

`default_nettype none

module dda
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
(
    input  var logic                   clk,
    input  var logic                   rst,

    input  var logic                   start_i,

    input  var logic [W_INT-1:0]       init_map_x_i,
    input  var logic [W_INT-1:0]       init_map_y_i,
    output var logic [W_INT-1:0]       map_x_o,
    output var logic [W_INT-1:0]       map_y_o,
    input  var logic                   step_x_i,
    input  var logic                   step_y_i,
    input  var logic                   wall_hit_i,

    input  var logic [W_INT-1:-W_FRAC] init_side_dist_x_i,
    input  var logic [W_INT-1:-W_FRAC] init_side_dist_y_i,
    output var logic [W_INT-1:-W_FRAC] side_dist_x_o,
    output var logic [W_INT-1:-W_FRAC] side_dist_y_o,
    input  var logic [W_INT-1:-W_FRAC] delta_dist_x_i,
    input  var logic [W_INT-1:-W_FRAC] delta_dist_y_i,
    output var logic                   hit_side_o
);

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

typedef enum {
    ST_IDLE,
    ST_CALC_DDA
} state_t;

state_t state, next_state;

// ----------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------

always_comb begin
    next_state = state;

    case (state)
        ST_IDLE:     if (start_i)    next_state = ST_CALC_DDA;
        ST_CALC_DDA: if (wall_hit_i) next_state = ST_IDLE;
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

always_ff @(posedge clk) begin
    if (state == ST_IDLE && start_i) begin
        side_dist_x_o <= init_side_dist_x_i;
        side_dist_y_o <= init_side_dist_y_i;

        map_x_o       <= init_map_x_i;
        map_y_o       <= init_map_y_i;
    end

    if (state == ST_CALC_DDA) begin
        if (side_dist_x_o < side_dist_y_o) begin
            side_dist_x_o <= side_dist_x_o + delta_dist_x_i;
            map_x_o       <= step_x_i ? (map_x_o + 1'b1) : (map_x_o - 1'b1);
            hit_side_o    <= '0;
        end else begin
            side_dist_y_o <= side_dist_y_o + delta_dist_y_i;
            map_y_o       <= step_y_i ? (map_y_o + 1'b1) : (map_y_o - 1'b1);
            hit_side_o    <= '1;
        end
    end
end

endmodule

`default_nettype wire
