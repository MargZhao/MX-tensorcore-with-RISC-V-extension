module tb_Block_PE_wrapper;

timeunit 1ns;
timeprecision 10ps;

logic clk_i;
logic rstn;

always begin #2.0ns; clk_i <= ~clk_i; end

//Inputs to DUT
//Control for MACs in Block_PE
logic [1:0]  prec_mode;
logic [1:0]  FP_mode;

//Control for requantization in Block_PE
logic        send_output;
logic [1:0]  prec_mode_quan;
logic [1:0]  FP_mode_quan;

//Data in
logic [0:7][7:0] A_INT8; //8-bit Mantissa
logic [0:7][7:0] B_INT8;

logic [0:7][0:3][7:0] A_FP8; //Sign,Exponent,Mantissa
logic [0:7][0:3][7:0] B_FP8;

logic [0:7][0:3][5:0] A_FP6; //Sign,Exponent,Mantissa
logic [0:7][0:3][5:0] B_FP6;

logic [0:7][0:7][3:0] A_FP4; //Sign,Exponent,Mantissa
logic [0:7][0:7][3:0] B_FP4;

logic [7:0]      shared_exp_A;
logic [7:0]      shared_exp_B;
	
logic A_ready;
logic A_valid;
logic B_ready;
logic B_valid;

//Data out
logic [0:7][0:7][7:0] Out; //Sign,Exponent,Mantissa,padding_zeros
logic [7:0] shared_exp_out;

//DUT
Block_PE_wrapper Block_PE_wrapper0 (
.clk_i(clk_i), .rstn(rstn), .prec_mode(prec_mode), .FP_mode(FP_mode), 
.send_output(send_output), .prec_mode_quan(prec_mode_quan), .FP_mode_quan(FP_mode_quan),
.A_INT8(A_INT8), .B_INT8(B_INT8), .A_FP8(A_FP8), .B_FP8(B_FP8), .A_FP6(A_FP6), .B_FP6(B_FP6),
.A_FP4(A_FP4), .B_FP4(B_FP4), .shared_exp_A(shared_exp_A), .shared_exp_B(shared_exp_B), .Out(Out), .shared_exp_out(shared_exp_out),
.A_ready(A_ready), .A_valid(A_valid), .B_ready(B_ready), .B_valid(B_valid)
);

initial begin
clk_i = 0;
rstn = 0;
// shared_exp_A = 'd127;
// shared_exp_B = 'd127;
prec_mode = 2'b00; //INT8xINT8
FP_mode = 2'b00;
prec_mode_quan = 2'b00;
FP_mode_quan = 2'b00;
send_output = 1'b0;
A_valid = 1'b0;
B_valid = 1'b0;

shared_exp_A   = 'x;       // unknown
shared_exp_B   = 'x;       // unknown
// prec_mode      = 2'bxx;    // unknown (both bits)
// FP_mode        = 2'bxx;    // unknown
// prec_mode_quan = 2'bxx;    // unknown
// FP_mode_quan   = 2'bxx;    // unknown
// send_output    = 1'bx;     // unknown
// A_valid        = 1'b0;     // unknown
// B_valid        = 1'b0;     // unknown

@(posedge clk_i);

rstn = 1;

#10ns;

// shared_exp_A   = 'x;       // unknown
// shared_exp_B   = 'x;       // unknown
// prec_mode      = 2'bxx;    // unknown (both bits)
// FP_mode        = 2'bxx;    // unknown
// prec_mode_quan = 2'bxx;    // unknown
// FP_mode_quan   = 2'bxx;    // unknown
// send_output    = 1'bx;     // unknown
// A_valid        = 1'b0;     // unknown
// B_valid        = 1'b0;     // unknown

//INT8:
for (int i=0;i<8;i++) begin
A_INT8[i] = 8'd11;
B_INT8[i] = 8'd8;
end
A_valid = 1'b1;
B_valid = 1'b1;
shared_exp_A = 'd127;
shared_exp_B = 'd127;

@(posedge clk_i);

shared_exp_A   = 'x;       // unknown
shared_exp_B   = 'x;       // unknown
A_valid = 1'b0;
B_valid = 1'b0;

@(posedge clk_i);
for (int i=0;i<8;i++) begin
A_INT8[i] = 8'd11;
B_INT8[i] = 8'd8;
end
A_valid = 1'b1;
B_valid = 1'b1;
shared_exp_A = 'd127;
shared_exp_B = 'd127;

