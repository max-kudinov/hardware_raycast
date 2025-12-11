`include "fixedpoint.svh"

module raycast_top
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter W_X_POS     = 10,
    parameter W_HEIGHT    = 9,
    parameter FRAME_WIDTH = 640
) (
    // input  var logic                          clk,
    input  var logic                          rst,

    input  var logic                          start_i,
    // Horizontal position of input pixel on the screen
    input  var logic        [W_X_POS-1:0]     px_x_i,

    // Camera coordinates
    input  var logic        [W_INT-1:-W_FRAC] pos_x_i,
    input  var logic        [W_INT-1:-W_FRAC] pos_y_i,
    // Camera direction
    input  var logic signed [W_INT-1:-W_FRAC] dir_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] dir_y_i,
    // Camera plane
    input  var logic signed [W_INT-1:-W_FRAC] plane_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] plane_y_i,

    output var logic                          done_o,
    output var logic        [W_HEIGHT-1:0]    height_o,
    output var logic                          ray_hit_side_o
);

bit clk;
always #1 clk = !clk;

localparam MAP_SIDE = 20;

// verilator lint_off UNUSEDSIGNAL
logic [W_INT-1:0] map_x;
logic [W_INT-1:0] map_y;
// verilator lint_on UNUSEDSIGNAL

// verilator lint_off ascrange
logic [0:MAP_SIDE-1] map [MAP_SIDE];
// verilator lint_on ascrange
logic wall_hit;

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
assign wall_hit = map[map_x][map_y];
// verilator lint_on WIDTHTRUNC


line_height_calc #(
    .W_X_POS     (W_X_POS    ),
    .W_HEIGHT    (W_HEIGHT   ),
    .FRAME_WIDTH (FRAME_WIDTH)
) line_height_calc (
    .clk            (clk           ),
    .rst            (rst           ),

    .start_i        (start_i       ),
    .px_x_i         (px_x_i        ),

    .pos_x_i        (pos_x_i       ),
    .pos_y_i        (pos_y_i       ),

    .dir_x_i        (dir_x_i       ),
    .dir_y_i        (dir_y_i       ),

    .plane_x_i      (plane_x_i     ),
    .plane_y_i      (plane_y_i     ),

    .lookup_map_x_o (map_x         ),
    .lookup_map_y_o (map_y         ),
    .wall_hit_i     (wall_hit      ),

    .done_o         (done_o        ),
    .height_o       (height_o      ),
    .ray_hit_side_o (ray_hit_side_o)
);

endmodule
