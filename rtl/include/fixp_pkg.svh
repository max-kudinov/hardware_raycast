`ifndef FIXP_PKG_SVH
`define FIXP_PKG_SVH

`define REAL_TO_FIXP(macro_real_num, macro_type) \
    macro_type'(macro_real_num * 2 ** (-$right(macro_type)))

`define INT_TO_FIXP(macro_int_num, macro_type)             \
    macro_type'({ ($left(macro_type) + 1)'(macro_int_num), \
                  { -$right(macro_type) {1'b0} }           \
                })

`define FIXP_MULT(macro_num1, macro_num2, macro_type)        \
        macro_type'(($size(macro_num1) + $size(macro_num2))' \
        (macro_num1 * macro_num2) >> -$right(macro_num1))

`define FIXP_ABS(macro_num, macro_type) \
    (macro_num < 0) ? macro_type'(-macro_num) : macro_type'(macro_num)

    localparam int unsigned W_INT_POS = 5;
    localparam int unsigned W_INT_POS_EXT = W_INT_POS + 3;
    localparam int          W_FRAC_POS = 10;

    typedef logic [W_INT_POS-1:-W_FRAC_POS]    pos_fixp_t;
    typedef logic [W_INT_POS_EXT-1:-W_FRAC_POS] ext_pos_fixp_t;

package fixp_pkg;

    localparam int unsigned N_ITER = 8;

    localparam int unsigned W_INT  = 8;
    localparam int          W_FRAC = 10;

    typedef logic        [W_INT-1:-W_FRAC] fixp_t;
    typedef logic signed [W_INT-1:-W_FRAC] sfixp_t;

endpackage

`endif // FIXP_PKG_SVH
