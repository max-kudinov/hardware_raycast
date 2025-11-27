`ifndef FIXEDPOINT_PKG_SVH
`define FIXEDPOINT_PKG_SVH

package fixedpoint;

    localparam W_INT  = 5;
    localparam W_FRAC = 9;
    localparam N_ITER = 5;

    function automatic logic [W_INT-1:-W_FRAC] fixp_mult (
        input var logic [W_INT-1:-W_FRAC] num_a,
        input var logic [W_INT-1:-W_FRAC] num_b
    );
        // Bits are truncated after multiplication
        // verilator lint_off UNUSEDSIGNAL
        logic [W_INT*2-1:-W_FRAC*2] mult_res;
        // verilator lint_on UNUSEDSIGNAL
        begin
            mult_res = num_a * num_b;
            return mult_res[W_INT-1:-W_FRAC];
        end
    endfunction

endpackage

`endif // FIXEDPOINT_PKG_SVH
