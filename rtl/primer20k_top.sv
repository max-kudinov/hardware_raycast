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
    input  var logic [5:0] keys_inv_i,
`ifdef VGA
    output var logic [3:0] red_o,
    output var logic [3:0] green_o,
    output var logic [3:0] blue_o,

    output var logic       hsync_o,
    output var logic       vsync_o
`else
    output var logic [2:0] tmds_data_p,
    output var logic [2:0] tmds_data_n,
    output var logic       tmds_clk_p,
    output var logic       tmds_clk_n
`endif
);

logic       rst;
logic [7:0] power_on_rst_cnt;
logic [5:0] keys;
logic       px_clk;
logic       pll_clk;
logic       pll_lock;

// Hides this module from Verilator lint
`ifdef GOWIN

    rPLL #(
        .FCLKIN    ("27"),
    `ifdef VGA
        // 50 MHz for VGA (divided by 2 to get 25 MHz pixel clock)
        .IDIV_SEL  (6   ),
        .FBDIV_SEL (12  ),
        .ODIV_SEL  (16  )
    `else
        // 252 MHz for DVI serialization
        .IDIV_SEL  (2   ),
        .FBDIV_SEL (27  ),
        .ODIV_SEL  (4   )
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

    `ifndef VGA

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

    `endif

`elsif SIMULATION

    assign pll_lock = '0;

    initial pll_clk = '0;
    initial px_clk  = '0;

    always #1  pll_clk = !pll_clk;
    always #10 px_clk  = !px_clk;

`endif


`ifdef VGA

    vga_if display();

    assign red_o   = display.red;
    assign green_o = display.green;
    assign blue_o  = display.blue;
    assign vsync_o = display.vsync;
    assign hsync_o = display.hsync;

    initial px_clk = '0;

    // always_ff can't have LHS values that are also driven by other processes
    // (like initial), see IEEE-1800 2023 9.2.2.4
    always @(posedge pll_clk)
        px_clk <= !px_clk;

`else

    dvi_if display();

    assign display.serial_clk = pll_clk;

    assign tmds_data_p = display.tmds_data_p;
    assign tmds_data_n = display.tmds_data_n;
    assign tmds_clk_p  = display.tmds_clk_p;
    assign tmds_clk_n  = display.tmds_clk_n;

`endif

initial power_on_rst_cnt = '1;

always @(posedge pll_clk)
    if (pll_lock && power_on_rst_cnt != '0)
        power_on_rst_cnt <= power_on_rst_cnt - 1'b1;

assign rst  = !rst_n || (power_on_rst_cnt != '0);
assign keys = ~keys_inv_i;

raycast_top #(
    .MOVEMENT_SPEED (MOVEMENT_SPEED),
    .ROTATION_SPEED (ROTATION_SPEED)
) raycast_top (
    .clk                (px_clk ),
    .rst                (rst    ),

    .key_forward_i      (keys[0]),
    .key_backward_i     (keys[1]),
    .key_left_i         (keys[2]),
    .key_right_i        (keys[3]),
    .key_rotate_left_i  (keys[4]),
    .key_rotate_right_i (keys[5]),

    .display_if         (display)
);

endmodule

`resetall
