`include "fixp_pkg.svh"

`default_nettype none

module rotation
    import fixp_pkg::*;
#(
    parameter real ROTATION_SPEED = 0.4
) (
    input  var logic      clk,
    input  var logic      rst,

    input  var logic      key_rotate_left_i,
    input  var logic      key_rotate_right_i,

    input  var logic      update_start_i,

    // Camera direction
    output var ray_fixp_t dir_x_o,
    output var ray_fixp_t dir_y_o,
    // Camera plane
    output var ray_fixp_t plane_x_o,
    output var ray_fixp_t plane_y_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam real       PLANE_COEFF      = 0.66;
localparam real       START_DIR_X      = -1;
localparam real       START_DIR_Y      = 0;
localparam real       START_PLANE_X    = START_DIR_Y * PLANE_COEFF;
localparam real       START_PLANE_Y    = -START_DIR_X * PLANE_COEFF;

// Precalculated trig constants for rotation matrix
localparam ray_fixp_t FIXP_PLANE_COEFF = `REAL_TO_FIXP(PLANE_COEFF, ray_fixp_t);
localparam ray_fixp_t COS_ANGLE        = `REAL_TO_FIXP($cos( ROTATION_SPEED), ray_fixp_t);
localparam ray_fixp_t SIN_ANGLE        = `REAL_TO_FIXP($sin( ROTATION_SPEED), ray_fixp_t);
localparam ray_fixp_t COS_NEG_ANGLE    = `REAL_TO_FIXP($cos(-ROTATION_SPEED), ray_fixp_t);
localparam ray_fixp_t SIN_NEG_ANGLE    = `REAL_TO_FIXP($sin(-ROTATION_SPEED), ray_fixp_t);

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef enum logic [3:0] {
    ST_CALC_IDLE,
    ST_X_MULT_COS,
    ST_X_MULT_SIN,
    ST_X_SUB,
    ST_X_MULT_COEFF,
    ST_Y_MULT_SIN,
    ST_Y_MULT_COS,
    ST_Y_ADD,
    ST_Y_MULT_COEFF
} calc_state_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

ray_fixp_t   dir_x_next;
ray_fixp_t   dir_y_next;

ray_fixp_t   plane_x_next;
ray_fixp_t   plane_y_next;

ray_fixp_t   cur_cos;
ray_fixp_t   cur_sin;

ray_fixp_t   cos_mult_next;
ray_fixp_t   sin_mult_next;
ray_fixp_t   cos_mult_ff;
ray_fixp_t   sin_mult_ff;

ray_fixp_t   x_prev;
ray_fixp_t   y_prev;
ray_fixp_t   comp_new;

logic        update_enable;

calc_state_t calc_state;
calc_state_t calc_next_state;

// ----------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (rst)
        calc_state <= ST_CALC_IDLE;
    else
        calc_state <= calc_next_state;

always_comb begin
    calc_next_state = calc_state;

    unique case (calc_state)
        ST_CALC_IDLE:  if (update_start_i) calc_next_state = ST_X_MULT_COS;
        ST_X_MULT_COS:                     calc_next_state = ST_X_MULT_SIN;
        ST_X_MULT_SIN:                     calc_next_state = ST_X_SUB;
        ST_X_SUB:                          calc_next_state = ST_Y_MULT_SIN;
        ST_Y_MULT_SIN:                     calc_next_state = ST_Y_MULT_COS;
        ST_Y_MULT_COS:                     calc_next_state = ST_Y_ADD;
        ST_Y_ADD:                          calc_next_state = ST_X_MULT_COEFF;
        ST_X_MULT_COEFF:                   calc_next_state = ST_Y_MULT_COEFF;
        ST_Y_MULT_COEFF:                   calc_next_state = ST_CALC_IDLE;
    endcase
end

// ----------------------------------------------------------------------------
// New field of view calculation
// ----------------------------------------------------------------------------

// Rotate only when 1 key is pressed
assign update_enable = key_rotate_left_i ^ key_rotate_right_i;

// To rotate we have to multiply vector components by rotation matrix
// The formula is:
// x_new = x * cos(rot_angle) - y * sin(rot_angle)
// y_new = x * sin(rot_angle) + y * cos(rot_angle)

always_ff @(posedge clk)
    if (update_start_i)
        if (key_rotate_left_i) begin // Counterclockwise
            cur_cos <= COS_ANGLE;
            cur_sin <= SIN_ANGLE;
        end else begin               // Clockwise
            cur_cos <= COS_NEG_ANGLE;
            cur_sin <= SIN_NEG_ANGLE;
        end

always_ff @(posedge clk)
    if (update_start_i) begin
        x_prev <= dir_x_o;
        y_prev <= dir_y_o;
    end

always_comb begin
    cos_mult_next = cos_mult_ff;
    sin_mult_next = sin_mult_ff;
    comp_new      = '0;

    unique0 case (calc_state)
        // Direction vector intermediate values
        ST_X_MULT_COS:   cos_mult_next = `FIXP_MULT_TRUNC(x_prev, cur_cos);
        ST_X_MULT_SIN:   sin_mult_next = `FIXP_MULT_TRUNC(y_prev, cur_sin);
        ST_Y_MULT_SIN:   sin_mult_next = `FIXP_MULT_TRUNC(x_prev, cur_sin);
        ST_Y_MULT_COS:   cos_mult_next = `FIXP_MULT_TRUNC(y_prev, cur_cos);

        // Direction vector results
        ST_X_SUB:        comp_new      = cos_mult_ff - sin_mult_ff;
        ST_Y_ADD:        comp_new      = sin_mult_ff + cos_mult_ff;
        // Plane vector results
        ST_X_MULT_COEFF: comp_new      =  `FIXP_MULT_TRUNC(dir_y_o, FIXP_PLANE_COEFF);
        ST_Y_MULT_COEFF: comp_new      = -`FIXP_MULT_TRUNC(dir_x_o, FIXP_PLANE_COEFF);
    endcase
end

always_ff @(posedge clk) begin
    cos_mult_ff <= cos_mult_next;
    sin_mult_ff <= sin_mult_next;
end

// ----------------------------------------------------------------------------
// Output
// ----------------------------------------------------------------------------

always_comb begin
    dir_x_next   = dir_x_o;
    dir_y_next   = dir_y_o;

    plane_x_next = plane_x_o;
    plane_y_next = plane_y_o;

    if (update_enable) begin
        unique0 case (calc_state)
            ST_X_SUB:        dir_x_next   = comp_new;
            ST_Y_ADD:        dir_y_next   = comp_new;
            ST_X_MULT_COEFF: plane_x_next = comp_new;
            ST_Y_MULT_COEFF: plane_y_next = comp_new;
        endcase
    end
end

always_ff @(posedge clk)
    if (rst) begin
        dir_x_o   <= `REAL_TO_FIXP(START_DIR_X, ray_fixp_t);
        dir_y_o   <= `REAL_TO_FIXP(START_DIR_Y, ray_fixp_t);

        plane_x_o <= `REAL_TO_FIXP(START_PLANE_X, ray_fixp_t);
        plane_y_o <= `REAL_TO_FIXP(START_PLANE_Y, ray_fixp_t);
    end else begin
        dir_x_o   <= dir_x_next;
        dir_y_o   <= dir_y_next;

        plane_x_o <= plane_x_next;
        plane_y_o <= plane_y_next;
    end

endmodule

`resetall
