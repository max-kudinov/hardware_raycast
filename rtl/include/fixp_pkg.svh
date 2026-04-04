`ifndef FIXP_PKG_SVH
`define FIXP_PKG_SVH

package fixp_pkg;

    localparam int unsigned RAY_W_INT       = 2;
    localparam int unsigned RAY_W_FRAC      = 10;

    localparam int unsigned POS_W_INT       = 5;
    localparam int unsigned POS_W_FRAC      = 8;

    localparam int unsigned SIDE_W_INT      = 1;
    localparam int unsigned SIDE_W_FRAC     = 8;

    localparam int unsigned EXT_POS_W_INT   = 8;
    localparam int unsigned EXT_POS_W_FRAC  = 8;

    localparam int unsigned INV_DIST_W_INT  = 1;
    localparam int unsigned INV_DIST_W_FRAC = 10;

    localparam int unsigned INV_W_INT       = 8;
    localparam int unsigned INV_W_FRAC      = 10;

    localparam int unsigned PROJ_W_INT      = POS_W_INT + 1;
    localparam int unsigned PROJ_W_FRAC     = RAY_W_FRAC;

    localparam int unsigned INV_ITER_NUM    = 8;

    typedef logic signed [RAY_W_INT-1:-signed'(RAY_W_FRAC)]           ray_fixp_t;
    typedef logic        [POS_W_INT-1:-signed'(POS_W_FRAC)]           pos_fixp_t;
    typedef logic        [INV_W_INT-1:-signed'(INV_W_FRAC)]           inv_fixp_t;
    typedef logic signed [PROJ_W_INT-1:-signed'(PROJ_W_FRAC)]         proj_fixp_t;
    typedef logic        [SIDE_W_INT-1:-signed'(SIDE_W_FRAC)]         side_fixp_t;
    typedef logic        [EXT_POS_W_INT-1:-signed'(EXT_POS_W_FRAC)]   ext_pos_fixp_t;
    typedef logic        [INV_DIST_W_INT-1:-signed'(INV_DIST_W_FRAC)] inv_dist_fixp_t;

endpackage : fixp_pkg


`define REAL_TO_FIXP(real_num, T) \
    T'(real_num * 2 ** (-$right(T)))

`define INT_TO_FIXP(int_num, T) \
    T'({ ($left(T) + 1)'(int_num), { -$right(T) {1'b0} } })

`define FIXP_MULT(a, b)              \
    type(a)'(                        \
        (2 * $size(a))'(             \
            ((a * b) +               \
            (1 << (-$right(a) - 1))) \
            >> -$right(a)            \
        )                            \
    )

`define FIXP_MULT_TRUNC(a, b) \
    type(a)'((2 * $size(a))'((a * b) >> -$right(a)))

`define FIXP_ABS(num) \
    type(num)'((num < 0) ? -num : num )

`define FIXP_CAST(num, T)                                                      \
    T'({                                                                       \
        (-$right(num) - -$right(T) > 0) ?                                      \
            (type(num)'('1) < 0) ?  /* Checks that type is signed */           \
                T'(signed'({signed'(num) >>> (-$right(num) - -$right(T)) })) : \
                T'(        {       (num) >>  (-$right(num) - -$right(T)) })  : \
            (T'(num) << (-$right(T) - -$right(num)))                           \
    })

`endif // FIXP_PKG_SVH
