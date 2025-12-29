`include "fixedpoint.svh"
`include "dvi_pkg.svh"

`default_nettype none

module raycast_top
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter int unsigned        W_X_POS      = 10,
    parameter int unsigned        W_Y_POS      = 9,
    parameter logic [W_X_POS-1:0] FRAME_WIDTH  = 640,
    parameter logic [W_Y_POS-1:0] FRAME_HEIGHT = 480
) (
    // input  var logic                          clk,
    input  var logic                          rst,

    // Camera coordinates
    input  var logic        [W_INT-1:-W_FRAC] pos_x_i,
    input  var logic        [W_INT-1:-W_FRAC] pos_y_i,
    // Camera direction
    input  var logic signed [W_INT-1:-W_FRAC] dir_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] dir_y_i,
    // Camera plane
    input  var logic signed [W_INT-1:-W_FRAC] plane_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] plane_y_i,

    output var logic        [2:0]             tmds_data_p,
    output var logic        [2:0]             tmds_data_n,
    output var logic                          tmds_clk_p,
    output var logic                          tmds_clk_n
);

import dvi_pkg::X_POS_W;
import dvi_pkg::Y_POS_W;


bit board_clk;
bit px_clk;
bit serial_clk;

always #5  board_clk  = !board_clk;
always #1  serial_clk = !serial_clk;
always #10 px_clk     = !px_clk;

localparam MAP_SIDE = 20;

// verilator lint_off UNUSEDSIGNAL
logic [W_INT-1:0] map_x;
logic [W_INT-1:0] map_y;
// verilator lint_on UNUSEDSIGNAL

// Big-endian to match Python list order
// verilator lint_off ASCRANGE
logic [0:MAP_SIDE-1] map [MAP_SIDE];
// verilator lint_on ASCRANGE
logic wall_hit;

logic [23:0] color;
logic [7:0] red;
logic [7:0] green;
logic [7:0] blue;

logic [X_POS_W-1:0] px_x;
logic [Y_POS_W-1:0] px_y;
logic in_range;

initial begin
    map = '{
        20'b11111111111111111111,
        20'b10000000000100100001,
        20'b10000000000100100001,
        20'b10011111000100100001,
        20'b10010001000100100001,
        20'b10010001000100100001,
        20'b10010001000100100001,
        20'b10011011000000000001,
        20'b10000000000000000001,
        20'b10000000000010000001,
        20'b10000000010000001001,
        20'b10000000000001000001,
        20'b10000000001000000001,
        20'b11111111100000000001,
        20'b10000000100001110001,
        20'b10000000100001010001,
        20'b10000000000001110001,
        20'b10000000000000000001,
        20'b10000000100000000001,
        20'b11111111111111111111
    };
end


// verilator lint_off WIDTHTRUNC
assign wall_hit = map[map_y][map_x];
// verilator lint_on WIDTHTRUNC

render #(
    .FRAME_WIDTH  (FRAME_WIDTH ),
    .FRAME_HEIGHT (FRAME_HEIGHT),
    .W_X_POS      (W_X_POS     ),
    .W_Y_POS      (W_Y_POS     )
) render (
    .clk            (px_clk   ),
    .rst            (rst      ),
    .px_x_i         (px_x     ),
    .px_y_i         (px_y     ),
    .in_range_i     (in_range ),
    .pos_x_i        (pos_x_i  ),
    .pos_y_i        (pos_y_i  ),
    .dir_x_i        (dir_x_i  ),
    .dir_y_i        (dir_y_i  ),
    .plane_x_i      (plane_x_i),
    .plane_y_i      (plane_y_i),
    .lookup_map_x_o (map_x    ),
    .lookup_map_y_o (map_y    ),
    .wall_hit_i     (wall_hit ),
    .color_o        (color    )
);

assign { red, green, blue } = color;

dvi_top dvi_top (
    .serial_clk_i (serial_clk ),
    .pixel_clk_i  (px_clk     ),
    .rst_i        (rst        ),
    .red_i        (red        ),
    .green_i      (green      ),
    .blue_i       (blue       ),
    .x_o          (px_x       ),
    .y_o          (px_y       ),
    .in_range_o   (in_range   ),
    .tmds_data_p  (tmds_data_p),
    .tmds_data_n  (tmds_data_n),
    .tmds_clk_p   (tmds_clk_p ),
    .tmds_clk_n   (tmds_clk_n )
);

endmodule

`resetall
