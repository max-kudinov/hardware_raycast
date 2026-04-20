`include "dvi_pkg.svh"

`default_nettype none

module vga
    import dvi_pkg::W_H_RES;
    import dvi_pkg::W_V_RES;
    import dvi_pkg::W_COLOR;
(
    input  var logic               clk,
    input  var logic               rst,

    input  var logic [W_COLOR-1:0] red_i,
    input  var logic [W_COLOR-1:0] green_i,
    input  var logic [W_COLOR-1:0] blue_i,

    output var logic [W_H_RES-1:0] px_x_o,
    output var logic [W_V_RES-1:0] px_y_o,
    output var logic               in_range_o,

    interface                      display_if
);

import dvi_pkg::DEL_CYCLES;

localparam int unsigned W_DELAY = 3;

logic               hsync;
logic               vsync;
logic [W_DELAY-1:0] delay_in;
logic [W_DELAY-1:0] delay_out;
logic               hsync_del;
logic               vsync_del;
logic               in_range_del;

// DVI uses the same timings as VGA
dvi_sync dvi_sync (
    .clk_i           (clk       ),
    .rst_i           (rst       ),

    .hsync_o         (hsync     ),
    .vsync_o         (vsync     ),
    .pixel_x_o       (px_x_o    ),
    .pixel_y_o       (px_y_o    ),
    .visible_range_o (in_range_o)
);

assign delay_in = { hsync, vsync, in_range_o };
assign { hsync_del, vsync_del, in_range_del } = delay_out;

delay #(
    .WIDTH    (W_DELAY   ),
    .N_CYCLES (DEL_CYCLES)
) delay (
    .clk    (clk      ),
    .rst    (rst      ),
    .data_i (delay_in ),
    .data_o (delay_out)
);

always_ff @(posedge clk) begin
    display_if.hsync <= hsync_del;
    display_if.vsync <= vsync_del;

    display_if.red   <= '0;
    display_if.green <= '0;
    display_if.blue  <= '0;

    if (in_range_del) begin
        display_if.red   <= red_i  [W_COLOR-1-:4];
        display_if.green <= green_i[W_COLOR-1-:4];
        display_if.blue  <= blue_i [W_COLOR-1-:4];
    end
end

endmodule

`resetall
