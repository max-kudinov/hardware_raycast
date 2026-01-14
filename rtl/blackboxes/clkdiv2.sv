(* blackbox *)
module CLKDIV2 (HCLKIN, RESETN, CLKOUT);
    input HCLKIN, RESETN;
    output CLKOUT;
    parameter GSREN = "false"; 
endmodule

