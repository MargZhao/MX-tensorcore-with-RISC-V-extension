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
    localparam int unsigned PROD_MAN_WIDTH = 8;//3m+4
    localparam int unsigned PROD_EXP_WIDTH = 8;//change this with package
    localparam int unsigned NORM_MAN_WIDTH = 1.5*PROD_MAN_WIDTH +4; //16
    localparam int unsigned PROD_WIDTH = PROD_MAN_WIDTH + PROD_EXP_WIDTH+1;
    localparam int unsigned LEADING_ZERO_WIDTH = $clog2(NORM_MAN_WIDTH); //change this later
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
        .src_fmt_i    	(src_fmt_i  ),
        .operands_i 	(operands_a_i  ),
        .info_o     	(info_a      ),
        .man_i          (a_man_i),
        .exp_i          (a_exp_i),
        .sign_i         (a_sign_i),
        .isnormal       (a_isnormal)

    );
    //oprand B
    mxfp8_classifier #(
        .NumOperands 	(VectorSize     ),
        .MX          	(1     ),
        .SUPER_SRC_MAN_WIDTH(SUPER_SRC_MAN_WIDTH),
        .SUPER_SRC_EXP_WIDTH(SUPER_SRC_EXP_WIDTH),
        .SRC_WIDTH(SRC_WIDTH))
    u_mxfp8_classifier_b(
        .src_fmt_i    	(src_fmt_i  ),
        .operands_i 	(operands_b_i  ),
        .info_o     	(info_b      ),
        .man_i          (b_man_i),
        .exp_i          (b_exp_i),
        .sign_i         (b_sign_i),
        .isnormal       (b_isnormal)
    );

    //handle special cases

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

    // Stage 4
    //logic signed [PROD_EXP_WIDTH-1:0] exp_max;
    //logic [PROD_EXP_WIDTH-1:0] exp_diff[VectorSize-1:0];
    logic [SCALE_WIDTH:0] scale_aligned;
    logic [NORM_MAN_WIDTH-1:0] sum_man;
    logic sum_sgn;
    adder_tree#(.VectorSize(VectorSize), 
                .PROD_EXP_WIDTH(PROD_EXP_WIDTH), 
                .PROD_MAN_WIDTH(PROD_MAN_WIDTH),
                .NORM_MAN_WIDTH(NORM_MAN_WIDTH),
                .SCALE_WIDTH(SCALE_WIDTH)) 
        u_adder_tree (
            //input
            .exp_sum(exp_sum), 
            .man_prod(man_prod),
            .sgn_prod(sign_prod),
            .scale_sum(scale_add),
            //output
            .scale_aligned(scale_aligned),
            .sum_man(sum_man),
            .sum_sgn(sum_sgn));

 
 
    // //normalization
    // //logic signed [PROD_EXP_WIDTH-1:0]     total_exp;
    // logic [NORM_MAN_WIDTH-1:0]     norm_mant;
    // logic signed [PROD_EXP_WIDTH-1:0]     norm_exp;
    // logic [LEADING_ZERO_WIDTH-1:0] lz_count=0;
    // logic                          is_zero_prod=0;//indicate if the product is zero, no 1 is found
    // logic signed [LEADING_ZERO_WIDTH-1:0]    f_underflow=0;
    // always_comb begin : count_leading_zeros
    // lz_count     = 0;
    // is_zero_prod = 1'b1;  // assume all zero
    // for (int i = 0; i < NORM_MAN_WIDTH; i++) begin
    //     if (sum_man[NORM_MAN_WIDTH-1-i]) begin
    //         lz_count     = i;
    //         is_zero_prod = 1'b0;
    //         //f_underflow  = lz_count - exp_sum;
    //         break; // found first '1'
    //         end
    //     end
    // end

    // always_comb begin : shifting
    //     // default assignments
    //     norm_mant = '0;
    //     norm_exp  = '0;

    //     // special cases for lz_count == 0 or 1
    //     if (lz_count == 0) begin
    //         norm_mant = sum_man >> 1;
    //         norm_exp  = scale_aligned + 1;
    //     end
    //     else if (lz_count == 1) begin
    //         norm_mant = sum_man;
    //         norm_exp  = scale_aligned;
    //     end
    //     else begin
    //         // for larger lz_count, handle underflow / shift
    //         // if (f_underflow > 1) begin
    //         //     // underflow → zero
    //         //     norm_mant = '0;
    //         //     norm_exp  = '0;
    //         // end
    //         // else begin
    //             norm_mant = sum_man << (lz_count - 1);
    //             norm_exp  = scale_aligned - (lz_count - 1);
    //        //end
    //     end
    // end
    //acumulation with scaling

    logic [NORM_MAN_WIDTH-1:0] reg_man;
    logic signed [PROD_EXP_WIDTH-1:0] reg_exp;
    logic reg_sgn;
    logic [NORM_MAN_WIDTH-1:0] acc_man;
    logic signed [PROD_EXP_WIDTH-1:0] acc_exp;
    logic acc_sgn;

    stage8_fp32_accumulator #(
        .MANT_WIDTH(PROD_MAN_WIDTH),
        .NORM_MAN_WIDTH(NORM_MAN_WIDTH),
        .EXP_WIDTH(PROD_EXP_WIDTH)
    )
    u_fp32_acc(
        .clr(clr),
        .a_sgn(sum_sgn),
        .a_exp(scale_aligned),
        .a_man(sum_man), 
        .b_sgn(reg_sgn),
        .b_exp(reg_exp), 
        .b_man(reg_man), 
        .out_sgn(acc_sgn), 
        .out_exp(acc_exp), 
        .out_man(acc_man)
    );


    

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            reg_sgn <= 1'b0;
            reg_exp  <= '0;
            reg_man <= '0;
        end else begin
            reg_sgn <= acc_sgn;
            reg_exp  <= acc_exp;
            reg_man <= acc_man;
        end
    end

    logic [22:0] man_fp32;
    logic [7:0]  exp_fp32;

    assign man_fp32 = {reg_man[NORM_MAN_WIDTH-2:0],{(23-NORM_MAN_WIDTH+1){1'b0}}};
    assign exp_fp32 = (reg_man == 0) ? 8'd0 : reg_exp + 127;
    assign result_o = {reg_sgn,exp_fp32,man_fp32};


    


endmodule