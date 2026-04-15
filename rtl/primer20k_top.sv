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
    output var logic [2:0] tmds_data_p,
    output var logic [2:0] tmds_data_n,
    output var logic       tmds_clk_p,
    output var logic       tmds_clk_n
);

logic [7:0] power_on_rst_cnt;
logic       rst;
logic [5:0] keys;

assign keys = ~keys_inv_i;

`ifdef GOWIN

    logic px_clk;
    logic pixel_clk_div2;
    logic serial_clk;
    logic pll_lock;

    rPLL #(
        .FCLKIN    ("27"),
        .IDIV_SEL  (2   ),
        .FBDIV_SEL (27  ),
        .ODIV_SEL  (4   )
    ) rpll (
        .CLKIN   (clk       ), // 27 MHZ
        .CLKOUT  (serial_clk), // 252 MHz
        .LOCK    (pll_lock  ),
        .RESET   ('0        ),
        .RESET_P ('0        ),
        .CLKFB   ('0        ),
        .FBDSEL  ('0        ),
        .IDSEL   ('0        ),
        .ODSEL   ('0        ),
        .PSDA    ('0        ),
        .DUTYDA  ('0        ),
        .FDLY    ('0        )
    );

    // Divide by 10 to get 25.2 MHz pixel clock

    CLKDIV2 div_2 (
        .HCLKIN (serial_clk    ),
        .CLKOUT (pixel_clk_div2),
        .RESETN (pll_lock      )
    );

    CLKDIV #(
        .DIV_MODE ("5")
    ) div_5 (
        .HCLKIN (pixel_clk_div2),
        .CLKOUT (px_clk        ),
        .RESETN (pll_lock      )
    );

`elsif SIMULATION

    bit serial_clk;
    bit px_clk;

    always #1  serial_clk = !serial_clk;
    always #10 px_clk     = !px_clk;

`endif

// Enable reset after bitstream upload
initial power_on_rst_cnt = '1;

// always_ff can't have LHS values that are also driven by other processes
// (like initial), see IEEE-1800 2023 9.2.2.4
always @(posedge px_clk)
    if (power_on_rst_cnt != '0)
    power_on_rst_cnt <= power_on_rst_cnt - 1'b1;

assign rst = !rst_n || (power_on_rst_cnt != '0);

raycast_top #(
    .MOVEMENT_SPEED (MOVEMENT_SPEED),
    .ROTATION_SPEED (ROTATION_SPEED)
) raycast_top (
    .serial_clk         (serial_clk ),
    .px_clk             (px_clk     ),
    .rst                (rst        ),

    .key_forward_i      (keys[0]    ),
    .key_backward_i     (keys[1]    ),
    .key_left_i         (keys[2]    ),
    .key_right_i        (keys[3]    ),
    .key_rotate_left_i  (keys[4]    ),
    .key_rotate_right_i (keys[5]    ),

    .tmds_data_p        (tmds_data_p),
    .tmds_data_n        (tmds_data_n),
    .tmds_clk_p         (tmds_clk_p ),
    .tmds_clk_n         (tmds_clk_n )
);

endmodule

`resetall
