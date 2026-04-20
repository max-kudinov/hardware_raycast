`include "dvi_pkg.svh"

`default_nettype none

module dvi_top
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

logic       hsync;
logic       vsync;
logic       hsync_del;
logic       vsync_del;
logic       visible_range_del;
logic [2:0] sync_del_in;
logic [2:0] sync_del_out;

logic       serial_clk;
logic [9:0] red_tmds;
logic [9:0] green_tmds;
logic [9:0] blue_tmds;

logic       red_serial;
logic       green_serial;
logic       blue_serial;

// ------------------------------------------------------------------------
// Sync
// ------------------------------------------------------------------------

dvi_sync i_dvi_sync (
    .clk_i           (clk       ),
    .rst_i           (rst       ),
    .hsync_o         (hsync     ),
    .vsync_o         (vsync     ),
    .pixel_x_o       (px_x_o    ),
    .pixel_y_o       (px_y_o    ),
    .visible_range_o (in_range_o)
);

// ------------------------------------------------------------------------
// Encode
// ------------------------------------------------------------------------

assign sync_del_in = { vsync, hsync, in_range_o };
assign { vsync_del, hsync_del, visible_range_del} = sync_del_out;

delay #(
    .WIDTH    (3         ),
    .N_CYCLES (DEL_CYCLES)
) delay (
    .clk    (clk         ),
    .rst    (rst         ),
    .data_i (sync_del_in ),
    .data_o (sync_del_out)
);

tmds_encoder blue_encoder (
    .clk_i (clk              ),
    .rst_i (rst              ),
    .C0    (hsync_del        ),
    .C1    (vsync_del        ),
    .DE    (visible_range_del),
    .D     (blue_i           ),
    .q_out (blue_tmds        )
);

tmds_encoder green_encoder (
    .clk_i (clk              ),
    .rst_i (rst              ),
    .C0    (1'b0             ),
    .C1    (1'b0             ),
    .DE    (visible_range_del),
    .D     (green_i          ),
    .q_out (green_tmds       )
);

tmds_encoder red_encoder (
    .clk_i (clk              ),
    .rst_i (rst              ),
    .C0    (1'b0             ),
    .C1    (1'b0             ),
    .DE    (visible_range_del),
    .D     (red_i            ),
    .q_out (red_tmds         )
);

// ------------------------------------------------------------------------
// Serialize
// ------------------------------------------------------------------------

assign serial_clk = display_if.serial_clk;

serializer #(
    .W_DATA (10)
) blue_serializer (
    .clk    (serial_clk ),
    .rst    (rst        ),
    .data_i (blue_tmds  ),
    .data_o (blue_serial)
);

serializer #(
    .W_DATA (10)
) green_serializer (
    .clk    (serial_clk  ),
    .rst    (rst         ),
    .data_i (green_tmds  ),
    .data_o (green_serial)
);

serializer #(
    .W_DATA (10)
) red_serializer (
    .clk    (serial_clk),
    .rst    (rst       ),
    .data_i (red_tmds  ),
    .data_o (red_serial)
);

// ------------------------------------------------------------------------
// Create differential signals
// ------------------------------------------------------------------------

ds_buf blue_ds_buf (
    .in    (blue_serial              ),
    .out   (display_if.tmds_data_p[0]),
    .out_n (display_if.tmds_data_n[0])
);

ds_buf green_ds_buf (
    .in    (green_serial             ),
    .out   (display_if.tmds_data_p[1]),
    .out_n (display_if.tmds_data_n[1])
);

ds_buf red_ds_buf (
    .in    (red_serial               ),
    .out   (display_if.tmds_data_p[2]),
    .out_n (display_if.tmds_data_n[2])
);

ds_buf clk_ds_buf (
    .in    (clk                  ),
    .out   (display_if.tmds_clk_p),
    .out_n (display_if.tmds_clk_n)
);

endmodule

`resetall
