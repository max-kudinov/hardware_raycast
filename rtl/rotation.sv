`include "fixedpoint.svh"

`default_nettype none

module rotation
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter real ROTATION_SPEED = 0.4
)(
    input  var logic                          clk,
    input  var logic                          rst,

    input  var logic                          key_rotate_left_i,
    input  var logic                          key_rotate_right_i,

    input  var logic                          update_start_i,

    // Camera direction
    output var logic signed [W_INT-1:-W_FRAC] dir_x_o,
    output var logic signed [W_INT-1:-W_FRAC] dir_y_o,
    // Camera plane
    output var logic signed [W_INT-1:-W_FRAC] plane_x_o,
    output var logic signed [W_INT-1:-W_FRAC] plane_y_o
);

import fixedpoint::sfixp_t;

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam real    START_DIR_X   =  0.94;
localparam real    START_DIR_Y   = -0.33;
localparam real    START_PLANE_X = -0.22;
localparam real    START_PLANE_Y = -0.62;

// Precalculated trig constants for rotation matrix
localparam sfixp_t COS_ANGLE     = fixedpoint::real_to_sfixp($cos(ROTATION_SPEED));
localparam sfixp_t SIN_ANGLE     = fixedpoint::real_to_sfixp($sin(ROTATION_SPEED));
localparam sfixp_t COS_NEG_ANGLE = fixedpoint::real_to_sfixp($cos(-ROTATION_SPEED));
localparam sfixp_t SIN_NEG_ANGLE = fixedpoint::real_to_sfixp($sin(-ROTATION_SPEED));

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef enum {
    ST_UPDATE_DIR,
    ST_UPDATE_PLANE
} vect_state_t;

typedef enum {
    ST_CALC_IDLE,
    ST_X_MULT_COS,
    ST_X_MULT_SIN,
    ST_X_SUB,
    ST_Y_MULT_SIN,
    ST_Y_MULT_COS,
    ST_Y_ADD
} calc_state_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic update_done;
logic update_enable;
logic signed [W_INT-1:-W_FRAC] cur_cos;
logic signed [W_INT-1:-W_FRAC] cur_sin;

logic vect_done;

vect_state_t vect_state;
vect_state_t vect_next_state;

calc_state_t calc_state;
calc_state_t calc_next_state;

// ----------------------------------------------------------------------------
// FSMs
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (rst)
        vect_state <= ST_UPDATE_DIR;
    else
        vect_state <= vect_next_state;

always_comb begin
    vect_next_state = vect_state;

    case (vect_state)
        ST_UPDATE_DIR:   if (vect_done) vect_next_state = ST_UPDATE_PLANE;
        ST_UPDATE_PLANE: if (vect_done) vect_next_state = ST_UPDATE_DIR;
    endcase
end

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
        ST_Y_ADD:      if (update_done)    calc_next_state = ST_CALC_IDLE;
                       else                calc_next_state = ST_X_MULT_COS;
    endcase
end

// ----------------------------------------------------------------------------
// New field of view calculation
// ----------------------------------------------------------------------------

// Rotate only when 1 key is pressed
assign update_enable = key_rotate_left_i ^ key_rotate_right_i;
assign vect_done     = calc_state == ST_Y_ADD;
assign update_done   = vect_done && (vect_state == ST_UPDATE_PLANE);

// To rotate we have to multiply vector components by rotation matrix
// The formula is:
// x_new = x * cos(rot_angle) - y * sin(rot_angle)
// y_new = x * sin(rot_angle) + y * cos(rot_angle)

always_ff @(posedge clk)
    if (update_start_i)
        if (key_rotate_left_i) begin // Counter clockwise
            cur_cos <= COS_ANGLE;
            cur_sin <= SIN_ANGLE;
        end else begin               // Clockwise
            cur_cos <= COS_NEG_ANGLE;
            cur_sin <= SIN_NEG_ANGLE;
        end

always_ff @(posedge clk)
    if (rst) begin
        dir_x_o   <= fixedpoint::real_to_sfixp(START_DIR_X);
        dir_y_o   <= fixedpoint::real_to_sfixp(START_DIR_Y);

        plane_x_o <= fixedpoint::real_to_sfixp(START_PLANE_X);
        plane_y_o <= fixedpoint::real_to_sfixp(START_PLANE_Y);
    end

endmodule

`resetall
