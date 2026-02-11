`include "fixp_pkg.svh"

`default_nettype none

module line_height_calc
    import fixp_pkg::W_INT;
    import fixp_pkg::fixp_t;
    import fixp_pkg::sfixp_t;
#(
    parameter int unsigned        W_X_POS      = 10,
    parameter int unsigned        W_Y_POS      = 9,
    parameter logic [W_X_POS-1:0] FRAME_WIDTH  = 640,
    parameter logic [W_Y_POS-1:0] FRAME_HEIGHT = 480
) (
    input  var logic               clk,
    input  var logic               rst,

    input  var logic               start_i,
    // Horizontal position of input pixel on the screen
    input  var logic [W_X_POS-1:0] px_x_i,

    // Camera coordinates
    input  var fixp_t              pos_x_i,
    input  var fixp_t              pos_y_i,
    // Camera direction
    input  var sfixp_t             dir_x_i,
    input  var sfixp_t             dir_y_i,
    // Camera plane
    input  var sfixp_t             plane_x_i,
    input  var sfixp_t             plane_y_i,

    // Map coordinates to check for a wall
    output var logic [W_INT-1:0]   lookup_map_x_o,
    output var logic [W_INT-1:0]   lookup_map_y_o,
    input  var logic               wall_hit_i,

    output var logic               done_o,
    output var logic [W_Y_POS-1:0] height_o,
    output var logic               ray_hit_side_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam fixp_t RAY_STEP  = `REAL_TO_FIXP(fixp_t, 2.0 / real'(FRAME_WIDTH));
localparam fixp_t DELTA_MAX = `INT_TO_FIXP(fixp_t, W_INT'(2**(W_INT-1) - 1));

// ----------------------------------------------------------------------------
// Elaboration checks
// ----------------------------------------------------------------------------

if (RAY_STEP == 0) begin : gen_elab_check
    $error("Incompatible input parameters: RAY_STEP is 0.");
    $error("Either increase W_FRAC or decrease FRAME_WIDTH");
end

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef enum logic [3:0] {
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
    ST_CALC_LINE_HEIGHT
} state_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

// Ray direction for current screen pixel
logic   [W_X_POS-1:0] px_x;
sfixp_t               ray_x;
sfixp_t               dir_x;
sfixp_t               dir_y;
sfixp_t               plane_x;
sfixp_t               plane_y;
sfixp_t               ray_dir_x;
sfixp_t               ray_dir_y;

// Inversion module
fixp_t                inv_num_in;
fixp_t                inv_num_out;
logic                 inv_start_next;
logic                 inv_start_ff;
logic                 inv_done;

// Ray distance in one map cell
fixp_t                delta_dist_x_next;
fixp_t                delta_dist_x_ff;
fixp_t                delta_dist_y_next;
fixp_t                delta_dist_y_ff;

// Distance from the point to the cell border
fixp_t                side_perp_dist_x_next;
fixp_t                side_perp_dist_x_ff;
fixp_t                side_perp_dist_y_next;
fixp_t                side_perp_dist_y_ff;

// DDA
fixp_t                init_side_dist_x;
fixp_t                init_side_dist_y;
fixp_t                dda_side_dist_x;
fixp_t                dda_side_dist_y;
logic                 dda_start;
logic                 dda_done;

// Ray step direction for DDA
logic                 step_x_next;
logic                 step_x_ff;
logic                 step_y_next;
logic                 step_y_ff;

// Distance from the wall to the camera plane
fixp_t                perp_wall_dist_next;
fixp_t                perp_wall_dist_ff;
fixp_t                inv_perp_wall_dist_next;
fixp_t                inv_perp_wall_dist_ff;

// Camera position
fixp_t                pos_x;
fixp_t                pos_y;
logic [W_INT-1:0]     init_map_x;
logic [W_INT-1:0]     init_map_y;

// FSM
state_t               state;
state_t               next_state;

// ----------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------

always_comb begin
    next_state = state;

    unique case (state)
        ST_IDLE:              if (start_i)  next_state = ST_CALC_RAY_X;
        ST_CALC_RAY_X:                      next_state = ST_CALC_RAY_DIR;
        ST_CALC_RAY_DIR:                    next_state = ST_CALC_DELTA_DIST_X;
        ST_CALC_DELTA_DIST_X: if (inv_done) next_state = ST_CALC_DELTA_DIST_Y;
        ST_CALC_DELTA_DIST_Y: if (inv_done) next_state = ST_CALC_PERP_DIST;
        ST_CALC_PERP_DIST:                  next_state = ST_CALC_SIDE_DIST;
        ST_CALC_SIDE_DIST:                  next_state = ST_RUN_DDA;
        ST_RUN_DDA:           if (dda_done) next_state = ST_CALC_WALL_DIST;
        ST_CALC_WALL_DIST:                  next_state = ST_INV_WALL_DIST;
        ST_INV_WALL_DIST:     if (inv_done) next_state = ST_CALC_LINE_HEIGHT;
        ST_CALC_LINE_HEIGHT:                next_state = ST_IDLE;
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
        px_x       <= px_x_i;

        pos_x      <= pos_x_i;
        pos_y      <= pos_y_i;

        init_map_x <= pos_x_i[W_INT-1:0];
        init_map_y <= pos_y_i[W_INT-1:0];

        dir_x      <= dir_x_i;
        dir_y      <= dir_y_i;

        plane_x    <= plane_x_i;
        plane_y    <= plane_y_i;
    end
end

// ----------------------------------------------------------------------------
// Calculate ray_x
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (state == ST_CALC_RAY_X)
        // (px_x * 2 / FRAME_WIDTH) - 1, gets [-1:1) range
        // 2 / FRAME_WIDTH is precalculated in RAY_STEP
        ray_x <= sfixp_t'((fixp_t'(px_x) * RAY_STEP) - `INT_TO_FIXP(fixp_t, 1));

// ----------------------------------------------------------------------------
// Calculate ray dir x/y components
// ----------------------------------------------------------------------------

always_ff @(posedge clk) begin
    if (state == ST_CALC_RAY_DIR) begin
        ray_dir_x <= dir_x + `FIXP_MULT(sfixp_t, plane_x, ray_x);
        ray_dir_y <= dir_y + `FIXP_MULT(sfixp_t, plane_y, ray_x);
    end
end

// ----------------------------------------------------------------------------
// Calculate relative ray distance of one cell step
// ----------------------------------------------------------------------------

newton_inv newton_inv (
    .clk     (clk         ),
    .rst     (rst         ),
    .start_i (inv_start_ff),
    .num_i   (inv_num_in  ),
    .done_o  (inv_done    ),
    .num_o   (inv_num_out )
);

always_comb begin
    inv_start_next = '0;

    unique0 case (state)
        ST_CALC_RAY_DIR:                    inv_start_next = '1;
        ST_CALC_DELTA_DIST_X: if (inv_done) inv_start_next = '1;
        ST_CALC_WALL_DIST:                  inv_start_next = '1;
    endcase
end

always_ff @(posedge clk)
    if (rst)
        inv_start_ff <= '0;
    else
        inv_start_ff <= inv_start_next;

always_comb begin
    inv_num_in              = '0;
    delta_dist_x_next       = delta_dist_x_ff;
    delta_dist_y_next       = delta_dist_y_ff;
    inv_perp_wall_dist_next = inv_perp_wall_dist_ff;

    if (state == ST_CALC_DELTA_DIST_X) begin
        inv_num_in = `FIXP_ABS(ray_dir_x, fixp_t);

        if (inv_done)
            delta_dist_x_next = (ray_dir_x == '0) ? DELTA_MAX : inv_num_out;
    end

    if (state == ST_CALC_DELTA_DIST_Y) begin
        inv_num_in = `FIXP_ABS(ray_dir_y, fixp_t);

        if (inv_done)
            delta_dist_y_next = (ray_dir_y == '0) ? DELTA_MAX : inv_num_out;
    end

    if (state == ST_INV_WALL_DIST) begin
        inv_num_in = perp_wall_dist_ff;

        if (inv_done)
            inv_perp_wall_dist_next = (perp_wall_dist_ff == '0) ? '1 : inv_num_out;
    end

end

always_ff @(posedge clk) begin
    delta_dist_x_ff <= delta_dist_x_next;
    delta_dist_y_ff <= delta_dist_y_next;
end

// ----------------------------------------------------------------------------
// Calculation of distance between camera point and cell border in the direction
// of the ray
// ----------------------------------------------------------------------------

always_comb begin
    side_perp_dist_x_next = side_perp_dist_x_ff;
    side_perp_dist_y_next = side_perp_dist_y_ff;
    step_x_next           = step_x_ff;
    step_y_next           = step_y_ff;

    if (state == ST_CALC_PERP_DIST) begin

        if (ray_dir_x > 0) begin
            step_x_next           = '1;
            side_perp_dist_x_next = `INT_TO_FIXP(fixp_t, init_map_x + 1'b1) - pos_x;
        end else begin
            step_x_next           = '0;
            side_perp_dist_x_next = pos_x - `INT_TO_FIXP(fixp_t, init_map_x);
        end

        if (ray_dir_y > 0) begin
            step_y_next           = '1;
            side_perp_dist_y_next = `INT_TO_FIXP(fixp_t, init_map_y + 1'b1) - pos_y;
        end else begin
            step_y_next           = '0;
            side_perp_dist_y_next = pos_y - `INT_TO_FIXP(fixp_t, init_map_y);
        end

    end
end

always_ff @(posedge clk) begin
    side_perp_dist_x_ff <= side_perp_dist_x_next;
    side_perp_dist_y_ff <= side_perp_dist_y_next;
    step_x_ff           <= step_x_next;
    step_y_ff           <= step_y_next;
end

// ----------------------------------------------------------------------------
// Scale perpendicular distance to ray distance
// ----------------------------------------------------------------------------

always_ff @(posedge clk) begin
    if (state == ST_CALC_SIDE_DIST) begin
        init_side_dist_x <= `FIXP_MULT(fixp_t, side_perp_dist_x_ff, delta_dist_x_ff);
        init_side_dist_y <= `FIXP_MULT(fixp_t, side_perp_dist_y_ff, delta_dist_y_ff);
    end
end

// ----------------------------------------------------------------------------
// Calculate ray distance
// ----------------------------------------------------------------------------

dda dda (
    .clk                (clk             ),
    .rst                (rst             ),

    .start_i            (dda_start       ),

    .init_map_x_i       (init_map_x      ),
    .init_map_y_i       (init_map_y      ),
    .map_x_o            (lookup_map_x_o  ),
    .map_y_o            (lookup_map_y_o  ),
    .step_x_i           (step_x_ff       ),
    .step_y_i           (step_y_ff       ),
    .wall_hit_i         (wall_hit_i      ),

    .init_side_dist_x_i (init_side_dist_x),
    .init_side_dist_y_i (init_side_dist_y),
    .side_dist_x_o      (dda_side_dist_x ),
    .side_dist_y_o      (dda_side_dist_y ),
    .delta_dist_x_i     (delta_dist_x_ff ),
    .delta_dist_y_i     (delta_dist_y_ff ),
    .hit_side_o         (ray_hit_side_o  ),
    .done_o             (dda_done        )
);

always_ff @(posedge clk)
    if (rst)
        dda_start <= '0;
    else
        dda_start <= state == ST_CALC_SIDE_DIST;

always_comb begin
    perp_wall_dist_next = perp_wall_dist_ff;

    if (state == ST_CALC_WALL_DIST) begin
        if (ray_hit_side_o)
            perp_wall_dist_next = dda_side_dist_y - delta_dist_y_ff;
        else
            perp_wall_dist_next = dda_side_dist_x - delta_dist_x_ff;
    end
end

always_ff @(posedge clk)
    perp_wall_dist_ff <= perp_wall_dist_next;

// ----------------------------------------------------------------------------
// Calculate wall height
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (state == ST_INV_WALL_DIST && inv_done)
        inv_perp_wall_dist_ff <= inv_perp_wall_dist_next;

always_ff @(posedge clk)
    if (state == ST_CALC_LINE_HEIGHT)
        if (inv_perp_wall_dist_ff[W_INT-1:0] == '0)
            height_o <= W_Y_POS'(`FIXP_MULT(fixp_t, fixp_t'(FRAME_HEIGHT), inv_perp_wall_dist_ff));
        else
            height_o <= FRAME_HEIGHT;

always_ff @(posedge clk)
    if (rst)
        done_o <= '0;
    else
        done_o <= state == ST_CALC_LINE_HEIGHT;

endmodule

`resetall
