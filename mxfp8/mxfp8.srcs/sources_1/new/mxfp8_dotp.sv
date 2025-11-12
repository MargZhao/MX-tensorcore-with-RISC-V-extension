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
    parameter int unsigned             VectorSize  = 32,
    //parameter mxfp8_pkg::fmt_logic_t   SrcDotpFpFmtConfig = 3'b110,
    //const
    localparam int unsigned SRC_WIDTH = mxfp8_pkg::fp_width(mxfp8_pkg::E5M2), //change this with package
    localparam int unsigned SCALE_WIDTH = 8, //change this with package
    localparam int unsigned DST_WIDTH = mxfp8_pkg::fp_width(mxfp8_pkg::FP32), //change this with package
    localparam int unsigned NUM_OPERANDS = 2*VectorSize+1 // 2 input and result, scale is not included
    //localparam int unsigned NUM_FORMATS = fpnew_pkg::NUM_FP_FORMATS
    )(
    input  logic                        clk_i,
    input  logic                        rst_ni,
    ////////////input signals//////////
    input  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_a_i,
    input  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_b_i,                                                               
    input  mxfp8_pkg::fp_format_e                src_fmt_i,//src operands data type
    input  mxfp8_pkg::fp_format_e                dst_fmt_i,//dst operands data type,fixed to FP32 now
    input  logic [1:0][SCALE_WIDTH-1:0]          scale_i, // 2 scales for 2 vectors

    ////////////control signals///////////
    input logic clr,

    ////////////output signals//////////
    output logic [DST_WIDTH-1:0]        result_o
    //output mxfp8_pkg::status_t          status_o,
    );

    ////////////cosntants//////////
    //E5M2 and E4M3, max man_prod is 8 bits, max exp_sum is log_2(31)= 6 bits
    localparam int unsigned SUPER_SRC_MAN_WIDTH = 3;
    localparam int unsigned SUPER_SRC_EXP_WIDTH = 5;
    localparam int unsigned PROD_MAN_WIDTH = 16;//3m+4
    localparam int unsigned PROD_EXP_WIDTH = 6;//change this with package
    localparam int unsigned PROD_WIDTH = PROD_MAN_WIDTH + PROD_EXP_WIDTH+1;
    localparam int unsigned LEADING_ZERO_WIDTH = $clog2(PROD_MAN_WIDTH); //change this later
    ////////////type definition//////////

    ///////////logics//////////
    //unpack input operands
    logic [SUPER_SRC_MAN_WIDTH-1:0] a_man_i[VectorSize-1:0];
    logic [SUPER_SRC_MAN_WIDTH-1:0] b_man_i[VectorSize-1:0];
    logic signed [SUPER_SRC_EXP_WIDTH-1:0] a_exp_i[VectorSize-1:0];
    logic signed [SUPER_SRC_EXP_WIDTH-1:0] b_exp_i[VectorSize-1:0];
    logic [VectorSize-1:0] a_sign_i;
    logic [VectorSize-1:0] b_sign_i;
    logic [VectorSize-1:0] a_isnormal;
    logic [VectorSize-1:0] b_isnormal;

    // output declaration of module mxfp8_classifier
    mxfp8_pkg::fp_info_t [VectorSize-1:0] info_a, info_b;

    //oprand A
    mxfp8_classifier #(
        .NumOperands 	(VectorSize     ),
        .MX          	(1     ),
        .SUPER_SRC_MAN_WIDTH(SUPER_SRC_MAN_WIDTH),
        .SUPER_SRC_EXP_WIDTH(SUPER_SRC_EXP_WIDTH),
        .SRC_WIDTH(SRC_WIDTH))
    u_mxfp8_classifier_a(
        .operands_i 	(operands_a_i  ),
        .info_o     	(info_a      )
    );
    //oprand B
    mxfp8_classifier #(
        .NumOperands 	(VectorSize     ),
        .MX          	(1     ),
        .SUPER_SRC_MAN_WIDTH(SUPER_SRC_MAN_WIDTH),
        .SUPER_SRC_EXP_WIDTH(SUPER_SRC_EXP_WIDTH),
        .SRC_WIDTH(SRC_WIDTH))
    u_mxfp8_classifier_b(
        .operands_i 	(operands_b_i  ),
        .info_o     	(info_b      )
    );

    //handle special cases

    //denote bitwidth of mant and exponent according to src_fmt_i
    logic unsigned[1:0] mant_bits;
    logic unsigned[2:0] exp_bits;
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
            
            a_man_i[i]  = operands_a_i[i][man_bits-1:0]<< signed'(SUPER_SRC_MAN_WIDTH-man_bits); //align mant to the LSB
            b_man_i[i]  = operands_b_i[i][man_bits-1:0]<< signed'(SUPER_SRC_MAN_WIDTH-man_bits);
            
            a_isnormal[i] = info_a[i].is_normal;
            b_isnormal[i] = info_b[i].is_normal;
        end
    end

    //mantissa multiplication, exponent addition and sign calculation
    
    logic [PROD_MAN_WIDTH-1:0]  man_prod[VectorSize-1:0];
    logic signed [PROD_EXP_WIDTH-1:0] exp_sum[VectorSize-1:0];
    logic        [VectorSize-1:0]sign_prod;   
  //  logic        [PROD_WIDTH-1:0] interm_result[VectorSize-1:0]; //intermediate result before rounding and packing
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
        .sign_prod       (sign_prod)
    );

    // always_comb begin: 
    //     for (int i = 0; i < VectorSize; i++) begin
    //         interm_result[i] = {sign_prod[i], exp_sum[i], man_prod[i]}; 
    //     end
    // end

     //scaling addition
    logic [SCALE_WIDTH:0] scale_add;
    always_comb begin
        scale_add = signed'(scale_i[0]-127) + signed'(scale_i[1]-127); //change 127 with bias according to src_fmt_i
    end

    //normalization
    logic [PROD_MAN_WIDTH-1:0]     norm_mant;
    logic [PROD_EXP_WIDTH-1:0]     norm_exp;
    logic [LEADING_ZERO_WIDTH-1:0] lz_count=0;
    logic                          is_zero_prod=0;//indicate if the product is zero, no 1 is found
    always_comb begin: count leading zeros
        for (int i = 0;i<PROD_MAN_WIDTH ;i++ ) begin
            if (man_prod[PROD_EXP_WIDTH-i]) begin
                lz_count = i;
                is_zero_prod = 0;
                break;
            end
            else begin
                is_zero_prod = 1;
            end
        end
    end

    always_comb begin: shifting
        casez (leading_zeros)
            '0: begin
                norm_mant = man_prod >> 1;
                norm_exp  = exp_sum + 1;
            end
            '1: begin  
                norm_mant = man_prod;
                norm_exp  = exp_sum;
            end
            default: begin
                if (exp_sum < (leading_zeros-1)) begin
                    //here underflow to zero
                    norm_mant = 0;
                    norm_exp  = '0;
                end
                else begin
                    norm_mant = man_prod << (leading_zeros-1);
                    norm_exp  = exp_sum - (leading_zeros-1);
                end
            end
        endcase   
    end
    //acumulation with scaling
endmodule
