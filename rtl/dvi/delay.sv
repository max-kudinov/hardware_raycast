`default_nettype none

module delay #(
    parameter WIDTH    = 8,
    parameter N_CYCLES = 8
) (
    input  var logic             clk_i,
    // Used in one of generate branches
    // verilator lint_off UNUSEDSIGNAL
    input  var logic             rst_i,
    // verilator lint_on UNUSEDSIGNAL
    input  var logic [WIDTH-1:0] data_i,
    output var logic [WIDTH-1:0] data_o
);

    localparam W_PTR   = $clog2(N_CYCLES);
    localparam MAX_PTR = N_CYCLES - 1;

    if (N_CYCLES == '0) begin : bypass_gen

        assign data_o = data_i;

    end else if (N_CYCLES == 1) begin: single_ff_gen

        always_ff @(posedge clk_i)
            data_o <= data_i;

    end else begin : ring_buf_gen

        logic [WIDTH-1:0] mem [N_CYCLES];
        logic [W_PTR-1:0] ptr;

        always_ff @(posedge clk_i)
            if (rst_i)
                ptr <= '0;
            else
                ptr <= (ptr == W_PTR'(MAX_PTR)) ? '0 : ptr + 1'b1;

        always_ff @(posedge clk_i)
            mem[ptr] <= data_i;

        assign data_o = mem[ptr];

    end

endmodule

`resetall
