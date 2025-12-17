`include "fixedpoint.svh"

`default_nettype none

module newton_inv
    import fixedpoint::W_INT;
    import fixedpoint::W_FRAC;
(
    input  var logic                   clk,
    input  var logic                   rst,

    input  var logic                   start_i,
    input  var logic [W_INT-1:-W_FRAC] num_i,

    output var logic                   done_o,
    output var logic [W_INT-1:-W_FRAC] num_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam W_SHIFT       = $clog2(W_INT + 1);
localparam N_ITER_CYCLES = fixedpoint::N_ITER * 2;
localparam W_CNT         = $clog2(N_ITER_CYCLES);

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

logic [W_INT-1:-W_FRAC]     num_next;
logic [W_INT-1:-W_FRAC]     num_ff;
logic [W_INT-1:-W_FRAC]     approx_next;
logic [W_INT-1:-W_FRAC]     approx_ff;
logic [W_INT-1:-W_FRAC]     approx_mid_next;
logic [W_INT-1:-W_FRAC]     approx_mid_ff;
logic [W_SHIFT-1:0]         shift_amount;
logic [W_CNT-1:0]           iter_cnt;
logic                       cnt_done;

typedef enum {
    ST_IDLE,
    ST_CALC_SHIFT,
    ST_SHIFT_INPUT,
    ST_ITERATE,
    ST_SHIFT_OUTPUT,
    ST_RES_OUT
} state_t;

state_t state, next_state;

// ----------------------------------------------------------------------------
// FSM
// ----------------------------------------------------------------------------

always_comb begin
    next_state = state;

    case (state)
        ST_IDLE:         if (start_i)  next_state = ST_CALC_SHIFT;
        ST_CALC_SHIFT:                 next_state = ST_SHIFT_INPUT;
        ST_SHIFT_INPUT:                next_state = ST_ITERATE;
        ST_ITERATE:      if (cnt_done) next_state = ST_SHIFT_OUTPUT;
        ST_SHIFT_OUTPUT:               next_state = ST_RES_OUT;
        ST_RES_OUT:      if (start_i)  next_state = ST_CALC_SHIFT;
                         else          next_state = ST_IDLE;
    endcase
end

always_ff @(posedge clk)
    if (rst)
        state <= ST_IDLE;
    else
        state <= next_state;

// ----------------------------------------------------------------------------
// Data manipulation states
// ----------------------------------------------------------------------------

always_comb begin
    num_next = num_ff;

    unique0 case (state)
        ST_IDLE:        if (start_i)  num_next = num_i;
        ST_SHIFT_INPUT:               num_next = num_ff >> shift_amount;
        ST_ITERATE:     if (cnt_done) num_next = approx_next;
        ST_SHIFT_OUTPUT:              num_next = num_ff >> shift_amount;
    endcase
end

always_ff @(posedge clk)
    num_ff <= num_next;

// ----------------------------------------------------------------------------
// Caclulate shift amount
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (state == ST_CALC_SHIFT) begin
        shift_amount <= '0;

        for (int i = 0; i < W_INT; i++) begin
            if (num_ff[i]) shift_amount <= W_SHIFT'(i + 1);
        end
    end

// ----------------------------------------------------------------------------
// Newton's method calculations
// ----------------------------------------------------------------------------

always_ff @(posedge clk)
    if (state == ST_SHIFT_INPUT)
        iter_cnt <= '0;
    else if (state == ST_ITERATE)
        iter_cnt <= iter_cnt + 1'b1;

assign cnt_done = iter_cnt == W_CNT'(N_ITER_CYCLES - 1);

always_comb begin
    approx_next     = approx_ff;
    approx_mid_next = approx_mid_ff;

    if (state == ST_SHIFT_INPUT) begin
        approx_next = fixedpoint::int_to_fixp(1);
    end else if (state == ST_ITERATE) begin
        if (!iter_cnt[0]) begin
            approx_mid_next = fixedpoint::int_to_fixp(2) - fixedpoint::mult(num_ff,  approx_ff);
        end else begin
            approx_next = fixedpoint::mult(approx_ff, approx_mid_ff);
        end
    end

end

always_ff @(posedge clk) begin
    approx_ff     <= approx_next;
    approx_mid_ff <= approx_mid_next;
end

// ----------------------------------------------------------------------------
// Output
// ----------------------------------------------------------------------------

assign num_o = num_ff;

always_ff @(posedge clk)
    done_o <= next_state == ST_RES_OUT;

endmodule

`default_nettype wire
