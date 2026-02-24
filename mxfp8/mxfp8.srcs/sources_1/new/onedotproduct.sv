`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/20 00:54:38
// Design Name: 
// Module Name: onedotproduct
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


module onedotproduct#(
    parameter int unsigned SRC_WIDTH = 8, //E5M2
    parameter int unsigned SCALE_WIDTH = 8, //change this with package
    parameter int unsigned DST_WIDTH = 32 //change this with package
)(
    input logic clk_i,
    input logic rst_ni,
    //////input signal//////
    input logic [SRC_WIDTH-1:0] operands_a_i,
    input logic [SRC_WIDTH-1:0] operands_b_i,
    input mxfp8_pkg::fp_format_e    src_fmt_i,
    input mxfp8_pkg::fp_format_e    dst_fmt_i,
    input logic [1:0][SCALE_WIDTH-1:0] scale_i,

    /////control signal/////
    input logic a_valid_i,
    input logic b_valid_i,
    input logic init_save_i,
    output logic done_o,

    /////output signals//////
    output logic [DST_WIDTH-1:0] result_o
    );

    ////////////cosntants//////////
    //E5M2 and E4M3, max man_prod is 8 bits, max exp_sum is log_2(31)= 6 bits
    localparam int unsigned SUPER_SRC_MAN_WIDTH = 3;
    localparam int unsigned SUPER_SRC_EXP_WIDTH = 5;
    localparam int unsigned PROD_MAN_WIDTH = 8;//2(m+1)
    localparam int unsigned PROD_EXP_WIDTH = 6;//change this with package
    localparam int unsigned NORM_MAN_WIDTH = 26; 
    localparam int unsigned DST_MAN_WIDTH = 23;
    localparam int unsigned DST_EXP_WIDTH = 8; 
    localparam int unsigned ACC_WIDTH  = NORM_MAN_WIDTH + 1; //+1 sign 位

    //////////unpack input operands//////////
    logic [SUPER_SRC_MAN_WIDTH-1:0] a_man_w;
    logic [SUPER_SRC_MAN_WIDTH-1:0] b_man_w;
    logic unsigned [SUPER_SRC_EXP_WIDTH-1:0] a_exp_w;
    logic unsigned [SUPER_SRC_EXP_WIDTH-1:0] b_exp_w;
    logic a_sign_w;
    logic b_sign_w;
    logic a_isnormal_w;
    logic b_isnormal_w;

    //oprand A
    e5m2_classifier #(
        .MX          	(1     ),
        .SUPER_SRC_MAN_WIDTH(SUPER_SRC_MAN_WIDTH),
        .SUPER_SRC_EXP_WIDTH(SUPER_SRC_EXP_WIDTH),
        .SRC_WIDTH(SRC_WIDTH))
    u_e5m2_classifier_a(
        .src_fmt_i    	(src_fmt_i  ),
        .operands_i 	(operands_a_i  ),
        .man_o          (a_man_w),
        .exp_o          (a_exp_w),
        .sign_o         (a_sign_w),
        .isnormal_o     (a_isnormal_w)

    );
    //oprand B
    e5m2_classifier #(
        .MX          	(1     ),
        .SUPER_SRC_MAN_WIDTH(SUPER_SRC_MAN_WIDTH),
        .SUPER_SRC_EXP_WIDTH(SUPER_SRC_EXP_WIDTH),
        .SRC_WIDTH(SRC_WIDTH))
    u_e5m2_classifier_b(
        .src_fmt_i    	(src_fmt_i  ),
        .operands_i 	(operands_b_i  ),
        .man_o          (b_man_w),
        .exp_o          (b_exp_w),
        .sign_o         (b_sign_w),
        .isnormal_o     (b_isnormal_w)
    );

    logic [PROD_MAN_WIDTH-1:0] man_prod_w;
    logic signed [PROD_EXP_WIDTH-1:0] exp_sum_w;
    logic sign_prod_w;

    onedot_mult#(
        .PROD_MAN_WIDTH (PROD_MAN_WIDTH),
        .PROD_EXP_WIDTH (PROD_EXP_WIDTH)
    ) u_onedot_mult(
        .A_mant         (a_man_w), 
        .B_mant         (b_man_w),
        .A_exp          (a_exp_w),
        .B_exp          (b_exp_w),
        .A_sign         (a_sign_w),
        .B_sign         (b_sign_w),
        .A_isnormal     (a_isnormal_w),
        .B_isnormal     (b_isnormal_w), 
        .src_fmt_i      (src_fmt_i),
        .man_prod_o       (man_prod_w),
        .exp_sum_o        (exp_sum_w),
        .sign_prod_o      (sign_prod_w)
    );

    logic signed [SCALE_WIDTH:0] scale_add;
    logic signed [SCALE_WIDTH:0] scale_exp;
    always_comb begin
        scale_add = signed'(scale_i[0]-127) + signed'(scale_i[1]-127);
        scale_exp = signed'(scale_add) + signed'(exp_sum_w);
    end

    logic signed [ACC_WIDTH-1:0] sum_man,gated_sum_man;
    assign sum_man = {man_prod_w,{(ACC_WIDTH-PROD_MAN_WIDTH){1'b0}}};
    assign gated_sum_man = acc_valid? sum_man:'0;

    logic [DST_MAN_WIDTH:0]          reg_man_full;
    logic signed [DST_EXP_WIDTH-1:0] reg_exp;
    logic                            reg_sgn;
    logic                            reg_valid;

    logic [DST_MAN_WIDTH:0]          acc_man;
    logic signed [DST_EXP_WIDTH-1:0] acc_exp;
    logic                            acc_sgn;

    logic [DST_MAN_WIDTH:0]          feedback_man;
    logic signed [DST_EXP_WIDTH-1:0] feedback_exp;
    logic                            feedback_sgn;
    logic                            feedback_valid;

    always_comb begin
         if (init_save_i) begin
            feedback_sgn = 1'b0;
            feedback_exp = '0; // 这里的 '0 需确保代表数值 0.0
            feedback_man = '0;
            feedback_valid = 1'b0;
        end else begin
            feedback_sgn = reg_sgn;
            feedback_exp = reg_exp;
            feedback_man = reg_man_full;
            feedback_valid = reg_valid;
        end
    end

    logic acc_valid;
    assign acc_valid = a_valid_i&b_valid_i;

    fp32_accumulator #(
        .ACC_WIDTH(NORM_MAN_WIDTH),
        .EXP_WIDTH(DST_EXP_WIDTH),
        .DST_MAN_WIDTH(DST_MAN_WIDTH),
        .SCALE_WIDTH(SCALE_WIDTH)
    )
    u_fp32_acc(
        .a_sgn(sign_prod_w),
        .a_exp(scale_exp),
        .a_man(gated_sum_man), 
        .b_sgn(feedback_sgn),
        .b_exp(feedback_exp), 
        .b_man_with_hidden(feedback_man), 
        .b_valid(feedback_valid),
        .out_sgn(acc_sgn), 
        .out_exp(acc_exp), 
        .out_man(acc_man)
    );


    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            reg_sgn <= 1'b0;
            reg_exp <= '0;
            reg_man_full <= '0;
            reg_valid <= 1'b0;
        end else if (acc_valid) begin
            reg_sgn <= acc_sgn;
            reg_exp  <= acc_exp;
            reg_man_full <= acc_man;
            reg_valid <= 1'b1;
        end else begin
            reg_sgn <= reg_sgn;
            reg_exp  <= reg_exp;
            reg_man_full <= reg_man_full;
            reg_valid <= 1'b0;
        end
    end

    logic [22:0] man_fp32;
    logic [7:0]  exp_fp32;

    assign man_fp32 = reg_man_full[22:0];
    assign exp_fp32 = reg_exp + 127;
    assign result_o = {reg_sgn,exp_fp32,man_fp32};
    assign done_o   = reg_valid;
endmodule

module e5m2_classifier#(
    parameter int unsigned             MX = 1,
    parameter int unsigned             SUPER_SRC_MAN_WIDTH = 3,
    parameter int unsigned             SUPER_SRC_EXP_WIDTH = 5,
    parameter int unsigned             SRC_WIDTH = 8
) (
    input  mxfp8_pkg::fp_format_e                       src_fmt_i,
    input  logic           [SRC_WIDTH-1:0]              operands_i,
    output logic           [SUPER_SRC_MAN_WIDTH-1:0]    man_o ,
    output logic unsigned  [SUPER_SRC_EXP_WIDTH-1:0]    exp_o ,
    output logic                                        sign_o,
    output logic                                        isnormal_o
);


    always_comb begin: classify_input

        if(MX==1 && src_fmt_i == mxfp8_pkg::E5M2) begin
            isnormal_o = (operands_i[(SRC_WIDTH-2) -: 5] != '0) && (operands_i[(SRC_WIDTH-2) -: 5] != '1);
            exp_o = operands_i[(SRC_WIDTH-2) -: 5];
            man_o = operands_i[ 0+:2]<<1; 
        end else begin
            //other data type, add later
            isnormal_o = 1;
            exp_o = {{1'b0},operands_i[(SRC_WIDTH-2) -: 4]};
            man_o = operands_i[ 0+:3];
        end

        
        sign_o = operands_i[SRC_WIDTH-1];
    end
endmodule

module onedot_mult#(
    //config
    parameter int unsigned PROD_MAN_WIDTH = 8, //change this with package
    parameter int unsigned PROD_EXP_WIDTH = 6, //change this with package
    //const
    localparam int unsigned SUPER_SRC_MAN_WIDTH = 3,
    localparam int unsigned SUPER_SRC_EXP_WIDTH = 5
)(
    input  logic [SUPER_SRC_MAN_WIDTH-1:0]          A_mant ,//mant should include implicit bit
    input  logic [SUPER_SRC_MAN_WIDTH-1:0]          B_mant ,
    input  logic unsigned [SUPER_SRC_EXP_WIDTH-1:0] A_exp ,
    input  logic unsigned [SUPER_SRC_EXP_WIDTH-1:0] B_exp ,
    input  logic                                    A_sign ,
    input  logic                                    B_sign ,
    input  logic                                    A_isnormal ,
    input  logic                                    B_isnormal ,
    input  mxfp8_pkg::fp_format_e                   src_fmt_i,
    output logic [PROD_MAN_WIDTH-1:0]               man_prod_o,
    output logic signed  [PROD_EXP_WIDTH-1:0]       exp_sum_o,
    output logic                                    sign_prod_o    
);
    logic signed [PROD_EXP_WIDTH-1:0] A_exp_biased;
    logic signed [PROD_EXP_WIDTH-1:0] B_exp_biased;
    logic [4:0] bias;
    always_comb begin
        if (src_fmt_i==mxfp8_pkg::E5M2) begin
            bias = 15; // 2^(5-1)-1
        end else if (src_fmt_i==mxfp8_pkg::E4M3) begin
            bias = 7; // 2^(4-1)-1
        end else begin
            bias = 127; // 2^(8-1)-1, for FP32,implement later
        end
    end
    always_comb begin
            man_prod_o = {A_isnormal,A_mant} * {B_isnormal,B_mant} ; //mant multiplication
            A_exp_biased = A_exp-bias;
            B_exp_biased = B_exp-bias;
            exp_sum_o = A_exp_biased+ !A_isnormal+ B_exp_biased + !B_isnormal;
            sign_prod_o = A_sign ^ B_sign;
    end
endmodule

module fp32_accumulator#(
    parameter ACC_WIDTH = 27,
    parameter EXP_WIDTH  = 8,
    parameter DST_MAN_WIDTH = 23,
    parameter SCALE_WIDTH = 8
)(
    input logic a_sgn,
    input logic signed [SCALE_WIDTH:0] a_exp,
    input logic [ACC_WIDTH-1:0] a_man,
    input logic b_sgn,
    input logic signed [EXP_WIDTH-1:0] b_exp,
    input logic [DST_MAN_WIDTH:0] b_man_with_hidden,
    input logic b_valid,
    output logic out_sgn,
    output logic signed [EXP_WIDTH-1:0] out_exp,
    output logic [DST_MAN_WIDTH:0] out_man
);
    localparam int unsigned FULL_MAN_WIDTH = DST_MAN_WIDTH+1;

    //Align exponent
    logic signed [EXP_WIDTH-1:0] exp_diff;
    logic [ACC_WIDTH-1:0] mant_a_shifted, mant_b_shifted;
    logic signed [EXP_WIDTH-1:0] exp_large;

    // -------------------------------------------------------------------------
    // Step 1: Recover Hidden Bit for Operand B
    // -------------------------------------------------------------------------
    // FP32: 如果 exp != 0, 则是 1.Mantissa; 如果 exp == 0, 则是 0.Mantissa (Subnormal/Zero)
    // 为了防止复位时的 X 态或错误累加，如果 b_exp 为 0，我们强制 operand B 为 0
    
    logic [DST_MAN_WIDTH:0] b_man_full; // 24 bits: 1.xxxx
    logic b_is_zero;
    
    assign b_is_zero = (b_exp == 0)&&(b_man_with_hidden ==0); // 简单判断，忽略 Subnormal
    assign b_man_full   = b_is_zero ? '0: b_man_with_hidden;
    

    always_comb begin
        exp_diff = signed'(a_exp) - signed'({b_exp[EXP_WIDTH-1],b_exp});
        if (b_valid) begin
            exp_large      = a_exp;
            mant_a_shifted = a_man;
            mant_b_shifted = '0; 
        end else if (exp_diff > 0) begin
            // A has larger exponent
            exp_large      = a_exp;
            mant_a_shifted = a_man;//20 = 8 + 12
            mant_b_shifted = {1'b0, b_man_full,{(ACC_WIDTH-DST_MAN_WIDTH-1){1'b0}}} >> exp_diff;
        end else begin
            exp_large      = b_exp;
            mant_a_shifted = a_man >> (-exp_diff);
            mant_b_shifted = {1'b0,b_man_full,{(ACC_WIDTH-DST_MAN_WIDTH-1){1'b0}}};
        end
    end

    // -------------------------------------------------------------------------
    // Step 3: Apply signs and add/subtract (Full Signed Arithmetic)
    // -------------------------------------------------------------------------
    
    // 1. 扩展位宽以防止溢出，并转换为带符号补码
    // 如果 a_sgn 是 1 (负)，则取 -mant (2's comp)
    // 如果 a_sgn 是 0 (正)，则取 +mant
    
    logic signed [ACC_WIDTH+1:0] val_a_signed;
    logic signed [ACC_WIDTH+1:0] val_b_signed;
    logic signed [ACC_WIDTH+1:0] result_signed;

    always_comb begin
        // 转换 A
        if (a_sgn) val_a_signed = -$signed({1'b0, mant_a_shifted}); 
        else       val_a_signed =  $signed({1'b0, mant_a_shifted});

        // 转换 B
        if (b_sgn) val_b_signed = -$signed({1'b0, mant_b_shifted});
        else       val_b_signed =  $signed({1'b0, mant_b_shifted});

        // 直接加法 (包含所有情况: ++, +-, -+, --)
        result_signed = val_a_signed + val_b_signed;
    end

    // -------------------------------------------------------------------------
    // Step 4: Extract Sign and Magnitude
    // -------------------------------------------------------------------------
    
    // 结果的符号位直接看 MSB
    assign sum_negative = result_signed[ACC_WIDTH+1];
    logic [ACC_WIDTH:0] mant_abs;

    // 结果的绝对值 (Magnitude)
    // 如果结果是负数，取反加一变回正数绝对值；如果是正数，保持不变
    always_comb begin
        if (sum_negative) 
            mant_abs = -result_signed[ACC_WIDTH:0]; // 2's complement to magnitude
        else 
            mant_abs = result_signed[ACC_WIDTH:0];
    end

    // -------------------------------------------------------------------------
    // Step 5: Normalize result
    // -------------------------------------------------------------------------
    logic [ACC_WIDTH:0] mant_norm_abs;
    logic [4:0] lead_shift; // normalization shift
    logic signed [EXP_WIDTH-1:0] exp_adjust;

    function automatic [4:0] leading_one_pos(input logic [ACC_WIDTH:0] val);
        int i;
        leading_one_pos = 0;
        for (i = ACC_WIDTH; i >= 0; i--) begin
            if (val[i]) begin
                break;
            end
            leading_one_pos += 1;
        end
    endfunction

    
    always_comb begin
        lead_shift = leading_one_pos(mant_abs);

        // Shift left until MSB = 1
        mant_norm_abs = mant_abs << lead_shift;
        exp_adjust    = -$signed({1'b0,lead_shift}) + 1;
    end

    // -------------------------------------------------------------------------
    // Step 5: Assign output fields
    // -------------------------------------------------------------------------
    always_comb begin
        out_sgn = sum_negative;
        out_exp  = (mant_norm_abs == '0) ? exp_large : (exp_large + exp_adjust);
        out_man = mant_norm_abs[ACC_WIDTH -:FULL_MAN_WIDTH]; 
    end


endmodule