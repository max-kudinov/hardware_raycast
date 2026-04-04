`include "fixp_pkg.svh"
`include "tex_pkg.svh"
`include "dvi_pkg.svh"

`default_nettype none

module column_calc
    import fixp_pkg::*;
    import tex_pkg::*;
    import dvi_pkg::W_H_RES;
    import dvi_pkg::W_V_RES;
    import dvi_pkg::FRAME_WIDTH;
    import dvi_pkg::FRAME_HEIGHT;
(
    input  var logic                  clk,
    input  var logic                  rst,

    input  var logic                  start_i,
    // Horizontal position of input pixel on the screen
    input  var logic [W_H_RES-1:0]    px_x_i,

    // Camera coordinates
    input  var pos_fixp_t             pos_x_i,
    input  var pos_fixp_t             pos_y_i,
    // Camera direction
    input  var ray_fixp_t             dir_x_i,
    input  var ray_fixp_t             dir_y_i,
    // Camera plane
    input  var ray_fixp_t             plane_x_i,
    input  var ray_fixp_t             plane_y_i,

    // Map coordinates to check for a wall
    output var logic [POS_W_INT-1:0]  lookup_map_x_o,
    output var logic [POS_W_INT-1:0]  lookup_map_y_o,
    input  var logic [W_NUM_TEX-1:0]  texture_i,

    output var logic                  done_o,
    output var logic [W_NUM_TEX-1:0]  texture_o,
    output var logic                  tex_shade_o,
    output var logic [W_TEX_SIDE-1:0] tex_x_o,
    output var tex_step_fixp_t        tex_step_o,
    output var logic [W_V_RES-1:0]    tex_height_o
);

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
} main_state_t;

typedef enum logic [2:0] {
    ST_TEX_IDLE,
    ST_TEX_STEP,
    ST_TEX_DIST,
    ST_TEX_X,
    ST_TEX_MIRROR
} tex_state_t;

