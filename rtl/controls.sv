`include "fixp_pkg.svh"

`default_nettype none

module controls
    import fixp_pkg::*;
#(
    parameter real MOVEMENT_SPEED = 0.8,
    parameter real ROTATION_SPEED = 0.4
) (
    input  var logic                 clk,
    input  var logic                 rst,

    // Key input
    input  var logic                 key_forward_i,
    input  var logic                 key_backward_i,
    input  var logic                 key_left_i,
    input  var logic                 key_right_i,
    input  var logic                 key_rotate_left_i,
    input  var logic                 key_rotate_right_i,

    input  var logic                 update_start_i,

    // Map coordinates to check for a wall
    output var logic [POS_W_INT-1:0] lookup_map_x_o,
    output var logic [POS_W_INT-1:0] lookup_map_y_o,
    input  var logic                 wall_hit_i,

    // Camera coordinates
    output var pos_fixp_t            pos_x_o,
    output var pos_fixp_t            pos_y_o,
    // Camera direction
    output var ray_fixp_t            dir_x_o,
    output var ray_fixp_t            dir_y_o,
    // Camera plane
    output var ray_fixp_t            plane_x_o,
    output var ray_fixp_t            plane_y_o
);

logic pos_done;

position #(
    .MOVEMENT_SPEED (MOVEMENT_SPEED)
) position (
    .clk            (clk           ),
    .rst            (rst           ),

    .key_forward_i  (key_forward_i ),
    .key_backward_i (key_backward_i),
    .key_left_i     (key_left_i    ),
    .key_right_i    (key_right_i   ),

    .update_start_i (update_start_i),
    .update_done_o  (pos_done      ),

    .lookup_map_x_o (lookup_map_x_o),
    .lookup_map_y_o (lookup_map_y_o),
    .wall_hit_i     (wall_hit_i    ),

    .pos_x_o        (pos_x_o       ),
    .pos_y_o        (pos_y_o       ),
    .dir_x_i        (dir_x_o       ),
    .dir_y_i        (dir_y_o       )
);

rotation #(
    .ROTATION_SPEED (ROTATION_SPEED)
) rotation (
    .clk                (clk               ),
    .rst                (rst               ),

    .key_rotate_left_i  (key_rotate_left_i ),
    .key_rotate_right_i (key_rotate_right_i),

    .update_start_i     (pos_done          ),

    .dir_x_o            (dir_x_o           ),
    .dir_y_o            (dir_y_o           ),
    .plane_x_o          (plane_x_o         ),
    .plane_y_o          (plane_y_o         )
);

endmodule

`resetall
