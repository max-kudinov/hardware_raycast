`include "fixedpoint.svh"
`include "dvi_pkg.svh"

`default_nettype none

module render
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
    import dvi_pkg::COLOR_W;
#(
    parameter int unsigned        W_X_POS      = 10,
    parameter int unsigned        W_Y_POS      = 9,
    parameter logic [W_X_POS-1:0] FRAME_WIDTH  = 640,
    parameter logic [W_Y_POS-1:0] FRAME_HEIGHT = 480
) (
    input  var logic                          clk,
    input  var logic                          rst,

    // DVI
    input  var logic        [W_X_POS-1:0]     px_x_i,
    input  var logic        [W_Y_POS-1:0]     px_y_i,
    input  var logic                          in_range_i,
    input  var logic                          new_frame_i,
    output var logic        [COLOR_W-1:0]     red_o,
    output var logic        [COLOR_W-1:0]     green_o,
    output var logic        [COLOR_W-1:0]     blue_o,

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
    input  var logic                          wall_hit_i
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
logic [W_BUF_ADDR-1:0] buf_rd_addr;
logic [W_BUF_ADDR-1:0] buf_wr_addr;
logic [W_BUF_DATA-1:0] buf_wr_data;
logic [W_BUF_DATA-1:0] buf_rd_data;
logic [W_Y_POS-2:0]    buf_height;
logic                  buf_color;

// LSB is not used
// verilator lint_off UNUSEDSIGNAL
logic [W_Y_POS-1:0]    calc_height;
// verilator lint_on UNUSEDSIGNAL
logic                  calc_color;
logic                  calc_start;
logic                  calc_done;
logic [W_X_POS-1:0]    calc_px_x;
logic                  calc_active;

logic                  in_range_prev;
logic [W_Y_POS-1:0]    px_y;

// Simple dual-port block RAM with read-first behavior
always_ff @(posedge clk) begin
    if (buf_write)
        frame_buffer[buf_wr_addr] <= buf_wr_data;

    if (buf_read)
        buf_rd_data <= frame_buffer[buf_rd_addr];
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
    .px_x_i         (calc_px_x     ),

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
        calc_px_x  <= '0;
    end else if (calc_done) begin
        if (calc_px_x == (FRAME_WIDTH - 1)) begin
            calc_px_x <= '0;
        end else begin
            calc_px_x <= calc_px_x + 1'b1;
        end
    end
end

always_ff @(posedge clk) begin
    if (rst)
        calc_active <= '0;
    else if (new_frame_i)
        calc_active <= '1;
    else if (calc_start && (calc_px_x == (FRAME_WIDTH - 1)))
        calc_active <= '0;
end

always_ff @(posedge clk)
    if (rst)
        calc_start <= '0;
    else if (new_frame_i)
        calc_start <= '1;
    else
        calc_start <= calc_active && calc_done;

// Height divided by half is used for calculations, so we don't need LSB
assign buf_wr_data = { calc_color, calc_height[W_Y_POS-1:1] };
assign buf_write   = calc_done;
assign buf_wr_addr = calc_px_x;
assign buf_read    = in_range_i;
assign buf_rd_addr = px_x_i;

// ----------------------------------------------------------------------------
// Calc current color based on buffer data
// ----------------------------------------------------------------------------

assign { buf_color, buf_height } = buf_rd_data;

always_ff @(posedge clk) begin
    if (in_range_prev) begin
        if ((px_y > ((FRAME_HEIGHT >> 2) - W_Y_POS'(buf_height))) &&
            (px_y < ((FRAME_HEIGHT >> 2) + W_Y_POS'(buf_height)))) begin
            { red_o, green_o, blue_o } <= buf_color ? { 8'd127, 8'd127, 8'd127 } :
                                                      { 8'd255, 8'd255, 8'd255 };
        end else begin
            { red_o, green_o, blue_o } <= '0;
        end
    end
end

endmodule

`resetall