typedef logic [POS_W_INT-1:-signed'(TEX_STEP_W_FRAC)] ext_step_fixp_t;
typedef logic [-1:-signed'(POS_W_FRAC)]               pos_frac_fixp_t;

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned    MAX_DIST      = 2**(EXT_POS_W_INT) - 1;
localparam ext_pos_fixp_t  FIXP_MAX_DIST = `INT_TO_FIXP(MAX_DIST, ext_pos_fixp_t);
localparam inv_fixp_t      FIXP_INV_MIN  = `REAL_TO_FIXP(1.0 / MAX_DIST, inv_fixp_t);
localparam ray_fixp_t      RAY_STEP      = `REAL_TO_FIXP(2.0 / real'(FRAME_WIDTH), ray_fixp_t);
localparam ext_step_fixp_t TEX_SCALE_EXT = `FIXP_CAST(TEX_SCALE, ext_step_fixp_t);

// ----------------------------------------------------------------------------
// Elaboration checks
// ----------------------------------------------------------------------------

if (RAY_STEP == 0) begin : gen_elab_check
    $error("Incompatible input parameters: RAY_STEP is 0.");
    $error("Either increase W_FRAC or decrease FRAME_WIDTH");
end

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

// Ray direction for current screen pixel
logic [W_H_RES-1:0]    px_x;
ray_fixp_t             ray_x;
ray_fixp_t             dir_x;
ray_fixp_t             dir_y;
ray_fixp_t             plane_x;
ray_fixp_t             plane_y;
ray_fixp_t             ray_dir_x;
ray_fixp_t             ray_dir_y;

// Inversion module
inv_fixp_t             inv_num_in;
// Not all bits are used
// verilator lint_off UNUSEDSIGNAL
inv_fixp_t             inv_num_out;
// verilator lint_on UNUSEDSIGNAL
logic                  inv_start_next;
logic                  inv_start_ff;
logic                  inv_done;

// Ray distance between parallel coordinate lines
ext_pos_fixp_t         delta_dist_x_next;
ext_pos_fixp_t         delta_dist_x_ff;
ext_pos_fixp_t         delta_dist_y_next;
ext_pos_fixp_t         delta_dist_y_ff;

// Distance from the point to the cell border
side_fixp_t            side_dist_x_next;
side_fixp_t            side_dist_x_ff;
side_fixp_t            side_dist_y_next;
side_fixp_t            side_dist_y_ff;
pos_fixp_t             cell_dist;

// DDA
ext_pos_fixp_t         init_side_dist_x;
ext_pos_fixp_t         init_side_dist_y;
ext_pos_fixp_t         dda_side_dist_x;
ext_pos_fixp_t         dda_side_dist_y;
logic                  dda_start;
logic                  dda_done;
logic                  dda_wall_hit;

// Ray step direction for DDA
logic                  step_x_next;
logic                  step_x_ff;
logic                  step_y_next;
logic                  step_y_ff;

// Distance from the wall to the camera plane
pos_fixp_t             wall_dist_next;
pos_fixp_t             wall_dist_ff;
inv_dist_fixp_t        inv_wall_dist_next;
inv_dist_fixp_t        inv_wall_dist_ff;

// Camera position
pos_fixp_t             pos_x;
pos_fixp_t             pos_y;
logic [POS_W_INT-1:0]  init_map_x;
logic [POS_W_INT-1:0]  init_map_y;

// Texture data
ext_step_fixp_t        step_wall_dist;
ext_step_fixp_t        ext_tex_step;
tex_step_fixp_t        tex_step_next;

// Texture x coordinate calculation
proj_fixp_t            ext_ray_dir;
proj_fixp_t            ext_dist;
pos_frac_fixp_t        proj_frac_next;
pos_frac_fixp_t        proj_frac_ff;

// verilator lint_off UNUSEDSIGNAL
logic [-1:-POS_W_FRAC] tex_x_frac;  // MSB bits are unused
// verilator lint_on UNUSEDSIGNAL
logic [W_TEX_SIDE-1:0] tex_x_next;

// FSMs
main_state_t           main_state;
main_state_t           main_next_state;
tex_state_t            tex_state;
tex_state_t            tex_next_state;

// ----------------------------------------------------------------------------
// FSMs
// ----------------------------------------------------------------------------

always_comb begin
    main_next_state = main_state;

    unique case (main_state)
        ST_IDLE:              if (start_i)  main_next_state = ST_CALC_RAY_X;
        ST_CALC_RAY_X:                      main_next_state = ST_CALC_RAY_DIR;
        ST_CALC_RAY_DIR:                    main_next_state = ST_CALC_DELTA_DIST_X;
        ST_CALC_DELTA_DIST_X: if (inv_done) main_next_state = ST_CALC_DELTA_DIST_Y;
        ST_CALC_DELTA_DIST_Y: if (inv_done) main_next_state = ST_CALC_PERP_DIST;
        ST_CALC_PERP_DIST:                  main_next_state = ST_CALC_SIDE_DIST;
        ST_CALC_SIDE_DIST:                  main_next_state = ST_RUN_DDA;
        ST_RUN_DDA:           if (dda_done) main_next_state = ST_CALC_WALL_DIST;
        ST_CALC_WALL_DIST:                  main_next_state = ST_INV_WALL_DIST;
        ST_INV_WALL_DIST:     if (inv_done) main_next_state = ST_CALC_LINE_HEIGHT;
        ST_CALC_LINE_HEIGHT:                main_next_state = ST_IDLE;
    endcase
end

always_ff @(posedge clk)
    if (rst)
        main_state <= ST_IDLE;
    else
        main_state <= main_next_state;


always_comb begin
    tex_next_state = tex_state;

    unique case (tex_state)
        ST_TEX_IDLE: if (main_state == ST_CALC_WALL_DIST)
                         tex_next_state = ST_TEX_STEP;

        ST_TEX_STEP:     tex_next_state = ST_TEX_DIST;
        ST_TEX_DIST:     tex_next_state = ST_TEX_X;
        ST_TEX_X:        tex_next_state = ST_TEX_MIRROR;
        ST_TEX_MIRROR:   tex_next_state = ST_TEX_IDLE;
    endcase
end


always_ff @(posedge clk)
    if (rst)
        tex_state <= ST_TEX_IDLE;
    else
        tex_state <= tex_next_state;

// ----------------------------------------------------------------------------
// Register input signals
// ----------------------------------------------------------------------------

always_ff @(posedge clk) begin
    if (main_state == ST_IDLE && start_i) begin
        px_x       <= px_x_i;

        pos_x      <= pos_x_i;
        pos_y      <= pos_y_i;

        init_map_x <= pos_x_i[POS_W_INT-1:0];
        init_map_y <= pos_y_i[POS_W_INT-1:0];

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
    if (main_state == ST_CALC_RAY_X)
        // (px_x * 2 / FRAME_WIDTH) - 1, gets [-1:1) range
        // 2 / FRAME_WIDTH is precalculated in RAY_STEP
        ray_x <= (ray_fixp_t'(px_x) * RAY_STEP) - `INT_TO_FIXP(1, ray_fixp_t);

// ----------------------------------------------------------------------------
// Calculate ray dir x/y components
// ----------------------------------------------------------------------------

always_ff @(posedge clk) begin
    if (main_state == ST_CALC_RAY_DIR) begin
        ray_dir_x <= dir_x + `FIXP_MULT(plane_x, ray_x);
        ray_dir_y <= dir_y + `FIXP_MULT(plane_y, ray_x);
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

    unique0 case (main_state)
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
    inv_num_in         = '0;
    delta_dist_x_next  = delta_dist_x_ff;
    delta_dist_y_next  = delta_dist_y_ff;
    inv_wall_dist_next = inv_wall_dist_ff;

    if (main_state == ST_CALC_DELTA_DIST_X) begin
        inv_num_in = `FIXP_CAST(`FIXP_ABS(ray_dir_x), inv_fixp_t);

        if (inv_done)
            delta_dist_x_next = (inv_num_in < FIXP_INV_MIN) ?
                                 FIXP_MAX_DIST :
                                `FIXP_CAST(inv_num_out, ext_pos_fixp_t);
    end

    if (main_state == ST_CALC_DELTA_DIST_Y) begin
        inv_num_in = `FIXP_CAST(`FIXP_ABS(ray_dir_y), inv_fixp_t);

        if (inv_done)
            delta_dist_y_next = (inv_num_in < FIXP_INV_MIN) ?
                                  FIXP_MAX_DIST :
                                 `FIXP_CAST(inv_num_out, ext_pos_fixp_t);
    end

    if (main_state == ST_INV_WALL_DIST) begin
        inv_num_in = `FIXP_CAST(wall_dist_ff, inv_fixp_t);

        if (inv_done)
            inv_wall_dist_next = `FIXP_CAST(inv_num_out, inv_dist_fixp_t);
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
    side_dist_x_next = side_dist_x_ff;
    side_dist_y_next = side_dist_y_ff;
    step_x_next      = step_x_ff;
    step_y_next      = step_y_ff;
    cell_dist        = '0;

    if (main_state == ST_CALC_PERP_DIST) begin

        if (ray_dir_x > 0) begin
            step_x_next      = '1;
            cell_dist        = `INT_TO_FIXP(init_map_x + 1'b1, pos_fixp_t) - pos_x;
            side_dist_x_next = `FIXP_CAST(cell_dist, side_fixp_t);
        end else begin
            step_x_next      = '0;
            cell_dist        = pos_x - `INT_TO_FIXP(init_map_x, pos_fixp_t);
            side_dist_x_next = `FIXP_CAST(cell_dist, side_fixp_t);
        end

        if (ray_dir_y > 0) begin
            step_y_next      = '1;
            cell_dist        = `INT_TO_FIXP(init_map_y + 1'b1, pos_fixp_t) - pos_y;
            side_dist_y_next = `FIXP_CAST(cell_dist, side_fixp_t);
        end else begin
            step_y_next      = '0;
            cell_dist        = pos_y - `INT_TO_FIXP(init_map_y, pos_fixp_t);
            side_dist_y_next = `FIXP_CAST(cell_dist, side_fixp_t);
        end

    end
end

always_ff @(posedge clk) begin
    side_dist_x_ff <= side_dist_x_next;
    side_dist_y_ff <= side_dist_y_next;
    step_x_ff      <= step_x_next;
    step_y_ff      <= step_y_next;
end

// ----------------------------------------------------------------------------
// Scale perpendicular distance to ray distance
// ----------------------------------------------------------------------------

always_ff @(posedge clk) begin
    if (main_state == ST_CALC_SIDE_DIST) begin
        init_side_dist_x <= `FIXP_MULT(
            `FIXP_CAST(side_dist_x_ff, ext_pos_fixp_t),
            delta_dist_x_ff
        );

        init_side_dist_y <= `FIXP_MULT(
            `FIXP_CAST(side_dist_y_ff, ext_pos_fixp_t),
            delta_dist_y_ff
        );
    end
end

// ----------------------------------------------------------------------------
// Calculate ray distance
// ----------------------------------------------------------------------------

dda #(
    .FIXP_MAX_DIST (FIXP_MAX_DIST)
) dda (
    .clk                (clk             ),
    .rst                (rst             ),

    .start_i            (dda_start       ),

    .init_map_x_i       (init_map_x      ),
    .init_map_y_i       (init_map_y      ),
    .map_x_o            (lookup_map_x_o  ),
    .map_y_o            (lookup_map_y_o  ),
    .step_x_i           (step_x_ff       ),
    .step_y_i           (step_y_ff       ),
    .wall_hit_i         (dda_wall_hit    ),

    .init_side_dist_x_i (init_side_dist_x),
    .init_side_dist_y_i (init_side_dist_y),
    .side_dist_x_o      (dda_side_dist_x ),
    .side_dist_y_o      (dda_side_dist_y ),
    .delta_dist_x_i     (delta_dist_x_ff ),
    .delta_dist_y_i     (delta_dist_y_ff ),
    .hit_side_o         (tex_shade_o     ),
    .done_o             (dda_done        )
);

