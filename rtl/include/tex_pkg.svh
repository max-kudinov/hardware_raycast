`ifndef TEX_PKG_SVH
`define TEX_PKG_SVH

`include "fixp_pkg.svh"
`include "dvi_pkg.svh"

package tex_pkg;

    import dvi_pkg::FRAME_HEIGHT;

    localparam int unsigned TEX_SIDE         = 32;
    localparam int unsigned W_PX_CODE        = 4;
    localparam int unsigned NUM_TEX          = 7;
    localparam int unsigned RECODE_LUT_LEN   = 15;
    localparam int unsigned W_TEX_SIDE       = $clog2(TEX_SIDE);
    localparam int unsigned W_NUM_TEX        = $clog2(NUM_TEX);

    localparam int unsigned TEX_ZOOM_W_INT   = 4;
    localparam int unsigned TEX_ZOOM_W_FRAC  = 4;

    localparam int unsigned TEX_STEP_W_INT   = 3;
    localparam int unsigned TEX_STEP_W_FRAC  = 12;

    localparam int unsigned TEX_ALIGN_W_INT  = W_TEX_SIDE + 1;
    localparam int unsigned TEX_ALIGN_W_FRAC = TEX_STEP_W_FRAC;

    typedef logic [TEX_STEP_W_INT-1:-signed'(TEX_STEP_W_FRAC)]   tex_step_fixp_t;
    typedef logic [TEX_ZOOM_W_INT-1:-signed'(TEX_ZOOM_W_FRAC)]   tex_zoom_fixp_t;
    typedef logic [TEX_ALIGN_W_INT-1:-signed'(TEX_ALIGN_W_FRAC)] align_fixp_t;

    localparam tex_step_fixp_t TEX_SCALE = `REAL_TO_FIXP(
        real'(TEX_SIDE) / FRAME_HEIGHT, tex_step_fixp_t
    );

endpackage : tex_pkg

`endif // TEX_PKG_SVH
