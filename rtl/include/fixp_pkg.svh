`ifndef FIXP_PKG_SVH
`define FIXP_PKG_SVH

package fixp_pkg;

    localparam int unsigned W_INT  = 8;
    localparam int          W_FRAC = 10;
    localparam int unsigned N_ITER = 8;

    typedef logic        [W_INT-1:-W_FRAC] fixp_t;
    typedef logic signed [W_INT-1:-W_FRAC] sfixp_t;

    function automatic fixp_t mult (
        input fixp_t num_a,
        input fixp_t num_b
    );
        // Bits are truncated after multiplication
        // verilator lint_off UNUSEDSIGNAL
        logic [W_INT*2-1:-W_FRAC*2] mult_res;
        // verilator lint_on UNUSEDSIGNAL
        mult_res = num_a * num_b;
        return mult_res[W_INT-1:-W_FRAC];
    endfunction

    function automatic sfixp_t signed_mult (
        input sfixp_t num_a,
        input sfixp_t num_b
    );
        // Bits are truncated after multiplication
        // verilator lint_off UNUSEDSIGNAL
        logic signed [W_INT*2-1:-W_FRAC*2] mult_res;
        // verilator lint_on UNUSEDSIGNAL
        mult_res = num_a * num_b;
        return sfixp_t'(mult_res[W_INT-1:-W_FRAC]);
    endfunction

    function automatic fixp_t abs (
        input sfixp_t num
    );
        if (num < 0)
            return unsigned'(-num);
        else
            return unsigned'(num);
    endfunction

    function automatic fixp_t int_to_fixp (
        input [W_INT-1:0] num
    );
        return { num, { W_FRAC {1'b0} } };
    endfunction

    function automatic fixp_t real_to_fixp (
        input real num
    );
        return fixp_t'(num * 2**W_FRAC);
    endfunction

    function automatic sfixp_t real_to_sfixp (
        input real num
    );
        return sfixp_t'(num * 2**W_FRAC);
    endfunction

endpackage

`endif // FIXP_PKG_SVH
