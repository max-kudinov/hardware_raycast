module test;

localparam W_INT = 8;
localparam W_FRAC = 8;
localparam N_ITER = 6;
localparam W_NUM = W_INT + W_FRAC;

bit clk;
bit rst;

logic [W_INT-1:-W_FRAC] num;
logic [W_NUM-1:0] res;
logic start, done;
initial num = '0;

always #1 clk = !clk;

initial begin
    rst = 1;
    @(posedge clk);
    @(posedge clk);
    rst = 0;
end

initial begin
    @(posedge clk);
    @(posedge clk);
    @(posedge clk);
    start = 1;
    @(posedge clk);
    start = 0;

    wait(done);
    $display(res);
    @(posedge clk);
    $finish;
end

initial begin
    // $dumpfile("dump.fst");
    $dumpvars;
    repeat (100) @(posedge clk);
    $finish;
end

newton_inv DUT (
    .clk     (clk),
    .rst     (rst),

    .start_i (start),
    .num_i   (num),

    .done_o  (done),
    .num_o   (res)
);


endmodule
