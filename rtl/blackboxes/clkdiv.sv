(* blackbox *)
module CLKDIV (HCLKIN, RESETN, CALIB, CLKOUT);
input HCLKIN;
input RESETN;
input CALIB;
output CLKOUT;

parameter DIV_MODE = "2"; 
parameter GSREN = "false"; 
endmodule

