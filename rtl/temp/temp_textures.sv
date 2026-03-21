`default_nettype none

module temp_textures #(
    localparam int unsigned TEX_SIDE   = 32,
    localparam int unsigned W_PX_CODE  = 4,
    localparam int unsigned NUM_TEX    = 7,
    localparam int unsigned W_TEX_SIDE = $clog2(TEX_SIDE),
    localparam int unsigned W_NUM_TEX  = $clog2(NUM_TEX)
) (
    input  var logic                  clk,
    input  var logic [W_NUM_TEX-1:0]  num_tex,
    input  var logic [W_TEX_SIDE-1:0] x,
    input  var logic [W_TEX_SIDE-1:0] y,
    output var logic [W_PX_CODE-1:0]  px_code
);

logic [W_PX_CODE-1:0] textures [NUM_TEX][TEX_SIDE][TEX_SIDE];

// Cocotb runs simulation from sim_build directory, so it has different
// relative path to the memfiles
`ifdef SIMULATION
    initial $readmemh("../memfiles/textures.mem", textures);
`else
    initial $readmemh("memfiles/textures.mem", textures);
`endif

always_ff @(posedge clk)
    px_code <= textures[num_tex][y][x];

endmodule

`resetall
