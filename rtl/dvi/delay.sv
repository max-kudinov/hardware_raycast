`default_nettype none

module delay #(
    parameter int unsigned WIDTH    = 8,
    parameter int unsigned N_CYCLES = 8
) (
    input  var logic             clk,
    // Used in one of generate branches
    // verilator lint_off UNUSEDSIGNAL
    input  var logic             rst,
    // verilator lint_on UNUSEDSIGNAL
    input  var logic [WIDTH-1:0] data_i,
    output var logic [WIDTH-1:0] data_o
);

localparam int unsigned W_PTR   = $clog2(N_CYCLES);
localparam [W_PTR-1:0]  MAX_PTR = W_PTR'(N_CYCLES - 1);

if (N_CYCLES == '0) begin : bypass_gen

    assign data_o = data_i;

end else if (N_CYCLES == 1) begin: single_ff_gen

    always_ff @(posedge clk)
        data_o <= data_i;

end else begin : ring_buf_gen

    logic [WIDTH-1:0] mem [N_CYCLES];
    logic [W_PTR-1:0] ptr;

    always_ff @(posedge clk)
        if (rst)
            ptr <= '0;
        else
            ptr <= (ptr == MAX_PTR) ? '0 : ptr + 1'b1;

    always_ff @(posedge clk)
        mem[ptr] <= data_i;

    assign data_o = mem[ptr];

end

endmodule

`resetall
