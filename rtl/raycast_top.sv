`include "fixp_pkg.svh"
`include "tex_pkg.svh"
`include "dvi_pkg.svh"

`default_nettype none

module raycast_top
    import dvi_pkg::W_H_RES;
    import dvi_pkg::W_V_RES;
    import dvi_pkg::W_COLOR;
#(
    parameter real MOVEMENT_SPEED = 0.8,
    parameter real ROTATION_SPEED = 0.4
) (
    input  var logic               clk,
    input  var logic               rst,

    // Key input
    input  var logic               key_forward_i,
    input  var logic               key_backward_i,
    input  var logic               key_left_i,
    input  var logic               key_right_i,
    input  var logic               key_rotate_left_i,
    input  var logic               key_rotate_right_i,

    // Data for display output
    input  var logic [W_H_RES-1:0] px_x_i,
    input  var logic [W_V_RES-1:0] px_y_i,
    input  var logic               in_range_i,

    output var logic [W_COLOR-1:0] red_o,
    output var logic [W_COLOR-1:0] green_o,
    output var logic [W_COLOR-1:0] blue_o
);

import fixp_pkg::*;
import tex_pkg::W_NUM_TEX;
import dvi_pkg::FRAME_WIDTH;
import dvi_pkg::FRAME_HEIGHT;

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

always_ff @(posedge clk)
    texture <= map[map_addr];

assign frame_start = (px_x_i == '0) && (px_y_i == '0) && in_range_i;
assign frame_done  = (px_x_i == FRAME_WIDTH - 1) && (px_y_i == FRAME_HEIGHT - 1);

always_ff @(posedge clk)
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
    .clk            (clk         ),
    .rst            (rst         ),

    .px_x_i         (px_x_i      ),
    .px_y_i         (px_y_i      ),
    .in_range_i     (in_range_i  ),
    .new_frame_i    (frame_start ),
    .red_o          (red_o       ),
    .green_o        (green_o     ),
    .blue_o         (blue_o      ),

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
    .clk                (clk               ),
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
