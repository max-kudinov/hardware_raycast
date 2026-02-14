`include "fixp_pkg.svh"

`default_nettype none

module newton_inv
    // import fixp_pkg::W_INT;
    // import fixp_pkg::fixp_t;
#(
    parameter type input_t,
    parameter type output_t
) (
    input  var logic  clk,
    input  var logic  rst,

    input  var logic  start_i,
    // TODO: remove when change size

    // verilator lint_off UNUSEDSIGNAL
    input  var input_t num_i,
    // verilator lint_off UNUSEDSIGNAL

    output var logic  done_o,
    output var output_t num_o
);

// ----------------------------------------------------------------------------
// Local parameters declaration
// ----------------------------------------------------------------------------

localparam int unsigned W_SHIFT       = $clog2($left(output_t) + 1);
localparam int unsigned N_ITER_CYCLES = fixp_pkg::N_ITER * 2;
localparam int unsigned W_CNT         = $clog2(N_ITER_CYCLES);

// ----------------------------------------------------------------------------
// Local signals declaration
// ----------------------------------------------------------------------------

output_t          num_next;
output_t          num_ff;
output_t              approx_next;
output_t              approx_ff;
output_t              approx_mid_next;
output_t              approx_mid_ff;
logic [W_SHIFT-1:0] shift_amount;
logic [W_CNT-1:0]   iter_cnt;
logic               cnt_done;

typedef enum logic [2:0] {
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

    unique case (state)
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
        ST_IDLE:        if (start_i)  num_next = output_t'(num_i);
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

        for (int unsigned i = 0; i < $left(output_t) + 1; i++) begin
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
        approx_next = `INT_TO_FIXP(1, output_t);
    end else if (state == ST_ITERATE) begin
        if (!iter_cnt[0]) begin
            approx_mid_next = `INT_TO_FIXP(2, output_t) - `FIXP_MULT(num_ff,  approx_ff, output_t);
        end else begin
            approx_next = `FIXP_MULT(approx_ff, approx_mid_ff, output_t);
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
    if (rst)
        done_o <= '0;
    else
        done_o <= next_state == ST_RES_OUT;

endmodule

`resetall