@(posedge clk_i);
send_output = 1'b1;
#0.1ns;
/*
for (int i=0;i<8;i++) begin
for (int j=0;j<8;j++) begin
$display("i = %0d, j = %0d", i, j);
$display("%b", Out[i][j]);
$display("%d", shared_exp_out);
assert(Out[i][j] == 8'b00101100);
assert(shared_exp_out == 8'd121);
end
end*/
$display("%b", Out[0][0]);
$display("%d", shared_exp_out);
assert(Out[0][0] == 8'b00101100);
assert(shared_exp_out == 8'd121);

#10ns;

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


// //Negatives
// for (int i=0;i<8;i++) begin
// A_INT8[i] = -8'd11;
// B_INT8[i] = 8'd8;
// end
// A_valid = 1'b1;
// B_valid = 1'b1;

// @(posedge clk_i);
// A_valid = 1'b0;
// B_valid = 1'b0;
// send_output = 1'b1;
// #0.1ns;
// /*
// for (int i=0;i<8;i++) begin
// for (int j=0;j<8;j++) begin
// $display("i = %0d, j = %0d", i, j);
// $display("%b", Out[i][j]);
// $display("%d", shared_exp_out);
// assert(Out[i][j] == 8'b11010100);
// assert(shared_exp_out == 8'd121);
// end
// end*/
// $display("%b", Out[0][0]);
// $display("%d", shared_exp_out);
// assert(Out[0][0] == 8'b11010100);
// assert(shared_exp_out == 8'd121);

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


// //E4M3
// prec_mode = 2'b01;
// FP_mode = 2'b10;
// prec_mode_quan = 2'b01;
// FP_mode_quan = 2'b10;

// for (int i=0;i<8;i++) begin
// A_FP8[i][0] = {1'b0, 4'd1, 3'd2};
// A_FP8[i][1] = {1'b0, 4'd1, 3'd6};
// A_FP8[i][2] = {1'b0, 4'd1, 3'd5};
// A_FP8[i][3] = {1'b0, 4'd2, 3'd3};

// B_FP8[i][0] = {1'b0, 4'd3, 3'd1};
// B_FP8[i][1] = {1'b0, 4'd3, 3'd4};
// B_FP8[i][2] = {1'b0, 4'd2, 3'd7};
// B_FP8[i][3] = {1'b0, 4'd5, 3'd2};
// end
// A_valid = 1'b1;
// B_valid = 1'b1;

// @(posedge clk_i);
// A_valid = 1'b0;
// B_valid = 1'b0;
// send_output = 1'b1;
// #0.1ns;
// /*for (int i=0;i<8;i++) begin
// for (int j=0;j<8;j++) begin
// $display("i = %0d, j = %0d", i, j);
// $display("%b", Out[i][j]);
// $display("%d", shared_exp_out);
// assert(Out[i][j] == 8'b01111010);
// assert(shared_exp_out == 8'd112);
// end
// end*/
// $display("%b", Out[0][0]);
// $display("%d", shared_exp_out);
// assert(Out[0][0] == 8'b01111010);
// assert(shared_exp_out == 8'd113);

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


// //Negatives
// for (int i=0;i<8;i++) begin
// A_FP8[i][0] = {1'b1, 4'd1, 3'd2};
// A_FP8[i][1] = {1'b1, 4'd1, 3'd6};
// A_FP8[i][2] = {1'b1, 4'd1, 3'd5};
// A_FP8[i][3] = {1'b1, 4'd2, 3'd3};

// B_FP8[i][0] = {1'b0, 4'd3, 3'd1};
// B_FP8[i][1] = {1'b0, 4'd3, 3'd4};
// B_FP8[i][2] = {1'b0, 4'd2, 3'd7};
// B_FP8[i][3] = {1'b0, 4'd5, 3'd2};
// end
// A_valid = 1'b1;
// B_valid = 1'b1;

// @(posedge clk_i);
// A_valid = 1'b0;
// B_valid = 1'b0;
// send_output = 1'b1;
// #0.1ns;

// $display("%b", Out[0][0]);
// $display("%d", shared_exp_out);
// assert(Out[0][0] == 8'b11111010);
// assert(shared_exp_out == 8'd113);

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


// //E3M2
// prec_mode = 2'b01;
// FP_mode = 2'b01;
// prec_mode_quan = 2'b01;
// FP_mode_quan = 2'b01;

// for (int i=0;i<8;i++) begin
// A_FP6[i][0] = {1'b0, 3'd1, 2'd2};
// A_FP6[i][1] = {1'b0, 3'd1, 2'd2};
// A_FP6[i][2] = {1'b0, 3'd1, 2'd3};
// A_FP6[i][3] = {1'b0, 3'd2, 2'd3};

// B_FP6[i][0] = {1'b0, 3'd3, 2'd1};
// B_FP6[i][1] = {1'b0, 3'd3, 2'd2};
// B_FP6[i][2] = {1'b0, 3'd2, 2'd3};
// B_FP6[i][3] = {1'b0, 3'd5, 2'd2};
// end
// A_valid = 1'b1;
// B_valid = 1'b1;

// @(posedge clk_i);
// A_valid = 1'b0;
// B_valid = 1'b0;
// send_output = 1'b1;
// #0.1ns;

// $display("%b", Out[0][0]);
// $display("%d", shared_exp_out);
// assert(Out[0][0] == 8'b01111000);
// assert(shared_exp_out == 8'd125);

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


// //E5M2
// prec_mode = 2'b01;
// FP_mode = 2'b11;
// prec_mode_quan = 2'b01;
// FP_mode_quan = 2'b11;

// for (int i=0;i<8;i++) begin
// A_FP8[i][0] = {1'b0, 5'd2, 2'd2};
// A_FP8[i][1] = {1'b0, 5'd11, 2'd0};
// A_FP8[i][2] = {1'b0, 5'd22, 2'd0};
// A_FP8[i][3] = {1'b0, 5'd13, 2'd1};

// B_FP8[i][0] = {1'b0, 5'd6, 2'd3};
// B_FP8[i][1] = {1'b0, 5'd28, 2'd1};
// B_FP8[i][2] = {1'b0, 5'd2, 2'd2};
// B_FP8[i][3] = {1'b0, 5'd5, 2'd2};
// end
// A_valid = 1'b1;
// B_valid = 1'b1;

// @(posedge clk_i);
// A_valid = 1'b0;
// B_valid = 1'b0;
// send_output = 1'b1;
// #0.1ns;

// $display("%b", Out[0][0]);
// $display("%d", shared_exp_out);
// assert(Out[0][0] == 8'b01111101);
// assert(shared_exp_out == 8'd120);

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


// //E2M3
// prec_mode = 2'b01;
// FP_mode = 2'b00;
// prec_mode_quan = 2'b01;
// FP_mode_quan = 2'b00;

// for (int i=0;i<8;i++) begin
// A_FP6[i][0] = {1'b0, 2'd1, 3'd1};
// A_FP6[i][1] = {1'b0, 2'd1, 3'd7};
// A_FP6[i][2] = {1'b0, 2'd1, 3'd3};
// A_FP6[i][3] = {1'b0, 2'd2, 3'd3};

// B_FP6[i][0] = {1'b0, 2'd3, 3'd4};
// B_FP6[i][1] = {1'b0, 2'd3, 3'd6};
// B_FP6[i][2] = {1'b0, 2'd2, 3'd3};
// B_FP6[i][3] = {1'b0, 2'd1, 3'd5};
// end
// A_valid = 1'b1;
// B_valid = 1'b1;

// @(posedge clk_i);
// A_valid = 1'b0;
// B_valid = 1'b0;
// send_output = 1'b1;
// #0.1ns;

// $display("%b", Out[0][0]);
// $display("%d", shared_exp_out);
// assert(Out[0][0] == 8'b01111000);
// assert(shared_exp_out == 8'd125);

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


// //E2M1
// prec_mode = 2'b11;
// FP_mode = 2'b00;
// prec_mode_quan = 2'b11;
// FP_mode_quan = 2'b00;

// for (int i=0;i<8;i++) begin
// A_FP4[i][0] = {1'b0, 2'd1, 1'd0};
// A_FP4[i][1] = {1'b0, 2'd1, 1'd0};
// A_FP4[i][2] = {1'b0, 2'd1, 1'd1};
// A_FP4[i][3] = {1'b0, 2'd1, 1'd1};
// A_FP4[i][4] = {1'b0, 2'd1, 1'd1};
// A_FP4[i][5] = {1'b0, 2'd1, 1'd1};
// A_FP4[i][6] = {1'b0, 2'd2, 1'd1};
// A_FP4[i][7] = {1'b0, 2'd2, 1'd0};

// B_FP4[i][0] = {1'b0, 2'd1, 1'd0};
// B_FP4[i][1] = {1'b0, 2'd1, 1'd1};
// B_FP4[i][2] = {1'b0, 2'd1, 1'd0};
// B_FP4[i][3] = {1'b0, 2'd1, 1'd1};
// B_FP4[i][4] = {1'b0, 2'd2, 1'd0};
// B_FP4[i][5] = {1'b0, 2'd3, 1'd1};
// B_FP4[i][6] = {1'b0, 2'd2, 1'd1};
// B_FP4[i][7] = {1'b0, 2'd3, 1'd1};
// end
// A_valid = 1'b1;
// B_valid = 1'b1;

// @(posedge clk_i);
// A_valid = 1'b0;
// B_valid = 1'b0;
// send_output = 1'b1;
// #0.1ns;

// $display("%b", Out[0][0]);
// $display("%d", shared_exp_out);
// assert(Out[0][0] == 8'b01100000);
// assert(shared_exp_out == 8'd130);

// @(posedge clk_i);
// send_output = 1'b0;
// rstn = 0;
// @(posedge clk_i);
// rstn = 1;


$display("Test ends.");
$finish;

end

endmodule
