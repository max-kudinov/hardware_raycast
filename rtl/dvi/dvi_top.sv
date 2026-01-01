`include "dvi_pkg.svh"

`default_nettype none

module dvi_top
    import dvi_pkg::X_POS_W;
    import dvi_pkg::Y_POS_W;
    import dvi_pkg::COLOR_W;
(
    input  var logic               serial_clk_i,
    input  var logic               pixel_clk_i,
    input  var logic               rst_i,

    input  var logic [COLOR_W-1:0] red_i,
    input  var logic [COLOR_W-1:0] green_i,
    input  var logic [COLOR_W-1:0] blue_i,

    output var logic [X_POS_W-1:0] x_o,
    output var logic [Y_POS_W-1:0] y_o,
    output var logic               in_range_o,

    output var logic [        2:0] tmds_data_p,
    output var logic [        2:0] tmds_data_n,
    output var logic               tmds_clk_p,
    output var logic               tmds_clk_n
);

    import dvi_pkg::DEL_CYCLES;

    logic       hsync;
    logic       vsync;
    logic       hsync_del;
    logic       vsync_del;
    logic       visible_range_del;
    logic [2:0] sync_del_in;
    logic [2:0] sync_del_out;

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
        .clk_i           ( pixel_clk_i   ),
        .rst_i           ( rst_i         ),
        .hsync_o         ( hsync         ),
        .vsync_o         ( vsync         ),
        .pixel_x_o       ( x_o           ),
        .pixel_y_o       ( y_o           ),
        .visible_range_o ( in_range_o    )
    );

    // ------------------------------------------------------------------------
    // Encode
    // ------------------------------------------------------------------------

    assign sync_del_in = { vsync, hsync, in_range_o };
    assign { vsync_del, hsync_del, visible_range_del} = sync_del_out;

    delay #(
        .WIDTH    ( 3          ),
        .N_CYCLES ( DEL_CYCLES )
    ) delay (
        .clk_i ( pixel_clk_i  ),
        .rst_i ( rst_i        ),
        .data_i( sync_del_in  ),
        .data_o( sync_del_out )
    );

    tmds_encoder blue_encoder (
        .clk_i ( pixel_clk_i       ),
        .rst_i ( rst_i             ),
        .C0    ( hsync_del         ),
        .C1    ( vsync_del         ),
        .DE    ( visible_range_del ),
        .D     ( blue_i            ),
        .q_out ( blue_tmds         )
    );

    tmds_encoder green_encoder (
        .clk_i ( pixel_clk_i       ),
        .rst_i ( rst_i             ),
        .C0    ( 1'b0              ),
        .C1    ( 1'b0              ),
        .DE    ( visible_range_del ),
        .D     ( green_i           ),
        .q_out ( green_tmds        )
    );

    tmds_encoder red_encoder (
        .clk_i ( pixel_clk_i       ),
        .rst_i ( rst_i             ),
        .C0    ( 1'b0              ),
        .C1    ( 1'b0              ),
        .DE    ( visible_range_del ),
        .D     ( red_i             ),
        .q_out ( red_tmds          )
    );

    // ------------------------------------------------------------------------
    // Serialize
    // ------------------------------------------------------------------------

    serializer #(
        .DATA_W ( 10 )
    ) blue_serializer (
        .clk_i  ( serial_clk_i ),
        .rst_i  ( rst_i        ),
        .data_i ( blue_tmds    ),
        .data_o ( blue_serial  )
    );

    serializer #(
        .DATA_W ( 10 )
    ) green_serializer (
        .clk_i  ( serial_clk_i ),
        .rst_i  ( rst_i        ),
        .data_i ( green_tmds   ),
        .data_o ( green_serial )
    );

    serializer #(
        .DATA_W ( 10 )
    ) red_serializer (
        .clk_i  ( serial_clk_i ),
        .rst_i  ( rst_i        ),
        .data_i ( red_tmds     ),
        .data_o ( red_serial   )
    );

    // ------------------------------------------------------------------------
    // Create differential signals
    // ------------------------------------------------------------------------

    ds_buf blue_ds_buf (
        .in    ( blue_serial     ),
        .out   ( tmds_data_p [0] ),
        .out_n ( tmds_data_n [0] )
    );

    ds_buf green_ds_buf (
        .in    ( green_serial    ),
        .out   ( tmds_data_p [1] ),
        .out_n ( tmds_data_n [1] )
    );

    ds_buf red_ds_buf (
        .in    ( red_serial      ),
        .out   ( tmds_data_p [2] ),
        .out_n ( tmds_data_n [2] )
    );

    ds_buf clk_ds_buf (
        .in    ( pixel_clk_i ),
        .out   ( tmds_clk_p  ),
        .out_n ( tmds_clk_n  )
    );

endmodule

`resetall
