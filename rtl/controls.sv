`include "fixedpoint.svh"

`default_nettype none

module controls
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter real         MOVEMENT_SPEED      = 0.8,
    parameter real         ROTATION_SPEED      = 0.4,
    parameter int unsigned W_X_POS             = 10,
    parameter int unsigned W_Y_POS             = 9,
    parameter logic [W_X_POS-1:0] FRAME_WIDTH  = 640,
    parameter logic [W_Y_POS-1:0] FRAME_HEIGHT = 480
) (
    input  var logic                          clk,
    input  var logic                          rst,

    // Key input
    input  var logic                          key_forward_i,
    input  var logic                          key_backward_i,
    input  var logic                          key_left_i,
    input  var logic                          key_right_i,
    input  var logic                          key_rotate_left_i,
    input  var logic                          key_rotate_right_i,

    // DVI
    input  var logic        [W_X_POS-1:0]     px_x_i,
    input  var logic        [W_Y_POS-1:0]     px_y_i,

    // Camera coordinates
    output var logic        [W_INT-1:-W_FRAC] pos_x_o,
    output var logic        [W_INT-1:-W_FRAC] pos_y_o,
    // Camera direction
    output var logic signed [W_INT-1:-W_FRAC] dir_x_o,
    output var logic signed [W_INT-1:-W_FRAC] dir_y_o,
    // Camera plane
    output var logic signed [W_INT-1:-W_FRAC] plane_x_o,
    output var logic signed [W_INT-1:-W_FRAC] plane_y_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam real START_POS_X   =  10.0;
localparam real START_POS_Y   =  10.0;
localparam real START_DIR_X   =  0.94;
localparam real START_DIR_Y   = -0.33;
localparam real START_PLANE_X = -0.22;
localparam real START_PLANE_Y = -0.62;

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef enum {
    ST_IDLE,
    ST_CALC_DELTA,
    ST_CALC_POS
} state_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic        [W_INT-1:-W_FRAC] pos_x_next;
logic        [W_INT-1:-W_FRAC] pos_y_next;
logic signed [W_INT-1:-W_FRAC] dir_x_next;
logic signed [W_INT-1:-W_FRAC] dir_y_next;
logic signed [W_INT-1:-W_FRAC] plane_x_next;
logic signed [W_INT-1:-W_FRAC] plane_y_next;

logic signed [W_INT-1:-W_FRAC] delta_dir_x;
logic signed [W_INT-1:-W_FRAC] delta_dir_y;

logic signed [W_INT-1:-W_FRAC] pos_x_inc_x;
logic signed [W_INT-1:-W_FRAC] pos_y_inc_y;
logic signed [W_INT-1:-W_FRAC] pos_x_dec_x;
logic signed [W_INT-1:-W_FRAC] pos_y_dec_y;

logic signed [W_INT-1:-W_FRAC] pos_x_inc_y;
logic signed [W_INT-1:-W_FRAC] pos_y_inc_x;
logic signed [W_INT-1:-W_FRAC] pos_x_dec_y;
logic signed [W_INT-1:-W_FRAC] pos_y_dec_x;

logic start_update;

state_t state, next_state;

always_ff @(posedge clk)
    if (rst)
        state <= ST_IDLE;
    else
        state <= next_state;

always_comb begin
    next_state = state;

    case (state)
        ST_IDLE: if (start_update) next_state = ST_CALC_DELTA;
        ST_CALC_DELTA: next_state = ST_CALC_POS;
    endcase
end

always_ff @(posedge clk) begin
    if (state == ST_CALC_DELTA) begin
        delta_dir_x <= fixedpoint::real_to_sfixp(MOVEMENT_SPEED) * dir_x_o;
        delta_dir_y <= fixedpoint::real_to_sfixp(MOVEMENT_SPEED) * dir_y_o;
    end

    if (state == ST_CALC_POS) begin
        pos_x_inc_x <= pos_x_o + delta_dir_x;
        pos_y_inc_y <= pos_y_o + delta_dir_y;
        pos_x_inc_x <= pos_x_o - delta_dir_x;
        pos_y_inc_y <= pos_y_o - delta_dir_y;

        pos_x_inc_y <= pos_x_o + delta_dir_y;
        pos_y_inc_x <= pos_y_o + delta_dir_x;
        pos_x_dec_y <= pos_x_o - delta_dir_y;
        pos_y_dec_x <= pos_y_o - delta_dir_x;
    end
end

assign start_update = (px_x_i == FRAME_WIDTH - 1) && (px_y_i == FRAME_HEIGHT - 1);

always_ff @(posedge clk) begin
    if (rst) begin
        pos_x_o   <= fixedpoint::real_to_fixp(START_POS_X);
        pos_y_o   <= fixedpoint::real_to_fixp(START_POS_Y);

        dir_x_o   <= fixedpoint::real_to_sfixp(START_DIR_X);
        dir_y_o   <= fixedpoint::real_to_sfixp(START_DIR_Y);

        plane_x_o <= fixedpoint::real_to_sfixp(START_PLANE_X);
        plane_y_o <= fixedpoint::real_to_sfixp(START_PLANE_Y);
    end else if (start_update) begin
        pos_x_o   <= pos_x_next;
        pos_y_o   <= pos_y_next;

        dir_x_o   <= dir_x_next;
        dir_y_o   <= dir_y_next;

        plane_x_o <= plane_x_next;
        plane_y_o <= plane_y_next;
    end
end

always_comb begin
    pos_x_next   = pos_x_o;
    pos_y_next   = pos_y_o;

    dir_x_next   = dir_x_o;
    dir_y_next   = dir_y_o;

    plane_x_next = plane_x_o;
    plane_y_next = plane_y_o;

    // Forward
    if (key_forward_i) begin

    end
end

endmodule

`resetall
