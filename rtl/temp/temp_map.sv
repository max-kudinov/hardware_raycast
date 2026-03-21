`default_nettype none

module temp_map #(
    localparam int unsigned NUM_TEX   = 7,
    localparam int unsigned W_NUM_TEX = $clog2(NUM_TEX),
    localparam int unsigned POS_W_INT = 5
) (
    input  var logic                 clk,
    input  var logic [POS_W_INT-1:0] x,
    input  var logic [POS_W_INT-1:0] y,
    output var logic [W_NUM_TEX-1:0] texture
);

localparam int unsigned MAP_SIDE = 32;

logic [W_NUM_TEX-1:0] map [MAP_SIDE][MAP_SIDE];

always_ff @(posedge clk)
    texture <= map[y][x];

// Cocotb runs simulation from sim_build directory, so it has different
// relative path to the memfiles
`ifdef SIMULATION
    initial $readmemh("../memfiles/map.mem", map);
`else
    initial $readmemh("memfiles/map.mem", map);
`endif

endmodule

`resetall
