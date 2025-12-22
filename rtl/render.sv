`include "fixedpoint.svh"

`default_nettype none

module render
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter W_X_POS = 8,
    parameter W_Y_POS = 8
) (
    input  var logic                          clk,
    input  var logic                          rst,

    input  var logic        [W_X_POS-1:0]     px_x_i,
    input  var logic        [W_Y_POS-1:0]     px_y_i,

    // Camera coordinates
    input  var logic        [W_INT-1:-W_FRAC] pos_x_i,
    input  var logic        [W_INT-1:-W_FRAC] pos_y_i,
    // Camera direction
    input  var logic signed [W_INT-1:-W_FRAC] dir_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] dir_y_i,
    // Camera plane
    input  var logic signed [W_INT-1:-W_FRAC] plane_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] plane_y_i,

    // Map coordinates to check for a wall
    output var logic        [W_INT-1:0]       lookup_map_x_o,
    output var logic        [W_INT-1:0]       lookup_map_y_o,
    input  var logic                          wall_hit_i,

    output var logic        [23:0]            color_o
);

endmodule

`default_nettype wire
