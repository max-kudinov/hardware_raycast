`default_nettype none

module primer20k_top #(
    parameter real         MOVEMENT_SPEED      = 0.8,
    parameter real         ROTATION_SPEED      = 0.4,
    parameter int unsigned        W_X_POS      = 10,
    parameter int unsigned        W_Y_POS      = 9,
    parameter logic [W_X_POS-1:0] FRAME_WIDTH  = 640,
    parameter logic [W_Y_POS-1:0] FRAME_HEIGHT = 480
) (
    input  var logic       clk,
    input  var logic       rst_n,
    input  var logic [5:0] keys_inv_i,
    output var logic [2:0] tmds_data_p,
    output var logic [2:0] tmds_data_n,
    output var logic       tmds_clk_p,
    output var logic       tmds_clk_n
);

// verilator lint_off UNUSEDSIGNAL
// verilator lint_off UNDRIVEN
logic       pixel_clk;
logic       pixel_clk_div2;
logic       serial_clk;
logic       pll_lock;
// verilator lint_on UNDRIVEN
// verilator lint_on UNUSEDSIGNAL
logic       rst;
logic       power_on_rst_n;
logic [5:0] keys;

// Reset on upload
initial begin
    power_on_rst_n = '0;
end

always_ff @(posedge pixel_clk)
    power_on_rst_n <= '1;

// Invert board signals
assign rst  = !rst_n || !power_on_rst_n;
assign keys = ~keys_inv_i;

// Hide blackboxes from lint
`ifdef GOWIN

    rPLL #(
        .FCLKIN    ("27"),
        .IDIV_SEL  (2   ),
        .FBDIV_SEL (27  ),
        .ODIV_SEL  (4   )
    ) rpll (
        .CLKIN   (clk_i     ), // 27 MHZ
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
        .CLKOUT (pixel_clk     ),
        .RESETN (pll_lock      )
    );

`endif

`ifdef SIMULATION
    always #1  serial_clk = !serial_clk;
    always #10 pixel_clk  = !pixel_clk;
`endif

raycast_top #(
    .MOVEMENT_SPEED (MOVEMENT_SPEED),
    .ROTATION_SPEED (ROTATION_SPEED),
    .W_X_POS        (W_X_POS       ),
    .W_Y_POS        (W_Y_POS       ),
    .FRAME_WIDTH    (FRAME_WIDTH   ),
    .FRAME_HEIGHT   (FRAME_HEIGHT  )
) raycast_top (
    .serial_clk         (serial_clk ),
    .px_clk             (pixel_clk  ),
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
