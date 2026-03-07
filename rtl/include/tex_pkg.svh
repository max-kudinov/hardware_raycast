`ifndef TEX_PKG_SVH
`define TEX_PKG_SVH

`include "fixp_pkg.svh"
`include "dvi_pkg.svh"

package tex_pkg;

    import dvi_pkg::FRAME_HEIGHT;

    localparam int unsigned TEX_SIDE         = 32;
    localparam int unsigned W_TEX_SIDE       = $clog2(TEX_SIDE);

    localparam int unsigned TEX_POS_W_INT    = 5;
    localparam int unsigned TEX_POS_W_FRAC   = 4;

    localparam int unsigned TEX_START_W_INT  = 4;
    localparam int unsigned TEX_START_W_FRAC = 4;

    localparam int unsigned TEX_STEP_W_INT   = 3;
    localparam int unsigned TEX_STEP_W_FRAC  = 12;

    localparam int unsigned TEX_SCALE_W_INT  = 0;
    localparam int unsigned TEX_SCALE_W_FRAC = 8;

    typedef logic [TEX_POS_W_INT-1:-signed'(TEX_POS_W_FRAC)]     tex_pos_fixp_t;
    typedef logic [TEX_STEP_W_INT-1:-signed'(TEX_STEP_W_FRAC)]   tex_step_fixp_t;
    typedef logic [TEX_START_W_INT-1:-signed'(TEX_START_W_FRAC)] tex_start_fixp_t;
    typedef logic [TEX_SCALE_W_INT-1:-signed'(TEX_SCALE_W_FRAC)] tex_scale_fixp_t;

    localparam tex_scale_fixp_t TEX_SCALE = `REAL_TO_FIXP(
        real'(TEX_SIDE) / FRAME_HEIGHT, tex_scale_fixp_t
    );

endpackage : tex_pkg

`endif // TEX_PKG_SVH
