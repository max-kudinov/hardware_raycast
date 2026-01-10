`include "fixedpoint.svh"

`default_nettype none

module rotation
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter real ROTATION_SPEED = 0.4
)(
    input  var logic                          clk,
    input  var logic                          rst,

    input  var logic                          key_rotate_left_i,
    input  var logic                          key_rotate_right_i,

    input  var logic                          update_start_i,

    // Camera direction
    output var logic signed [W_INT-1:-W_FRAC] dir_x_o,
    output var logic signed [W_INT-1:-W_FRAC] dir_y_o,
    // Camera plane
    output var logic signed [W_INT-1:-W_FRAC] plane_x_o,
    output var logic signed [W_INT-1:-W_FRAC] plane_y_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam real START_DIR_X   =  0.94;
localparam real START_DIR_Y   = -0.33;
localparam real START_PLANE_X = -0.22;
localparam real START_PLANE_Y = -0.62;

always_ff @(posedge clk)
    if (rst) begin
        dir_x_o   <= fixedpoint::real_to_sfixp(START_DIR_X);
        dir_y_o   <= fixedpoint::real_to_sfixp(START_DIR_Y);

        plane_x_o <= fixedpoint::real_to_sfixp(START_PLANE_X);
        plane_y_o <= fixedpoint::real_to_sfixp(START_PLANE_Y);
    end

endmodule

`resetall
