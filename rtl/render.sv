`include "fixedpoint.svh"

`default_nettype none

module render
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter FRAME_WIDTH = 640,
    parameter W_HEIGHT    = 8,
    parameter W_X_POS     = 8,
    parameter W_Y_POS     = 8
) (
    input  var logic                          clk,
    input  var logic                          rst,

    input  var logic        [W_X_POS-1:0]     px_x_i,
    input  var logic        [W_Y_POS-1:0]     px_y_i,
    input  var logic                          in_range_i,

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

localparam BUF_PIXELS = FRAME_WIDTH;
localparam W_BUF_DATA = W_HEIGHT + 1;
localparam W_BUF_ADDR = $clog2(BUF_PIXELS);

logic [W_BUF_DATA-1:0] frame_buffer [BUF_PIXELS];
logic                  buf_write;
logic                  buf_read;
logic [W_BUF_ADDR-1:0] buf_addr;
logic [W_BUF_DATA-1:0] buf_data_in;
logic [W_BUF_DATA-1:0] buf_data_out;

// Single-port block RAM
always_ff @(posedge clk) begin
    if (buf_write) begin
        frame_buffer[buf_addr] <= buf_data_in;
    end else if (buf_read) begin
        buf_data_out <= frame_buffer[buf_addr];
    end
end

endmodule

`default_nettype wire
