`default_nettype none

module ds_buf (
    input  var logic in,
    output var logic out,
    output var logic out_n
);

    `ifdef GOWIN
        TLVDS_OBUF tmds_buf (
            .I  (in   ),
            .O  (out  ),
            .OB (out_n)
        );
    `else
        always_comb begin
            out   =   in;
            out_n = ~ in;
        end
    `endif

endmodule

`resetall
