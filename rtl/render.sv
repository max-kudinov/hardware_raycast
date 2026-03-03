`include "fixp_pkg.svh"
`include "dvi_pkg.svh"

`default_nettype none

module render
    import fixp_pkg::*;
    import dvi_pkg::W_H_RES;
    import dvi_pkg::W_V_RES;
    import dvi_pkg::FRAME_WIDTH;
    import dvi_pkg::FRAME_HEIGHT;
    import dvi_pkg::W_COLOR;
(
    input  var logic                 clk,
    input  var logic                 rst,

    // DVI
    input  var logic [W_H_RES-1:0]   px_x_i,
    input  var logic [W_V_RES-1:0]   px_y_i,
    input  var logic                 in_range_i,
    input  var logic                 new_frame_i,
    output var logic [W_COLOR-1:0]   red_o,
    output var logic [W_COLOR-1:0]   green_o,
    output var logic [W_COLOR-1:0]   blue_o,

    // Map coordinates to check for a wall
    output var logic [POS_W_INT-1:0] lookup_map_x_o,
    output var logic [POS_W_INT-1:0] lookup_map_y_o,
    input  var logic                 wall_hit_i,

    // Camera coordinates
    input  var pos_fixp_t            pos_x_i,
    input  var pos_fixp_t            pos_y_i,
    // Camera direction
    input  var ray_fixp_t            dir_x_i,
    input  var ray_fixp_t            dir_y_i,
    // Camera plane
    input  var ray_fixp_t            plane_x_i,
    input  var ray_fixp_t            plane_y_i
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned W_BUF_DATA = W_V_RES; // Height without LSB + 1 bit for color
localparam int unsigned BUF_DEPTH  = FRAME_WIDTH * 2;
localparam int unsigned W_BUF_ADDR = $clog2(BUF_DEPTH);

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic [W_BUF_DATA-1:0] frame_buffer [BUF_DEPTH];
logic                  buf_write;
logic                  buf_read;
logic                  buf_toggle;
logic [W_BUF_ADDR-1:0] buf_rd_addr;
logic [W_BUF_ADDR-1:0] buf_wr_addr;
logic [W_BUF_DATA-1:0] buf_wr_data;
logic [W_BUF_DATA-1:0] buf_rd_data;
logic [W_V_RES-2:0]    buf_height;
logic                  buf_color;

// LSB is not used
// verilator lint_off UNUSEDSIGNAL
logic [W_V_RES-1:0]    calc_height;
// verilator lint_on UNUSEDSIGNAL
logic                  calc_color;
logic                  calc_start;
logic                  calc_done;
logic [W_H_RES-1:0]    calc_px_x;
logic                  calc_active;

logic                  in_range_prev;
logic [W_V_RES-1:0]    px_y;


always_ff @(posedge clk)
    if (rst)
        buf_toggle <= '0;
    else if (new_frame_i)
        buf_toggle <= !buf_toggle;

// Simple dual-port block RAM with read-first behavior
always_ff @(posedge clk) begin
    if (buf_write)
        frame_buffer[buf_wr_addr] <= buf_wr_data;

    if (buf_read)
        buf_rd_data <= frame_buffer[buf_rd_addr];
end

line_height_calc line_height_calc (
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

// Height divided in half is used for calculations, so we don't need LSB
assign buf_wr_data = { calc_color, calc_height[W_V_RES-1:1] };
assign buf_write   = calc_done;
assign buf_wr_addr = W_BUF_ADDR'(calc_px_x) + W_BUF_ADDR'(FRAME_WIDTH & { W_H_RES { buf_toggle } });
assign buf_read    = in_range_i;
assign buf_rd_addr = W_BUF_ADDR'(px_x_i) + W_BUF_ADDR'(FRAME_WIDTH & { W_H_RES { !buf_toggle } });

// ----------------------------------------------------------------------------
// Calc current color based on buffer data
// ----------------------------------------------------------------------------

assign { buf_color, buf_height } = buf_rd_data;

always_ff @(posedge clk) begin
    if (in_range_prev) begin
        if ((px_y >= ((FRAME_HEIGHT >> 1) - W_V_RES'(buf_height))) &&
            (px_y <= ((FRAME_HEIGHT >> 1) + W_V_RES'(buf_height)))) begin
            { red_o, green_o, blue_o } <= buf_color ? { 8'd127, 8'd127, 8'd127 } :
                                                      { 8'd255, 8'd255, 8'd255 };
        end else begin
            { red_o, green_o, blue_o } <= '0;
        end
    end
end

endmodule

`resetall
