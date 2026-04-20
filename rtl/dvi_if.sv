interface dvi_if;

    logic       serial_clk;
    logic [2:0] tmds_data_p;
    logic [2:0] tmds_data_n;
    logic       tmds_clk_p;
    logic       tmds_clk_n;

endinterface : dvi_if
