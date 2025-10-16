`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/16 20:33:44
// Design Name: 
// Module Name: mxfp8_mult
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module mxfp8_mult#(
    //config
    parameter int unsigned             VectorSize  = 4,
    parameter int unsigned PROD_MAN_WIDTH = 8, //change this with package
    parameter int unsigned PROD_EXP_WIDTH = 6, //change this with package
    //const
    localparam int unsigned SUPER_SRC_MAN_WIDTH = 3,
    localparam int unsigned SUPER_SRC_EXP_WIDTH = 5,
)(
    input  logic [SUPER_SRC_MAN_WIDTH-1:0][VectorSize-1:0]        A_mant ,//mant should include implicit bit
    input  logic [SUPER_SRC_MAN_WIDTH-1:0][VectorSize-1:0]        B_mant ,
    input  logic signed [SUPER_SRC_EXP_WIDTH-1:0][VectorSize-1:0] A_exp ,
    input  logic signed [SUPER_SRC_EXP_WIDTH-1:0][VectorSize-1:0] B_exp ,
    input  logic        [VectorSize-1:0]                          A_sign ,
    input  logic        [VectorSize-1:0]                          B_sign ,
    input  logic        [VectorSize-1:0]                          A_isnormal ,
    input  logic        [VectorSize-1:0]                          B_isnormal ,
    input  mxfp8_pkg::fp_format_e                                 src_fmt_i,
    output logic [PROD_MAN_WIDTH-1:0][VectorSize-1:0]  man_prod ,
    output logic signed [PROD_EXP_WIDTH-1:0][VectorSize-1:0] exp_sum ,
    output logic        [VectorSize-1:0]sgn_prod    
);
    logic [4:0] bias;
    always_comb begin: bias
        if (src_fmt_i==mxfp8_pkg::E5M2) begin
            bias = 15; // 2^(5-1)-1
        end else if (src_fmt_i==mxfp8_pkg::E4M3) begin
            bias = 7; // 2^(4-1)-1
        end else begin
            bias = 127; // 2^(8-1)-1, for FP32,implement later
        end
    end
    always_comb begin
        for (int i = 0; i < VectorSize; i++) begin
            man_prod[i] = {A_isnormal,A_mant[i]} * {B_isnormal,B_mant[i]} ; //mant multiplication
            exp_sum[i]  = A_exp[i] + B_exp[i] -signed'(bias)+A_isnormal+B_isnormal; //bias addition
            sgn_prod[i] = A_sign ^ B_sign;
        end
    end
endmodule
