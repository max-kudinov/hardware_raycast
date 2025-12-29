`include "fixedpoint.svh"

`default_nettype none

module render
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter int unsigned        W_X_POS      = 10,
    parameter int unsigned        W_Y_POS      = 9,
    parameter logic [W_X_POS-1:0] FRAME_WIDTH  = 640,
    parameter logic [W_Y_POS-1:0] FRAME_HEIGHT = 480
) (
    input  var logic                          clk,
    input  var logic                          rst,

    // DVI driver input
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

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned W_BUF_DATA = W_Y_POS; // Height without LSB + 1 bit for color
localparam int unsigned W_BUF_ADDR = $clog2(FRAME_WIDTH);

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic [W_BUF_DATA-1:0] frame_buffer [FRAME_WIDTH];
logic                  buf_write;
logic                  buf_read;
logic [W_BUF_ADDR-1:0] buf_addr;
logic [W_BUF_DATA-1:0] buf_data_in;
logic [W_BUF_DATA-1:0] buf_data_out;
logic [W_Y_POS-2:0]    buf_height;
logic                  buf_color;

// verilator lint_off UNUSEDSIGNAL
logic [W_Y_POS-1:0]   calc_height;
// verilator lint_on UNUSEDSIGNAL
logic                  calc_color;
logic                  calc_start;
// verilator lint_off UNUSEDSIGNAL
logic                  calc_done;
// verilator lint_on UNUSEDSIGNAL
logic [W_X_POS-1:0]    calc_col;

logic                  in_range_prev;
logic [W_Y_POS-1:0]    px_y;

// Single-port block RAM
always_ff @(posedge clk) begin
    if (buf_write) begin
        frame_buffer[buf_addr] <= buf_data_in;
    end else if (buf_read) begin
        buf_data_out <= frame_buffer[buf_addr];
    end
end

line_height_calc #(
    .W_X_POS      (W_X_POS     ),
    .W_Y_POS      (W_Y_POS     ),
    .FRAME_WIDTH  (FRAME_WIDTH ),
    .FRAME_HEIGHT (FRAME_HEIGHT)
) line_height_calc (
    .clk            (clk           ),
    .rst            (rst           ),

    .start_i        (calc_start    ),
    .px_x_i         (px_x_i        ),

    .pos_x_i        (pos_x_i       ),
    .pos_y_i        (pos_y_i       ),
    .dir_x_i        (dir_x_i       ),
    .dir_y_i        (dir_y_i       ),
    .plane_x_i      (plane_x_i     ),
    .plane_y_i      (plane_y_i     ),

    .lookup_map_x_o (lookup_map_x_o),
    .lookup_map_y_o (lookup_map_y_o),
    .wall_hit_i     (wall_hit_i    ),

    .done_o         (calc_done     ),
    .height_o       (calc_height   ),
    .ray_hit_side_o (calc_color    )
);


always_ff @(posedge clk)
    if (rst)
        in_range_prev <= '0;
    else
        in_range_prev <= in_range_i;

// Register input coordinate for next stage
always_ff @(posedge clk)
    px_y <= px_y_i;

always_ff @(posedge clk) begin
    if (rst) begin
        calc_col <= '0;
    end else if (buf_write) begin
        if (calc_col == (FRAME_HEIGHT - 1)) begin
            calc_col <= '0;
        end else begin
            calc_col <= calc_col + 1'b1;
        end
    end
end

// Height divided by half is used for calculations, so we don't need LSB
assign buf_data_in = { calc_color, calc_height[W_Y_POS-1:1] };
assign calc_start  = !in_range_prev &&  in_range_i;
assign buf_write   =  in_range_prev && !in_range_i;
assign buf_read    = in_range_i;
assign buf_addr    = in_range_i ? px_x_i : calc_col;

// ----------------------------------------------------------------------------
// Calc current color based on buffer data
// ----------------------------------------------------------------------------

assign { buf_color, buf_height } = buf_data_out;

always_ff @(posedge clk) begin
    if (in_range_prev) begin
        if ((px_y > ((FRAME_HEIGHT >> 2) - W_Y_POS'(buf_height))) &&
            (px_y < ((FRAME_HEIGHT >> 2) + W_Y_POS'(buf_height)))) begin
            color_o <= buf_color ? { 8'd127, 8'd127, 8'd127 } :
                                   { 8'd255, 8'd255, 8'd255 };
        end else begin
            color_o <= '0;
        end
    end
end

endmodule

`resetall
