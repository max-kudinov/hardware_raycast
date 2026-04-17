module \$__MUL12X12 (input [11:0] A, input [11:0] B, output [23:0] Y);

parameter A_WIDTH = 12;
parameter B_WIDTH = 12;
parameter Y_WIDTH = 24;
parameter A_SIGNED = 0;
parameter B_SIGNED = 0;

MULT12X12 __TECHMAP_REPLACE__ (
    .A     (A   ),
    .B     (B   ),
    .CE    (2'd0),
    .CLK   (2'd0),
    .DOUT  (Y   ),
    .RESET (2'd0)
);

endmodule