assign dda_wall_hit = texture_i != '0;

always_ff @(posedge clk)
    if (rst)
        dda_start <= '0;
    else
        dda_start <= main_state == ST_CALC_SIDE_DIST;

// texture_i == 0 means no texture, and texture_o is used for ROM indexing, so
// we subtract 1 to start indexing from 0 (0 to 6 instead of 1 to 7)
always_ff @(posedge clk)
    if (dda_done)
        texture_o <= texture_i - 1'b1;

always_comb begin
    wall_dist_next = wall_dist_ff;

    if (main_state == ST_CALC_WALL_DIST) begin
        if (tex_shade_o)
            wall_dist_next = pos_fixp_t'(dda_side_dist_y - delta_dist_y_ff);
        else
            wall_dist_next = pos_fixp_t'(dda_side_dist_x - delta_dist_x_ff);
    end
end

always_ff @(posedge clk)
    wall_dist_ff <= wall_dist_next;

// ----------------------------------------------------------------------------
// Calculate step for going through texture pixels
// ----------------------------------------------------------------------------

always_comb begin
    tex_step_next  = tex_step_o;
    ext_tex_step   = '0;
    step_wall_dist = `FIXP_CAST(wall_dist_ff, ext_step_fixp_t);

    if (tex_state == ST_TEX_STEP) begin
        ext_tex_step  = `FIXP_MULT(step_wall_dist, TEX_SCALE_EXT);
        tex_step_next = `FIXP_CAST(ext_tex_step, tex_step_fixp_t);
    end
end

always_ff @(posedge clk)
    tex_step_o <= tex_step_next;

// ----------------------------------------------------------------------------
// Calculate projection distance between player point and the point where ray
// hits the wall
// ----------------------------------------------------------------------------

always_comb begin
    proj_frac_next = proj_frac_ff;
    ext_ray_dir    = '0;
    ext_dist       = `FIXP_CAST(wall_dist_ff, proj_fixp_t);

    if (tex_state == ST_TEX_DIST) begin
        if (tex_shade_o)
            ext_ray_dir = `FIXP_CAST(ray_dir_x, proj_fixp_t);
        else
            ext_ray_dir = `FIXP_CAST(ray_dir_y, proj_fixp_t);

        ext_dist        = `FIXP_MULT(ext_dist, ext_ray_dir);
        proj_frac_next  = unsigned'(ext_dist[-1:$right(pos_fixp_t)]);
    end
end

always_ff @(posedge clk)
    proj_frac_ff <= proj_frac_next;

// ----------------------------------------------------------------------------
// Calculate x coordinate where ray hits the texture
// ----------------------------------------------------------------------------

always_comb begin
    tex_x_frac = '0;
    tex_x_next = tex_x_o;

    if (tex_state == ST_TEX_X) begin
        if (tex_shade_o)
            tex_x_frac = pos_x[-1:$right(pos_x)] + proj_frac_ff;
        else
            tex_x_frac = pos_y[-1:$right(pos_y)] + proj_frac_ff;

        // Get highest W_TEX_SIDE bits and represent as integer, which is the
        // same as int(tex_x_frac << W_TEX_SIDE), or multiplication by TEX_SIDE.
        // Basically we scale 0-1 range to 0-(TEX_SIDE-1) range
        tex_x_next = tex_x_frac[-1 -: W_TEX_SIDE];
    end

    if (tex_state == ST_TEX_MIRROR) begin
        if (tex_shade_o && (ray_dir_y < 0))
            tex_x_next = W_TEX_SIDE'(TEX_SIDE - 1) - tex_x_o;
        if (!tex_shade_o && ray_dir_x > 0)
            tex_x_next = W_TEX_SIDE'(TEX_SIDE - 1) - tex_x_o;
    end
end

always_ff @(posedge clk)
    tex_x_o <= tex_x_next;

// ----------------------------------------------------------------------------
// Calculate texture height
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (main_state == ST_INV_WALL_DIST && inv_done)
        inv_wall_dist_ff <= inv_wall_dist_next;

always_ff @(posedge clk)
    if (main_state == ST_CALC_LINE_HEIGHT)
        if (wall_dist_ff[POS_W_INT-1:0] != '0)
            tex_height_o <= W_V_RES'(`FIXP_MULT(inv_dist_fixp_t'(FRAME_HEIGHT), inv_wall_dist_ff));
        else
            tex_height_o <= FRAME_HEIGHT;

always_ff @(posedge clk)
    if (rst)
        done_o <= '0;
    else
        done_o <= main_state == ST_CALC_LINE_HEIGHT;

endmodule

`resetall
