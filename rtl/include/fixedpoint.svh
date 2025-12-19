`ifndef FIXEDPOINT_PKG_SVH
`define FIXEDPOINT_PKG_SVH

package fixedpoint;

    localparam W_INT  = 8;
    localparam W_FRAC = 10;
    localparam N_ITER = 8;

    function automatic logic [W_INT-1:-W_FRAC] mult (
        input logic [W_INT-1:-W_FRAC] num_a,
        input logic [W_INT-1:-W_FRAC] num_b
    );
        // Bits are truncated after multiplication
        // verilator lint_off UNUSEDSIGNAL
        logic [W_INT*2-1:-W_FRAC*2] mult_res;
        // verilator lint_on UNUSEDSIGNAL
        mult_res = num_a * num_b;
        return mult_res[W_INT-1:-W_FRAC];
    endfunction

    function automatic logic [W_INT-1:-W_FRAC] signed_mult (
        input logic signed [W_INT-1:-W_FRAC] num_a,
        input logic signed [W_INT-1:-W_FRAC] num_b
    );
        // Bits are truncated after multiplication
        // verilator lint_off UNUSEDSIGNAL
        logic signed [W_INT*2-1:-W_FRAC*2] mult_res;
        // verilator lint_on UNUSEDSIGNAL
        mult_res = num_a * num_b;
        return mult_res[W_INT-1:-W_FRAC];
    endfunction

    function automatic integer int_mult (
        input integer                 num_a,
        input logic [W_INT-1:-W_FRAC] num_b
    );
        // Bits are truncated after multiplication
        // verilator lint_off UNUSEDSIGNAL
        logic [31:-W_FRAC*2] mult_res;
        // verilator lint_on UNUSEDSIGNAL
        mult_res = (W_INT+W_FRAC)'({num_a, {W_FRAC {1'b0} } }) * num_b;
        return integer'(mult_res[31:0]);
    endfunction


    function automatic logic [W_INT-1:-W_FRAC] abs (
        input logic signed [W_INT-1:-W_FRAC] num
    );
        if (num < 0)
            return unsigned'(-num);
        else
            return unsigned'(num);
    endfunction

    function automatic logic [W_INT-1:-W_FRAC] int_to_fixp (
        input [W_INT-1:0] num
    );
        return { num, { W_FRAC {1'b0} } };
    endfunction

endpackage

`endif // FIXEDPOINT_PKG_SVH
