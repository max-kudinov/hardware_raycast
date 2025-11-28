`include "fixedpoint.svh"

`default_nettype none

module line_height_calc
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
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

import fixedpoint::fixp_mult;
import fixedpoint::fixp_abs;

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam RAY_STEP = int'(2.0 / FRAME_WIDTH * (2**W_FRAC));

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic signed [W_INT-1:-W_FRAC] ray_x;
logic [W_INT-1:-W_FRAC] inv_num_in;
logic [W_INT-1:-W_FRAC] inv_num_out;
logic inv_start;
logic inv_done;
logic inv_busy;
logic dda_done;
logic wall_dist_zero;

logic [W_INT-1:-W_FRAC] delta_dist_x_next;
logic [W_INT-1:-W_FRAC] delta_dist_x_ff;
logic [W_INT-1:-W_FRAC] delta_dist_y_next;
logic [W_INT-1:-W_FRAC] delta_dist_y_ff;

logic        [W_X_POS-1:0]     x_pos;
logic signed [W_INT-1:-W_FRAC] dir_x;
logic signed [W_INT-1:-W_FRAC] dir_y;
logic signed [W_INT-1:-W_FRAC] ray_dir_x;
logic signed [W_INT-1:-W_FRAC] ray_dir_y;
logic signed [W_INT-1:-W_FRAC] plane_x;
logic signed [W_INT-1:-W_FRAC] plane_y;

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

// ----------------------------------------------------------------------------
// Register input signals
// ----------------------------------------------------------------------------

always_ff @(posedge clk) begin
    if (state == ST_IDLE && start_i) begin
        x_pos   <= x_pos_i;

        dir_x   <= dir_x_i;
        dir_y   <= dir_y_i;

        plane_x <= plane_x_i;
        plane_y <= plane_y_i;
    end
end

// ----------------------------------------------------------------------------
// Calculate ray_x
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (state == ST_CALC_RAY_X)
        ray_x <= (W_INT + W_FRAC)'(x_pos * RAY_STEP) - 1'b1;

// ----------------------------------------------------------------------------
// Calculate ray dir x/y components
// ----------------------------------------------------------------------------

always_ff @(posedge clk) begin
    if (state == ST_CALC_RAY_DIR) begin
        ray_dir_x <= dir_x + fixp_mult(plane_x, ray_x);
        ray_dir_y <= dir_y + fixp_mult(plane_y, ray_x);
    end
end

// ----------------------------------------------------------------------------
// Calculate relative ray distance of one cell step
// ----------------------------------------------------------------------------

newton_inv newton_inv (
    .clk     (clk        ),
    .rst     (rst        ),
    .start_i (inv_start  ),
    .num_i   (inv_num_in ),
    .done_o  (inv_done   ),
    .busy_o  (inv_busy   ),
    .num_o   (inv_num_out)
);

always_comb begin
    inv_start         = '0;
    inv_num_in        = '0;
    delta_dist_x_next = delta_dist_x_ff;
    delta_dist_y_next = delta_dist_y_ff;

    if (state == ST_CALC_DELTA_DIST_X) begin
        inv_num_in = fixp_abs(ray_dir_x);

        if (!inv_busy && !inv_done)
            inv_start = '1;

        if (inv_done)
            delta_dist_x_next = (ray_dir_x == '0) ? '1 : inv_num_out;
    end

    if (state == ST_CALC_DELTA_DIST_Y) begin
        inv_num_in = fixp_abs(ray_dir_y);

        if (!inv_busy && !inv_done)
            inv_start = '1;

        if (inv_done)
            delta_dist_y_next = (ray_dir_y == '0) ? '1 : inv_num_out;
    end

end

always_ff @(posedge clk) begin
    delta_dist_x_ff <= delta_dist_x_next;
    delta_dist_y_ff <= delta_dist_y_next;
end

endmodule
