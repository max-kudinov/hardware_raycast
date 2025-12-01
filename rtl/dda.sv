`include "fixedpoint.svh"

`default_nettype none

module dda
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
(
    input  var logic clk,
    input  var logic rst,

    input  var logic start_i,

    input  var logic [W_INT-1:0] map_x_i,
    input  var logic [W_INT-1:0] map_y_i,

    input  var logic step_x_i,
    input  var logic step_y_i,

    input  var logic [W_INT-1:-W_FRAC] init_side_dist_x_i,
    input  var logic [W_INT-1:-W_FRAC] init_side_dist_y_i,

    input  var logic [W_INT-1:-W_FRAC] delta_dist_x_i,
    input  var logic [W_INT-1:-W_FRAC] delta_dist_y_i,

    output var logic [W_INT-1:-W_FRAC] side_dist_x_o,
    output var logic [W_INT-1:-W_FRAC] side_dist_y_o,

    output var logic done_o,
    output var logic hit_side_o
);

endmodule
`default_nettype wire
