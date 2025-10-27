`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/16 15:57:47
// Design Name: 
// Module Name: mxfp8_dot4
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


module mxfp8_dotp#(
    //config
    parameter int unsigned             VectorSize  = 4,
    //parameter mxfp8_pkg::fmt_logic_t   SrcDotpFpFmtConfig = 3'b110,
    //const
    localparam int unsigned SRC_WIDTH = mxfp8_pkg::fp_width(mxfp8_pkg::E5M2), //change this with package
    localparam int unsigned SCALE_WIDTH = 8, //change this with package
    localparam int unsigned DST_WIDTH = mxfp8_pkg::fp_width(mxfp8_pkg::FP32), //change this with package
    localparam int unsigned NUM_OPERANDS = 2*VectorSize+1, // 2 input and result, scale is not included
    localparam int unsigned NUM_FORMATS = fpnew_pkg::NUM_FP_FORMATS
    )(
    input  logic                        clk_i,
    input  logic                        rst_ni,
    ////////////input signals//////////
    input  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_a_i,
    input  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_b_i,                                                               
    input  mxfp8_pkg::fp_format_e                src_fmt_i,//src operands data type
    input  mxfp8_pkg::fp_format_e                dst_fmt_i,//dst operands data type,fixed to FP32 now
    input  logic [1:0][SCALE_WIDTH-1:0]          scale_i, // 2 scales for 2 vectors

    ////////////output signals//////////
    output logic [DST_WIDTH-1:0]        result_o,
    output fpnew_pkg::status_t          status_o,
    );

    ////////////cosntants//////////
    //E5M2 and E4M3, max man_prod is 8 bits, max exp_sum is log_2(31)= 6 bits
    localparam int unsigned SUPER_SRC_MAN_WIDTH = 3,
    localparam int unsigned SUPER_SRC_EXP_WIDTH = 5,
    localparam int unsigned PROD_MAN_WIDTH = 8, //change this with package
    localparam int unsigned PROD_EXP_WIDTH = 6, //change this with package
    localparam int unsigned PROD_WIDTH = PROD_MAN_WIDTH + PROD_EXP_WIDTH+1,

    ////////////type definition//////////

    ///////////logics//////////

    // output declaration of module mxfp8_classifier
    mxfp8_pkg::fp_info_t [VectorSize-1:0] info_a, info_b;
    //oprand A
    mxfp8_classifier #(
        .FpFormat    	(src_fmt_i  ),
        .NumOperands 	(VectorSize     ),
        .MX          	(1     ))
    u_mxfp8_classifier_a(
        .operands_i 	(operands_a_i  ),
        .info_o     	(info_a      )
    );
    //oprand B
    mxfp8_classifier #(
        .FpFormat    	(src_fmt_i  ),
        .NumOperands 	(VectorSize     ),
        .MX          	(1     ))
    u_mxfp8_classifier_b(
        .operands_i 	(operands_b_i  ),
        .info_o     	(info_b      )
    );

    //handle special cases

    //denote bitwidth of mant and exponent according to src_fmt_i
    logic [1:0] mant_bits;
    logic [2:0] exp_bits;
    always_comb begin
    exp_bits = mxfp8_pkg::FP_ENCODINGS[src_fmt_i].exp_bits;
    man_bits = mxfp8_pkg::FP_ENCODINGS[src_fmt_i].man_bits;           
    end

    //unpack input operands
    logic [VectorSize-1:0][SUPER_SRC_MAN_WIDTH-1:0] a_man_i;
    logic [VectorSize-1:0][SUPER_SRC_MAN_WIDTH-1:0] b_man_i;
    logic signed [VectorSize-1:0][SUPER_SRC_EXP_WIDTH-1:0] a_exp_i;
    logic signed [VectorSize-1:0][SUPER_SRC_EXP_WIDTH-1:0] b_exp_i;
    logic [VectorSize-1:0] a_sign_i;
    logic [VectorSize-1:0] b_sign_i;
    logic [VectorSize-1:0] a_isnormal;
    logic [VectorSize-1:0] b_isnormal;

    always_comb begin: unpack_operands
        for (int i = 0; i < VectorSize; i++) begin
            a_sign_i[i] = operands_a_i[i][SRC_WIDTH-1];
            b_sign_i[i] = operands_b_i[i][SRC_WIDTH-1];

            a_exp_i[i] = {{signed'(SUPER_SRC_EXP_WIDTH-exp_bits){1'b0}}, operands_a_i[i][SRC_WIDTH-2 -: exp_bits]};
            b_exp_i[i] = {{signed'(SUPER_SRC_EXP_WIDTH-exp_bits){1'b0}}, operands_b_i[i][SRC_WIDTH-2 -: exp_bits]};
            
            a_man_i[i]  = operands_a_i[i][man_bits-1:0]<< (SUPER_SRC_MAN_WIDTH-man_bits); //align mant to the LSB
            b_man_i[i]  = operands_b_i[i][man_bits-1:0]<< (SUPER_SRC_MAN_WIDTH-man_bits);
            
            a_isnormal[i] = info_a[i].is_normal;
            b_isnormal[i] = info_b[i].is_normal;
        end
    end

    //mantissa multiplication, exponent addition and sign calculation
    
    logic [PROD_MAN_WIDTH-1:0][VectorSize-1:0]  man_prod;
    logic signed [PROD_EXP_WIDTH-1:0][VectorSize-1:0] exp_sum;
    logic        [VectorSize-1:0]sign_prod;   
    logic        [PROD_WIDTH-1:0][VectorSize-1:0] interm_result; //intermediate result before rounding and packing
    mxfp8_mult #(
        .VectorSize       (VectorSize),
        .PROD_MAN_WIDTH   (PROD_MAN_WIDTH),
        .PROD_EXP_WIDTH   (PROD_EXP_WIDTH)
    ) u_mxfp8_mult (
        .A_mant         (a_man_i), 
        .B_mant         (b_man_i),
        .A_exp          (a_exp_i),
        .B_exp          (b_exp_i),
        .A_sign         (a_sign_i),
        .B_sign         (b_sign_i),
        .A_isnormal    (a_isnormal),
        .B_isnormal    (b_isnormal), 
        .src_fmt_i      (src_fmt_i),
        .man_prod       (man_prod),
        .exp_sum        (exp_sum),
        .sign_prod       (sgn_prod)
    );
    always_comb begin: interm_result
        for (int i = 0; i < VectorSize; i++) begin
            interm_result[i] = {sign_prod[i], exp_sum[i], man_prod[i]}; 
        end
    end

    //scaling addition
    logic signed [SCALE_WIDTH:0] scale_add;
    always_comb begin
        scale_add = signed'(scale_i[0]-127) + signed'(scale_i[1]-127); //change 127 with bias according to src_fmt_i
    end
endmodule
