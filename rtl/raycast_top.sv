`include "fixp_pkg.svh"
`include "tex_pkg.svh"
`include "dvi_pkg.svh"

`default_nettype none

module raycast_top #(
    parameter real MOVEMENT_SPEED = 0.8,
    parameter real ROTATION_SPEED = 0.4
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

import fixp_pkg::*;
import tex_pkg::W_NUM_TEX;
import dvi_pkg::FRAME_WIDTH;
import dvi_pkg::FRAME_HEIGHT;
import dvi_pkg::W_H_RES;
import dvi_pkg::W_V_RES;
import dvi_pkg::W_COLOR;

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned MAP_SIDE   = 32;
localparam int unsigned MAP_SIZE   = MAP_SIDE * MAP_SIDE;
localparam int unsigned W_MAP_ADDR = $clog2(MAP_SIZE);

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef logic [W_MAP_ADDR-1:0] map_addr_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic [W_NUM_TEX-1:0] map [MAP_SIZE];
map_addr_t            map_addr;
logic [POS_W_INT-1:0] map_x;
logic [POS_W_INT-1:0] map_y;
logic [POS_W_INT-1:0] render_map_x;
logic [POS_W_INT-1:0] render_map_y;
logic [POS_W_INT-1:0] controls_map_x;
logic [POS_W_INT-1:0] controls_map_y;
logic [W_NUM_TEX-1:0] texture;

logic                 lookup_render;
logic                 wall_hit;

logic [W_COLOR-1:0]   red;
logic [W_COLOR-1:0]   green;
logic [W_COLOR-1:0]   blue;

logic [W_H_RES-1:0]   px_x;
logic [W_V_RES-1:0]   px_y;
logic                 in_range;

logic                 frame_start;
logic                 frame_done;

pos_fixp_t            pos_x;
pos_fixp_t            pos_y;
ray_fixp_t            dir_x;
ray_fixp_t            dir_y;
ray_fixp_t            plane_x;
ray_fixp_t            plane_y;

// ----------------------------------------------------------------------------
// ROM initialization
// ----------------------------------------------------------------------------

// Cocotb runs simulation from sim_build directory, so it has different
// relative path to the memfiles
`ifdef SIMULATION
    initial $readmemh("../memfiles/map.mem", map);
`else
    initial $readmemh("memfiles/map.mem", map);
`endif

// ----------------------------------------------------------------------------
// Manage access to map lookup memory
// ----------------------------------------------------------------------------

assign map_addr = (map_addr_t'(map_y) * map_addr_t'(MAP_SIDE)) + map_addr_t'(map_x);

always_ff @(posedge px_clk)
    texture <= map[map_addr];

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

assign wall_hit = texture != '0;

// ----------------------------------------------------------------------------
// Main raycast components
// ----------------------------------------------------------------------------

render render (
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
    .texture_i      (texture     ),

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

dvi_top dvi_top (
    .serial_clk  (serial_clk ),
    .pixel_clk   (px_clk     ),
    .rst         (rst        ),

    .red_i       (red        ),
    .green_i     (green      ),
    .blue_i      (blue       ),

    .x_o         (px_x       ),
    .y_o         (px_y       ),
    .in_range_o  (in_range   ),

    .tmds_data_p (tmds_data_p),
    .tmds_data_n (tmds_data_n),
    .tmds_clk_p  (tmds_clk_p ),
    .tmds_clk_n  (tmds_clk_n )
);

endmodule

`resetall
