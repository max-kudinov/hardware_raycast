`default_nettype none

module temp_recode_lut #(
    localparam int unsigned NUM_TEX   = 7,
    localparam int unsigned W_NUM_TEX = $clog2(NUM_TEX)
) (
    input  var logic clk,
    input  var logic [W_NUM_TEX-1:0] tex,
    input  var logic [3:0]           color_code,
    output var logic [23:0]          color
);

logic [23:0] recode_lut [NUM_TEX] [15];

// Cocotb runs simulation from sim_build directory, so it has different
// relative path to the memfiles
`ifdef SIMULATION
    initial $readmemh("../memfiles/recode_lut.mem", recode_lut);
`else
    initial $readmemh("memfiles/recode_lut.mem", recode_lut);
`endif

always_ff @(posedge clk)
    color <= recode_lut[tex][color_code];

endmodule

`resetall
