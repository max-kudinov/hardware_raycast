`include "fixp_pkg.svh"
`include "dvi_pkg.svh"

`default_nettype none

module raycast_top
    // import fixp_pkg::W_INT;
#(
    parameter real         MOVEMENT_SPEED      = 0.8,
    parameter real         ROTATION_SPEED      = 0.4,
    parameter int unsigned        W_X_POS      = 10,
    parameter int unsigned        W_Y_POS      = 9,
    parameter logic [W_X_POS-1:0] FRAME_WIDTH  = 640,
    parameter logic [W_Y_POS-1:0] FRAME_HEIGHT = 480
) (
    input  var logic       serial_clk,
    input  var logic       px_clk,
    input  var logic       rst,

    // Key input
    input  var logic       key_forward_i,
    input  var logic       key_backward_i,
    input  var logic       key_left_i,
    input  var logic       key_right_i,
    input  var logic       key_rotate_left_i,
    input  var logic       key_rotate_right_i,

    output var logic [2:0] tmds_data_p,
    output var logic [2:0] tmds_data_n,
    output var logic       tmds_clk_p,
    output var logic       tmds_clk_n
);

import dvi_pkg::X_POS_W;
import dvi_pkg::Y_POS_W;
import dvi_pkg::COLOR_W;

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned MAP_SIDE = 20;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

// Big-endian to match Python list order
// verilator lint_off ASCRANGE
logic [0:MAP_SIDE-1] map [MAP_SIDE];
// verilator lint_on ASCRANGE

// verilator lint_off UNUSEDSIGNAL
logic [POS_W_INT-1:0]    map_x;
logic [POS_W_INT-1:0]    map_y;
// verilator lint_on UNUSEDSIGNAL
logic [POS_W_INT-1:0]    render_map_x;
logic [POS_W_INT-1:0]    render_map_y;
logic [POS_W_INT-1:0]    controls_map_x;
logic [POS_W_INT-1:0]    controls_map_y;

logic                lookup_render;
logic                wall_hit;

logic [COLOR_W-1:0]  red;
logic [COLOR_W-1:0]  green;
logic [COLOR_W-1:0]  blue;

logic [X_POS_W-1:0]  px_x;
logic [Y_POS_W-1:0]  px_y;
logic                in_range;

logic                frame_start;
logic                frame_done;

pos_fixp_t               pos_x;
pos_fixp_t               pos_y;
ray_fixp_t              dir_x;
ray_fixp_t              dir_y;
ray_fixp_t              plane_x;
ray_fixp_t              plane_y;

// ----------------------------------------------------------------------------
// Map ROM init
// ----------------------------------------------------------------------------

initial
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

// ----------------------------------------------------------------------------
// Manage access to map lookup memory
// ----------------------------------------------------------------------------

assign frame_start = (px_x == '0) && (px_y == '0) && in_range;
assign frame_done  = (px_x == FRAME_WIDTH - 1) && (px_y == FRAME_HEIGHT - 1);

always_ff @(posedge px_clk)
    if (rst)
        lookup_render <= '1;
    else if (frame_start)
        lookup_render <= '1;
    else if (frame_done)
        lookup_render <= '0;

assign map_x = lookup_render ? render_map_x : controls_map_x;
assign map_y = lookup_render ? render_map_y : controls_map_y;

// verilator lint_off widthtrunc
assign wall_hit = map[map_y][map_x];
// verilator lint_on WIDTHTRUNC

// ----------------------------------------------------------------------------
// Main raycast components
// ----------------------------------------------------------------------------

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

render #(
    .FRAME_WIDTH  (FRAME_WIDTH ),
    .FRAME_HEIGHT (FRAME_HEIGHT),
    .W_X_POS      (W_X_POS     ),
    .W_Y_POS      (W_Y_POS     )
) render (
    .clk            (px_clk      ),
    .rst            (rst         ),

    .px_x_i         (px_x        ),
    .px_y_i         (px_y        ),
    .in_range_i     (in_range    ),
    .new_frame_i    (frame_start ),
    .red_o          (red         ),
    .green_o        (green       ),
    .blue_o         (blue        ),

    .lookup_map_x_o (render_map_x),
    .lookup_map_y_o (render_map_y),
    .wall_hit_i     (wall_hit    ),

    .pos_x_i        (pos_x       ),
    .pos_y_i        (pos_y       ),

    .dir_x_i        (dir_x       ),
    .dir_y_i        (dir_y       ),

    .plane_x_i      (plane_x     ),
    .plane_y_i      (plane_y     )
);

controls #(
    .MOVEMENT_SPEED (MOVEMENT_SPEED),
    .ROTATION_SPEED (ROTATION_SPEED)
) controls (
    .clk                (px_clk            ),
    .rst                (rst               ),

    .key_forward_i      (key_forward_i     ),
    .key_backward_i     (key_backward_i    ),
    .key_left_i         (key_left_i        ),
    .key_right_i        (key_right_i       ),
    .key_rotate_left_i  (key_rotate_left_i ),
    .key_rotate_right_i (key_rotate_right_i),

    .update_start_i     (frame_done        ),

    .lookup_map_x_o     (controls_map_x    ),
    .lookup_map_y_o     (controls_map_y    ),
    .wall_hit_i         (wall_hit          ),

    .pos_x_o            (pos_x             ),
    .pos_y_o            (pos_y             ),

    .dir_x_o            (dir_x             ),
    .dir_y_o            (dir_y             ),

    .plane_x_o          (plane_x           ),
    .plane_y_o          (plane_y           )
);

endmodule

`resetall
