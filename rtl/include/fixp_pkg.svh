`ifndef FIXP_PKG_SVH
`define FIXP_PKG_SVH

`define REAL_TO_FIXP(macro_real_num, macro_type)    \
    macro_type'(                                    \
        macro_real_num * 2 ** (-$right(macro_type)) \
    )

`define INT_TO_FIXP(macro_int_num, macro_type)     \
    macro_type'(                                   \
        { ($left(macro_type) + 1)'(macro_int_num), \
          { -$right(macro_type) {1'b0} }           \
        }                                          \
    )

`define FIXP_MULT(macro_num1, macro_num2, macro_type)                     \
        macro_type'(                                                      \
            ($size(macro_num1) + $size(macro_num2))'                      \
            ((macro_num1 * macro_num2 + (1 << (-$right(macro_type) - 1))) \
            >> -$right(macro_num1))                                       \
        )

`define FIXP_ABS(macro_num, macro_type)          \
    macro_type'(                                 \
        (macro_num < 0) ? -macro_num : macro_num \
    )

`define FIXP_CAST(macro_num, macro_type_current, macro_type_target)                       \
    /* verilator lint_off WIDTHEXPAND */                                                  \
    macro_type_target'(                                                                   \
        (-$right(macro_type_current) - -$right(macro_type_target) > 0) ?                  \
            ((macro_num) >>> (-$right(macro_type_current) - -$right(macro_type_target))) : \
            ((macro_num) << (-$right(macro_type_target) - -$right(macro_type_current)))   \
    )                                                                                     \
    /* verilator lint_on WIDTHEXPAND */


localparam int unsigned RAY_W_INT       = 2;
localparam              RAY_W_FRAC      = 10;

localparam int unsigned POS_W_INT       = 5;
localparam              POS_W_FRAC      = 8;

localparam int unsigned SIDE_W_INT      = 1;
localparam              SIDE_W_FRAC     = 8;

localparam int unsigned EXT_POS_W_INT   = 8;
localparam              EXT_POS_W_FRAC  = 8;

localparam int unsigned INV_DIST_W_INT  = 1;
localparam              INV_DIST_W_FRAC = 10;

localparam int unsigned INV_W_INT       = 8;
localparam              INV_W_FRAC      = 10;


typedef logic signed [RAY_W_INT-1:-RAY_W_FRAC]           ray_fixp_t;
typedef logic        [POS_W_INT-1:-POS_W_FRAC]           pos_fixp_t;
typedef logic        [INV_W_INT-1:-INV_W_FRAC]           inv_fixp_t;
typedef logic        [SIDE_W_INT-1:-SIDE_W_FRAC]         side_fixp_t;
typedef logic        [EXT_POS_W_INT-1:-EXT_POS_W_FRAC]   ext_pos_fixp_t;
typedef logic        [INV_DIST_W_INT-1:-INV_DIST_W_FRAC] inv_dist_fixp_t;


package fixp_pkg;

    localparam int unsigned N_ITER = 8;

    localparam int unsigned W_INT  = 8;
    localparam int          W_FRAC = 10;

    typedef logic        [W_INT-1:-W_FRAC] fixp_t;
    typedef logic signed [W_INT-1:-W_FRAC] sfixp_t;

endpackage

`endif // FIXP_PKG_SVH
