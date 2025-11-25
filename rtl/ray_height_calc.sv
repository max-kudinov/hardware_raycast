`default_nettype none

module ray_height_calc #(
    parameter W_INT       = 8,
    parameter W_FRAC      = 8,
    parameter W_X_POS     = 8,
    parameter W_HEIGHT    = 8,
    parameter FRAME_WIDTH = 640
) (
    input  var logic                          clk,
    input  var logic                          rst,

    input  var logic                          start_i,
    input  var logic        [W_X_POS-1:0]     x_pos_i,

    input  var logic signed [W_INT-1:-W_FRAC] dir_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] dir_y_i,
    input  var logic signed [W_INT-1:-W_FRAC] plane_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] plane_y_i,

    output var logic                          done_o,
    output var logic        [W_HEIGHT-1:0]    height_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam RAY_STEP = int'(2.0 / FRAME_WIDTH * (2**W_FRAC));

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic inv_done;
logic dda_done;
logic wall_dist_zero;

typedef enum {
    ST_IDLE,
    ST_CALC_RAY_X,
    ST_CALC_RAY_DIR,
    ST_CALC_DELTA_DIST_X,
    ST_CALC_DELTA_DIST_Y,
    ST_CALC_PERP_DIST,
    ST_CALC_SIDE_DIST,
    ST_RUN_DDA,
    ST_CALC_WALL_DIST,
    ST_INV_WALL_DIST,
    ST_CALC_LINE_HEIGHT,
    ST_RES_OUT
} state_t;

state_t state, next_state;

// ----------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------

always_comb begin
    next_state = state;

    case (state)
        ST_IDLE:              if (start_i)        next_state = ST_CALC_RAY_X;
        ST_CALC_RAY_X:                            next_state = ST_CALC_RAY_DIR;
        ST_CALC_RAY_DIR:                          next_state = ST_CALC_DELTA_DIST_X;
        ST_CALC_DELTA_DIST_X: if (inv_done)       next_state = ST_CALC_DELTA_DIST_Y;
        ST_CALC_DELTA_DIST_Y: if (inv_done)       next_state = ST_CALC_PERP_DIST;
        ST_CALC_PERP_DIST:                        next_state = ST_CALC_SIDE_DIST;
        ST_CALC_SIDE_DIST:                        next_state = ST_RUN_DDA;
        ST_RUN_DDA:           if (dda_done)       next_state = ST_CALC_WALL_DIST;
        ST_CALC_WALL_DIST:    if (wall_dist_zero) next_state = ST_RES_OUT;
                              else                next_state = ST_INV_WALL_DIST;
        ST_INV_WALL_DIST:     if (inv_done)       next_state = ST_CALC_LINE_HEIGHT;
        ST_CALC_LINE_HEIGHT:                      next_state = ST_RES_OUT;
        ST_RES_OUT:           if (start_i)        next_state = ST_CALC_RAY_X;
                              else                next_state = ST_IDLE;
    endcase
end

always_ff @(posedge clk)
    if (rst)
        state <= ST_IDLE;
    else
        state <= next_state;

endmodule
