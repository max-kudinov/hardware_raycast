`include "dvi_pkg.svh"

`default_nettype none

module primer20k_top #(
    parameter real MOVEMENT_SPEED = 0.08,
    parameter real ROTATION_SPEED = 0.04
) (
`ifndef SIMULATION
    input  var logic       clk,
`endif
    input  var logic       rst_n,
    input  var logic [5:0] keys_inv_i
`ifdef DVI
    ,
    output var logic [2:0] tmds_data_p,
    output var logic [2:0] tmds_data_n,
    output var logic       tmds_clk_p,
    output var logic       tmds_clk_n
`elsif VGA
    ,
    output var logic [3:0] red_o,
    output var logic [3:0] green_o,
    output var logic [3:0] blue_o,

    output var logic       hsync_o,
    output var logic       vsync_o
`endif
);

import dvi_pkg::W_H_RES;
import dvi_pkg::W_V_RES;
import dvi_pkg::W_COLOR;

logic               rst;
logic [5:0]         keys;

logic               px_clk;
logic               pll_clk;
logic               pll_lock;

logic [W_H_RES-1:0] px_x;
logic [W_V_RES-1:0] px_y;
logic               in_range;

`ifdef VGA
logic               hsync;
logic               vsync;
logic [2:0]         delay_in;
logic [2:0]         delay_out;
logic               hsync_del;
logic               vsync_del;
logic               in_range_del;
`endif

// verilator lint_off UNUSEDSIGNAL
logic [W_COLOR-1:0] red;
logic [W_COLOR-1:0] green;
logic [W_COLOR-1:0] blue;
// verilator lint_on UNUSEDSIGNAL

assign keys = ~keys_inv_i;

// Hides this module from Verilator lint
`ifdef GOWIN

    rPLL #(
    `ifdef DVI
        // 252 MHz for DVI serialization
        .FCLKIN    ("27"),
        .IDIV_SEL  (2   ),
        .FBDIV_SEL (27  ),
        .ODIV_SEL  (4   )
    `elsif VGA
        // 50 MHz for VGA (divided by 2 to get 25 MHz pixel clock)
        .FCLKIN    ("27"),
        .IDIV_SEL  (6   ),
        .FBDIV_SEL (12  ),
        .ODIV_SEL  (16  )
    `endif
    ) rpll (
        .CLKIN   (clk     ), // 27 MHZ
        .CLKOUT  (pll_clk ),
        .LOCK    (pll_lock),
        .RESET   ('0      ),
        .RESET_P ('0      ),
        .CLKFB   ('0      ),
        .FBDSEL  ('0      ),
        .IDSEL   ('0      ),
        .ODSEL   ('0      ),
        .PSDA    ('0      ),
        .DUTYDA  ('0      ),
        .FDLY    ('0      )
    );

    `ifdef DVI

        logic serial_clk_div2;

        // Divide by 10 to get 25.2 MHz pixel clock

        CLKDIV2 div_2 (
            .HCLKIN (pll_clk        ),
            .CLKOUT (serial_clk_div2),
            .RESETN (pll_lock       )
        );

        CLKDIV #(
            .DIV_MODE ("5")
        ) div_5 (
            .HCLKIN (serial_clk_div2),
            .CLKOUT (px_clk         ),
            .RESETN (pll_lock       )
        );

        dvi_top dvi_top (
            .serial_clk  (pll_clk    ),
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

    `elsif VGA

        import dvi_pkg::DEL_CYCLES;


        initial px_clk = '0;

        // always_ff can't have LHS values that are also driven by other processes
        // (like initial), see IEEE-1800 2023 9.2.2.4
        always @(posedge pll_clk)
            px_clk <= !px_clk;

        // DVI uses the same timings as VGA
        dvi_sync dvi_sync (
            .clk_i           (px_clk  ),
            .rst_i           (rst     ),

            .hsync_o         (hsync   ),
            .vsync_o         (vsync   ),
            .pixel_x_o       (px_x    ),
            .pixel_y_o       (px_y    ),
            .visible_range_o (in_range)
        );

        assign delay_in = { hsync, vsync, in_range };
        assign { hsync_del, vsync_del, in_range_del } = delay_out;

        delay #(
            .WIDTH    (3         ),
            .N_CYCLES (DEL_CYCLES)
        ) delay (
            .clk    (px_clk   ),
            .rst    (rst      ),
            .data_i (delay_in ),
            .data_o (delay_out)
        );

        always_ff @(posedge px_clk) begin
            hsync_o <= hsync_del;
            vsync_o <= vsync_del;

            red_o   <= '0;
            green_o <= '0;
            blue_o  <= '0;

            if (in_range_del) begin
                red_o   <= red[W_COLOR-1-:4];
                green_o <= green[W_COLOR-1-:4];
                blue_o  <= blue[W_COLOR-1-:4];
            end
        end

    `endif

`elsif SIMULATION

    initial pll_clk = '0;
    initial px_clk  = '0;

    always #1  pll_clk = !pll_clk;
    always #10 px_clk  = !px_clk;

`endif

assign rst = !rst_n || !pll_lock;

raycast_top #(
    .MOVEMENT_SPEED (MOVEMENT_SPEED),
    .ROTATION_SPEED (ROTATION_SPEED)
) raycast_top (
    .clk                (px_clk     ),
    .rst                (rst        ),

    .key_forward_i      (keys[0]    ),
    .key_backward_i     (keys[1]    ),
    .key_left_i         (keys[2]    ),
    .key_right_i        (keys[3]    ),
    .key_rotate_left_i  (keys[4]    ),
    .key_rotate_right_i (keys[5]    ),

    .px_x_i             (px_x       ),
    .px_y_i             (px_y       ),
    .in_range_i         (in_range   ),

    .red_o              (red        ),
    .green_o            (green      ),
    .blue_o             (blue       )
);

endmodule

`resetall
