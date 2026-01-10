`include "fixedpoint.svh"

`default_nettype none

module position
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
#(
    parameter real MOVEMENT_SPEED = 0.8
)(
    input  var logic                          clk,
    input  var logic                          rst,

    // Key input
    input  var logic                          key_forward_i,
    input  var logic                          key_backward_i,
    input  var logic                          key_left_i,
    input  var logic                          key_right_i,

    input  var logic                          update_start_i,

    // Map coordinates to check for a wall
    output var logic        [W_INT-1:0]       lookup_map_x_o,
    output var logic        [W_INT-1:0]       lookup_map_y_o,
    input  var logic                          wall_hit_i,

    // Camera coordinates
    output var logic        [W_INT-1:-W_FRAC] pos_x_o,
    output var logic        [W_INT-1:-W_FRAC] pos_y_o,
    // Camera direction
    input  var logic signed [W_INT-1:-W_FRAC] dir_x_i,
    input  var logic signed [W_INT-1:-W_FRAC] dir_y_i
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam real START_POS_X = 10.0;
localparam real START_POS_Y = 10.0;

// ----------------------------------------------------------------------------
// Local types declaration
// ----------------------------------------------------------------------------

typedef enum {
    ST_POS_X,
    ST_POS_Y
} axis_state_t;

typedef enum {
    ST_FORWARD,
    ST_BACKWARD,
    ST_LEFT,
    ST_RIGHT
} cntrl_state_t;

typedef enum {
    ST_IDLE,
    ST_CALC_DIR,
    ST_SCALE_DIR,
    ST_CALC_POS,
    ST_UPDATE_POS
} calc_state_t;

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic        [W_INT-1:-W_FRAC] pos_x_next;
logic        [W_INT-1:-W_FRAC] pos_y_next;
logic        [W_INT-1:-W_FRAC] new_pos;

logic signed [W_INT-1:-W_FRAC] new_dir_next;
logic signed [W_INT-1:-W_FRAC] new_dir_ff;

logic                          update_done;
logic                          update_enable;
logic                          calc_done;
logic                          axis_done;  // Vector x/y projections, not AXI stream

axis_state_t                   axis_state;
axis_state_t                   axis_next_state;

cntrl_state_t                  cntrl_state;
cntrl_state_t                  cntrl_next_state;

calc_state_t                   calc_state;
calc_state_t                   calc_next_state;

// ----------------------------------------------------------------------------
// Global control
// ----------------------------------------------------------------------------

assign update_done = (axis_state == ST_POS_Y) && (cntrl_state == ST_RIGHT);
assign calc_done   = calc_state == ST_UPDATE_POS;
assign axis_done   = calc_done && (cntrl_state == ST_RIGHT);

always_ff @(posedge clk)
    if (rst) begin
        update_enable <= '0;
    end else begin
        update_enable <= '0;

        case (cntrl_state)
            ST_FORWARD:  if (key_forward_i)  update_enable <= '1;
            ST_BACKWARD: if (key_backward_i) update_enable <= '1;
            ST_LEFT:     if (key_left_i)     update_enable <= '1;
            ST_RIGHT:    if (key_right_i)    update_enable <= '1;
        endcase
    end

// ----------------------------------------------------------------------------
// FSMs
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (rst)
        axis_state <= ST_POS_X;
    else
        axis_state <= axis_next_state;

always_comb begin
    axis_next_state = axis_state;

    unique case (axis_state)
        ST_POS_X: if (axis_done) axis_next_state = ST_POS_Y;
        ST_POS_Y: if (axis_done) axis_next_state = ST_POS_X;
    endcase
end

always_ff @(posedge clk)
    if (rst)
        cntrl_state <= ST_FORWARD;
    else
        cntrl_state <= cntrl_next_state;

always_comb begin
    cntrl_next_state = cntrl_state;

    unique case (cntrl_state)
        ST_FORWARD:  if (calc_done) cntrl_next_state = ST_BACKWARD;
        ST_BACKWARD: if (calc_done) cntrl_next_state = ST_LEFT;
        ST_LEFT:     if (calc_done) cntrl_next_state = ST_RIGHT;
        ST_RIGHT:    if (calc_done) cntrl_next_state = ST_FORWARD;
    endcase
end

always_ff @(posedge clk)
    if (rst)
        calc_state <= ST_IDLE;
    else
        calc_state <= calc_next_state;

always_comb begin
    calc_next_state = calc_state;

    unique case (calc_state)
        ST_IDLE:       if (update_start_i) calc_next_state = ST_CALC_DIR;
        ST_CALC_DIR:                       calc_next_state = ST_SCALE_DIR;
        ST_SCALE_DIR:                      calc_next_state = ST_CALC_POS;
        ST_CALC_POS:                       calc_next_state = ST_UPDATE_POS;
        ST_UPDATE_POS: if (update_done)    calc_next_state = ST_IDLE;
                       else                calc_next_state = ST_CALC_DIR;
    endcase
end

// ----------------------------------------------------------------------------
// New position calculation
// ----------------------------------------------------------------------------

always_comb
    if (calc_state == ST_CALC_DIR)
        unique case ({ axis_state, cntrl_state })
            // X-axis
            { ST_POS_X, ST_FORWARD  }: new_dir_next =  dir_x_i;
            { ST_POS_X, ST_BACKWARD }: new_dir_next = -dir_x_i;
            { ST_POS_X, ST_LEFT     }: new_dir_next = -dir_y_i;
            { ST_POS_X, ST_RIGHT    }: new_dir_next =  dir_y_i;

            // Y-axis
            { ST_POS_Y, ST_FORWARD  }: new_dir_next =  dir_y_i;
            { ST_POS_Y, ST_BACKWARD }: new_dir_next = -dir_y_i;
            { ST_POS_Y, ST_LEFT     }: new_dir_next =  dir_x_i;
            { ST_POS_Y, ST_RIGHT    }: new_dir_next = -dir_x_i;
        endcase
    else if (calc_state == ST_SCALE_DIR)
        new_dir_next = fixedpoint::signed_mult(
            new_dir_ff,
            fixedpoint::real_to_sfixp(MOVEMENT_SPEED)
        );

always_ff @(posedge clk)
    new_dir_ff <= new_dir_next;

always_ff @(posedge clk)
    if (calc_state == ST_CALC_POS)
        if (axis_state == ST_POS_X)
            // Signed addition, then cast back to unsigned
            new_pos <= unsigned'(signed'(pos_x_o) + new_dir_ff);
        else
            new_pos <= unsigned'(signed'(pos_y_o) + new_dir_ff);

always_comb begin
    if (axis_state == ST_POS_X) begin
        lookup_map_x_o = new_pos[W_INT-1:0];
        lookup_map_y_o = pos_y_o[W_INT-1:0];
    end else begin
        lookup_map_x_o = pos_x_o[W_INT-1:0];
        lookup_map_y_o = new_pos[W_INT-1:0];
    end
end

// ----------------------------------------------------------------------------
// Output
// ----------------------------------------------------------------------------

always_comb begin
    pos_x_next = pos_x_o;
    pos_y_next = pos_y_o;

    if (update_enable && calc_done && !wall_hit_i)
        if (axis_state == ST_POS_X)
            pos_x_next = new_pos;
        else
            pos_y_next = new_pos;
end

always_ff @(posedge clk)
    if (rst) begin
        pos_x_o <= fixedpoint::real_to_fixp(START_POS_X);
        pos_y_o <= fixedpoint::real_to_fixp(START_POS_Y);
    end else begin
        pos_x_o <= pos_x_next;
        pos_y_o <= pos_y_next;
    end

endmodule

`resetall
