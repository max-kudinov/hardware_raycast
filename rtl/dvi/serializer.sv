`default_nettype none

module serializer #(
    parameter int unsigned W_DATA = 10
) (
    input  var logic              clk,
    input  var logic              rst,
    input  var logic [W_DATA-1:0] data_i,
    output var logic              data_o
);

localparam int unsigned W_CNT   = $clog2(W_DATA);
localparam [W_CNT-1:0]  CNT_MAX = W_CNT'(W_DATA - 1);

logic [W_DATA-1:0] shift_reg;
logic [W_CNT-1:0]  cnt;
logic              load;

assign load = cnt == CNT_MAX;

always_ff @(posedge clk) begin
    if (rst) begin
        cnt <= '0;
    end else if (load) begin
        cnt <= '0;
    end else begin
        cnt <= cnt + 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        shift_reg <= '0;
    end else if (load) begin
        shift_reg <= data_i;
    end else begin
        shift_reg <= { 1'b0, shift_reg[W_DATA-1:1] };
    end
end

assign data_o = shift_reg[0];

endmodule

`resetall
