`default_nettype none

module ray_height_calc #(
    parameter W_INT       = 8,
    parameter W_FRAC      = 8,
    parameter W_X_POS     = 8,
    parameter W_HEIGHT    = 8,
    parameter FRAME_WIDTH = 640
) (
    input  var logic                          clk,
    input  var logic                          rst,

    input  var logic                          start_i,
    input  var logic        [W_X_POS-1:0]     x_pos_i,

    input  var logic signed [W_INT-1:-W_FRAC] dir_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] dir_y_i,
    input  var logic signed [W_INT-1:-W_FRAC] plane_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] plane_y_i,

    output var logic                          done_o,
    output var logic        [W_HEIGHT-1:0]    height_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam RAY_STEP = int'(2.0 / FRAME_WIDTH * (2**W_FRAC));

endmodule
