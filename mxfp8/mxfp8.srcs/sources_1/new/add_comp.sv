`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/23 14:54:40
// Design Name: 
// Module Name: add_comp
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

typedef struct packed {
    logic                      sign;
    logic [5-1:0] exponent;
    logic [3-1:0] mantissa;
  } fp_src_t;

(* keep_hierarchy = "yes" *)
module add_comp#(
    VectorSize = 32,
    EXP_WIDTH  = 6,
    SOP_FIXED_WIDTH = 68,
    PRECISION_BITS = 4
)(
    input fp_src_t [VectorSize-1:0]operands_a,
    input fp_src_t [VectorSize-1:0]operands_b,
    input logic signed [VectorSize-1:0][2*PRECISION_BITS  :0] product_signed,
    output logic signed [VectorSize-1:0][EXP_WIDTH-1:0] exponent_product,
    output logic signed [VectorSize-1:0][SOP_FIXED_WIDTH-1:0] shifted_product,
    output logic [VectorSize-1:0][  5:0] shift_amount // max shift can be 58 (28 + exp-max(30)), min shift is 0 (28 + exp-min(-28))
);
  // ------------------
  // Shift data path
  // ------------------
  // Calculate the non-biased exponent of the product
    generate
        for (genvar i = 0; i < VectorSize; i++) begin : gen_exponent_adjustment
            assign exponent_product[i] = operands_a[i].exponent + 1
                                        + operands_b[i].exponent + 1
                                        - 2*signed'(16);
            // Right shift the significand by anchor point - exponent
            // sum of four 9-bit numbers can be at most 11 bits, for 69 bits output we need to shift by 69 - 11 = 58
            // 58-30=28 plus inherit 6 fractional bits from the multiplication -> point moves to 28+6=34
            assign shift_amount[i] = signed'(28) + signed'(exponent_product[i]);
            assign shifted_product[i] = signed'(product_signed[i]) << shift_amount[i];
        end
    endgenerate
endmodule
// module add_comp #(
//     // config
//     parameter int unsigned VectorSize      = 32,
//     parameter int unsigned PROD_EXP_WIDTH  = 8,
//     parameter int unsigned PROD_MAN_WIDTH  = 6,
//     // 建议：根据之前讨论，可选 NORM_MAN_WIDTH ≈ 64/80/96
//     parameter int unsigned NORM_MAN_WIDTH  = 96,
//     parameter int unsigned SCALE_WIDTH     = 8,

//     // 32 项累加需要 log2(32)=5 bit guard
//     parameter int unsigned GUARD_BITS      = $clog2(VectorSize),
//     // +1 sign 位；ACC_WIDTH-1 给 CSA 输出使用，ACC_WIDTH 给最终 CPA
//     parameter int unsigned ACC_WIDTH       = NORM_MAN_WIDTH + GUARD_BITS + 1
// ) (
//     input  logic signed [VectorSize-1:0][PROD_EXP_WIDTH-1:0] exp_sum,
//     input  logic        [VectorSize-1:0][PROD_MAN_WIDTH-1:0] man_prod,
//     input  logic        [VectorSize-1:0]                     sgn_prod,
//     input  logic signed [SCALE_WIDTH:0]                      scale_sum,
//     output logic signed [SCALE_WIDTH:0]                      scale_aligned,
//     output logic        [NORM_MAN_WIDTH-1:0]                 sum_man,
//     output logic                                             sum_sgn
// );

//     // ============================================================
//     // 1) 找 exp_max + 对齐后的 scale
//     // ============================================================
//     logic signed [PROD_EXP_WIDTH-1:0] exp_max;
//     logic signed [VectorSize-1:0][PROD_EXP_WIDTH-1:0] exp_diff;

//     // 最大 exponent（signed 比较）
//     always_comb begin : find_max
//         exp_max = exp_sum[0];
//         for (int i = 1; i < VectorSize; i++) begin
//             if ($signed(exp_sum[i]) > $signed(exp_max))
//                 exp_max = exp_sum[i];
//         end
//     end

//     // scale 对齐 + exponent 差
//     always_comb begin : reduce_exp
//         scale_aligned = scale_sum + exp_max; // 这就是你 MXDOTP 图里的 Xa/Xb + anchor 逻辑
//         for (int i = 0; i < VectorSize; i++) begin
//             exp_diff[i] = exp_max - exp_sum[i]; // >= 0
//         end
//     end

//     // ============================================================
//     // 2) Alignment：限制 shift 位宽 + 更紧凑的 barrel shifter
//     // ============================================================

//     // shift 控制位宽：只需要 log2(NORM_MAN_WIDTH) 位就够
//     localparam int unsigned SHIFT_BITS = $clog2(NORM_MAN_WIDTH);

//     // 对每个 operand：clip 后的移位量 + “是否直接变 0”
//     logic [VectorSize-1:0][SHIFT_BITS-1:0] shift_amt;
//     logic [VectorSize-1:0]                 shift_zero;

//     // 先把 exponent 差 clip 到 0..NORM_MAN_WIDTH-1 之间
//     always_comb begin : shift_clip
//         for (int i = 0; i < VectorSize; i++) begin
//             if (exp_diff[i] >= NORM_MAN_WIDTH) begin
//                 // 右移超出范围，直接视为 0
//                 shift_zero[i] = 1'b1;
//                 shift_amt[i]  = '0;
//             end else begin
//                 shift_zero[i] = 1'b0;
//                 shift_amt[i]  = exp_diff[i][SHIFT_BITS-1:0];
//             end
//         end
//     end

//     // 对齐后的部分和（带符号）
//     logic signed [VectorSize-1:0][NORM_MAN_WIDTH-1:0] man_align;
//     logic [NORM_MAN_WIDTH-1:0] base_mag;
//     logic [NORM_MAN_WIDTH-1:0] shifted_mag;
//     logic signed [NORM_MAN_WIDTH-1:0] shifted_signed;

//     // 对齐：不再 {1'b0, man, 0...} 再 >>>，
//     // 而是：先 zero-extend 到 NORM_MAN_WIDTH，再做逻辑右移，再根据符号做 2's complement
//     always_comb begin : alignment
//         for (int i = 0; i < VectorSize; i++) begin
//             // 1) zero-extend mantissa product 到 NORM_MAN_WIDTH
//             base_mag = {{(NORM_MAN_WIDTH-PROD_MAN_WIDTH){1'b0}}, man_prod[i]};

//             // 2) clip 后的逻辑右移
//             shifted_mag = base_mag >> shift_amt[i];

//             // 3) 转成带符号（此时为非负数）
//             shifted_signed = $signed(shifted_mag);

//             // 4) 如果 exp_diff 太大 → 直接 0
//             if (shift_zero[i]) begin
//                 man_align[i] = '0;
//             end else begin
//                 // 5) 根据 sgn_prod 生成负数或正数
//                 man_align[i] = sgn_prod[i] ? -shifted_signed : shifted_signed;
//             end
//         end
//     end

//     // ============================================================
//     // 3) CSA tree：多操作数压缩，只做一次全宽 CPA
//     // ============================================================

//     // CSA tree 输出：ACC_WIDTH-1 位（最后一位用于 sign 扩展）
//     logic signed [ACC_WIDTH-2:0] sum_csa;
//     logic signed [ACC_WIDTH-2:0] carry_csa;
//     (* keep_hierarchy = "yes" *)
//     csa_tree #(
//         .VectorSize (VectorSize),
//         .WIDTH_I    (NORM_MAN_WIDTH),
//         .WIDTH_O    (ACC_WIDTH-1)         // 显式指定输出位宽
//     ) inst_compressor_tree (
//         .operands_i (man_align),
//         .sum_o      (sum_csa),
//         .carry_o    (carry_csa)
//     );

//     // 最终 CPA（一次全宽加法）
//     logic signed [ACC_WIDTH-1:0] sum_all;

//     assign sum_all = $signed({sum_csa[ACC_WIDTH-2],   sum_csa}) +
//                      $signed({carry_csa[ACC_WIDTH-2], carry_csa});

//     // ============================================================
//     // 4) 提取 sign + magnitude（2's complement）
//     // ============================================================

//     always_comb begin : sign_extract
//         sum_sgn = sum_all[ACC_WIDTH-1];

//         if (sum_sgn) begin
//             // 负数 → 取反 + 1，取高 NORM_MAN_WIDTH 位
//             sum_man = (~sum_all[ACC_WIDTH-1 -: NORM_MAN_WIDTH]) + 1'b1;
//         end else begin
//             sum_man = sum_all[ACC_WIDTH-1 -: NORM_MAN_WIDTH];
//         end
//     end

// endmodule
// (* keep_hierarchy = "yes" *)
// module add_comp #(

//     parameter int VectorSize= 32,
//     parameter int PROD_EXP_WIDTH = 6,
//     parameter int PROD_MAN_WIDTH = 8,
//     parameter int NORM_MAN_WIDTH = 32,

//     parameter int GUARD_BITS = $clog2(VectorSize),
//     parameter int ACC_WIDTH  = NORM_MAN_WIDTH + GUARD_BITS + 1

// )(
//     input  logic signed  [VectorSize-1:0][PROD_EXP_WIDTH-1:0] exp_sum,
//     input  logic [VectorSize-1:0][PROD_MAN_WIDTH-1:0] man_prod,
//     input  logic [VectorSize-1:0] sgn_prod,

//     output logic signed [ACC_WIDTH-1:0] sum_all,
//     output logic signed [PROD_EXP_WIDTH-1:0] exp_max
// );

//     // ------------------------------------------------------------
//     // 1) exp_max
//     // ------------------------------------------------------------
//     (* keep_hierarchy = "yes" *)
//     exp_max #(
//         .VectorSize(VectorSize),
//         .EXPW(PROD_EXP_WIDTH)
//     ) u_exp_max (
//         .exp_sum(exp_sum),
//         .exp_max(exp_max)
//     );

//     // ------------------------------------------------------------
//     // 2) diff = exp_max - exp_sum
//     // ------------------------------------------------------------
//     (* keep_hierarchy = "yes" *)
//     logic signed [VectorSize-1:0][PROD_EXP_WIDTH-1:0] diff;

//     exp_diff #(
//         .VectorSize(VectorSize),
//         .EXPW(PROD_EXP_WIDTH)
//     ) u_exp_diff (
//         .exp_max(exp_max),
//         .exp_sum(exp_sum),
//         .diff(diff)
//     );

//     // ------------------------------------------------------------
//     // 3) align stage (barrel shifter inside)
//     // ------------------------------------------------------------
//     logic signed [VectorSize-1:0][NORM_MAN_WIDTH-1:0] man_align;
//     (* keep_hierarchy = "yes" *)
//     align_unit #(
//         .VectorSize(VectorSize),
//         .PROD_MAN_WIDTH(PROD_MAN_WIDTH),
//         .NORM_MAN_WIDTH(NORM_MAN_WIDTH),
//         .EXPW(PROD_EXP_WIDTH)
//     ) u_align (
//         .man_prod (man_prod),
//         .sgn_prod (sgn_prod),
//         .exp_diff (diff),
//         .man_align(man_align)
//     );

//     // ------------------------------------------------------------
//     // 4) CSA tree + CPA
//     // ------------------------------------------------------------
//     // logic signed [ACC_WIDTH-2:0] final_sum;
//     // logic signed [ACC_WIDTH-2:0] final_carry;
//     // (* keep_hierarchy = "yes" *)
//     // csa_tree #(
//     //     .VectorSize(VectorSize),
//     //     .WIDTH_I(NORM_MAN_WIDTH),
//     //     .WIDTH_O(ACC_WIDTH-1)
//     // ) u_tree (
//     //     .operands_i(man_align),
//     //     .sum_o(final_sum),
//     //     .carry_o(final_carry)
//     // );

//     // assign sum_all = final_sum + final_carry;
//     always_comb begin
//         sum_all = '0;
//         for (int i = 0; i < VectorSize; i++) begin
//             sum_all += man_align[i];
//         end
//     end

// endmodule

// module align_unit #(
//     parameter int VectorSize = 32,
//     parameter int PROD_MAN_WIDTH = 8,
//     parameter int NORM_MAN_WIDTH = 32,
//     parameter int EXPW = 6
// )(
//     input  logic [VectorSize-1:0][PROD_MAN_WIDTH-1:0] man_prod,
//     input  logic [VectorSize-1:0] sgn_prod,
//     input  logic [VectorSize-1:0][EXPW-1:0] exp_diff,

//     output logic signed [VectorSize-1:0][NORM_MAN_WIDTH-1:0] man_align
// );

//     logic signed [NORM_MAN_WIDTH-1:0] man_ext [VectorSize];
//     logic signed [NORM_MAN_WIDTH-1:0] shifted  [VectorSize];

//     generate
//         for (genvar i = 0; i < VectorSize; i++) begin : G_ALIGN

//             // Sign-extend
//             always_comb begin
//                 man_ext[i] = $signed({
//                     1'b0,
//                     man_prod[i],
//                     {(NORM_MAN_WIDTH-PROD_MAN_WIDTH-1){1'b0}}
//                 });

//                 if (sgn_prod[i])
//                     man_ext[i] = -man_ext[i];
//             end

//             // Barrel shifter instance
//             (* keep_hierarchy = "yes" *)
//             barrel_shifter #(
//                 .WIDTH(NORM_MAN_WIDTH)
//             ) u_bs (
//                 .din  (man_ext[i]),
//                 .shift(exp_diff[i][ $clog2(NORM_MAN_WIDTH)-1 : 0 ]),
//                 .dout (shifted[i])
//             );

//             // Too-large shift → zero
//             always_comb begin
//                 if (exp_diff[i] >= NORM_MAN_WIDTH)
//                     man_align[i] = '0;
//                 else
//                     man_align[i] = shifted[i];
//             end

//         end
//     endgenerate

// endmodule

// module exp_max #(
//     parameter int VectorSize = 32,
//     parameter int EXPW = 6
// )(
//     input  logic signed [VectorSize-1:0][EXPW-1:0] exp_sum,
//     output logic signed [EXPW-1:0] exp_max
// );
//     always_comb begin
//         exp_max = exp_sum[0];
//         for (int i = 1; i < VectorSize; i++)
//             if ($signed(exp_sum[i]) > $signed(exp_max))
//                 exp_max = exp_sum[i];
//     end
// endmodule

// module exp_diff #(
//     parameter int VectorSize = 32,
//     parameter int EXPW = 6
// )(
//     input  logic signed [EXPW-1:0] exp_max,
//     input  logic signed [VectorSize-1:0][EXPW-1:0] exp_sum,
//     output logic signed [VectorSize-1:0][EXPW-1:0] diff
// );

//     always_comb begin
//         for (int i = 0; i < VectorSize; i++)
//             diff[i] = exp_max - exp_sum[i];
//     end
// endmodule

// module barrel_shifter #(
//     parameter int WIDTH = 32,
//     parameter int SHIFTW = $clog2(WIDTH)
// )(
//     input  logic signed [WIDTH-1:0] din,
//     input  logic [SHIFTW-1:0]       shift,
//     output logic signed [WIDTH-1:0] dout
// );
//     logic signed [WIDTH-1:0] tmp;

//     always_comb begin
//         tmp = din;
//         for (int k = 0; k < SHIFTW; k++)
//             if (shift[k])
//                 tmp = tmp >>> (1 << k);

//         dout = tmp;
//     end
// endmodule



// module csa_tree #(
//     parameter int unsigned VectorSize = 32,
//     parameter int unsigned WIDTH_I = 8,     // bit-width of inputs
//     parameter int unsigned WIDTH_O = WIDTH_I + 4 + 1   // bit-width of outputs
// )(
//     input logic signed[VectorSize-1:0][WIDTH_I-1:0] operands_i,
//     output logic signed[WIDTH_O-1:0] sum_o,
//     output logic signed[WIDTH_O-1:0] carry_o
// );
//     localparam int unsigned N_A = VectorSize/2;
//     localparam int unsigned N_B = VectorSize - N_A;

//     generate
//         if (VectorSize==1) begin
//             assign sum_o = operands_i[0];
//             assign carry_o = '0;
//         end
//         else if(VectorSize==2) begin
//             assign sum_o = operands_i[0];
//             assign carry_o = operands_i[1];
//         end
//         else if(VectorSize==3) begin
//             compressor_3to2 #(
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) u_compressor_3to2(
//                 .operands_i(operands_i),
//                 .sum_o(sum_o),
//                 .carry_o(carry_o)
//             );
//         end
//         else if(VectorSize==4) begin
//             compressor_4to2 #(
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) u_compressor_4to2(
//                 .operands_i(operands_i),
//                 .sum_o(sum_o),
//                 .carry_o(carry_o)
//             );
//         end
//         else begin
//             logic signed [N_A-1:0][WIDTH_I-1:0] operands_i_A;
//             logic signed [N_B-1:0][WIDTH_I-1:0] operands_i_B;
//             logic signed [WIDTH_O-1:0] sum_o_A;
//             logic signed [WIDTH_O-1:0] sum_o_B;
//             logic signed [WIDTH_O-1:0] carry_o_A;
//             logic signed [WIDTH_O-1:0] carry_o_B;

//             // Divide the inputs into two chunks
//             assign operands_i_A = operands_i[N_A-1:0];
//             assign operands_i_B = operands_i[VectorSize-1:N_A];

//             csa_tree #(
//                 .VectorSize(N_A),
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) ua_csa_tree(
//                 .operands_i(operands_i_A),
//                 .sum_o(sum_o_A),
//                 .carry_o(carry_o_A)
//             );

//             csa_tree #(
//                 .VectorSize(N_B),
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) ub_csa_tree(
//                 .operands_i(operands_i_B),
//                 .sum_o(sum_o_B),
//                 .carry_o(carry_o_B)
//             );

//             logic signed [3:0][WIDTH_O-1:0] operands_i_C ;
//             assign operands_i_C = {sum_o_A, carry_o_A, sum_o_B, carry_o_B};
            
//             compressor_4to2 #(
//                 .WIDTH_I(WIDTH_O),
//                 .WIDTH_O(WIDTH_O)
//             ) uc_compressor_4to2(
//                 .operands_i(operands_i_C),
//                 .sum_o(sum_o),
//                 .carry_o(carry_o)
//             );
//         end
//     endgenerate
// endmodule

// module compressor_4to2 #(
//     parameter int unsigned WIDTH_I = 8,                             // bit-width of inputs
//     parameter int unsigned WIDTH_O = WIDTH_I + 5   // bit-width of outputs
// )(
//     input logic signed [3:0][WIDTH_I-1:0] operands_i,
//     output logic signed [WIDTH_O-1:0] sum_o,
//     output logic signed [WIDTH_O-1:0] carry_o
// );
//     logic signed[WIDTH_I-1:0] sum;
//     logic [WIDTH_I:0] cin;
//     logic [WIDTH_I-1:0] cout;
//     logic signed[WIDTH_I-1:0] carry;
    
//     assign cin[0] = 1'b0;

//     // Cascaded 5:3 counters according to input bit-width
//     generate
//         genvar i;
//         for(i=0;i<WIDTH_I;i++) begin
//             counter_5to3 u_counter_5to3(
//                 .x1(operands_i[0][i]),
//                 .x2(operands_i[1][i]),
//                 .x3(operands_i[2][i]),
//                 .x4(operands_i[3][i]),
//                 .cin(cin[i]),
//                 .sum(sum[i]),
//                 .carry(carry[i]),
//                 .cout(cout[i])
//             );
//             assign cin[i+1] = cout[i];
//         end
//     endgenerate

//     logic carry_temp;
    
//     assign sum_o = sum;
//     assign carry_temp = carry[WIDTH_I-1]|cin[WIDTH_I];

//     // 1) 组合出未扩展的 carry_o 原始向量 (宽度 WIDTH_I + 2)
//     logic signed [WIDTH_I:0] carry_raw;
//     assign carry_raw = {carry_temp, carry[WIDTH_I-2:0], 1'b0};

//     // 2) 按符号位扩展到 WIDTH_O 位
//     assign carry_o = {{(WIDTH_O-(WIDTH_I+1)){carry_raw[WIDTH_I]}}, carry_raw};
// endmodule

// module counter_5to3(
//     input logic x1,x2,x3,x4,cin,
//     output logic sum,carry,cout
// );
//     assign sum = x1 ^ x2 ^ x3 ^ x4 ^ cin;
//     assign cout = (x1 ^ x2) & x3 | ~(x1 ^ x2) & x1;
//     assign carry = (x1 ^ x2 ^ x3 ^ x4) & cin | ~(x1 ^ x2 ^ x3 ^ x4) & x4;
// endmodule


// module add_comp#(
//     parameter int unsigned ACC_WIDTH = 96,
//     parameter int unsigned VectorSize = 32)
// (
//     input logic signed [VectorSize-1:0][ACC_WIDTH-1:0] sop_contrib,
//     output  logic signed [ACC_WIDTH-1:0] sop_fixed
//     );

    
//   always_comb begin
//     sop_fixed = '0;
//     for (int i = 0; i < VectorSize; i++) begin
//       sop_fixed += sop_contrib[i];
//     end
//   end
// endmodule

//N=32 area: 1269 delay: 10.708ns
//N=16 area: 582  delay: 8.777 ns
//N=8  area: 222  delay: 7.094ns

// module add_comp #(
//     parameter int unsigned VectorSize = 32,
//     parameter int unsigned WIDTH_I = 96,     // bit-width of inputs
//     parameter int unsigned WIDTH_O = 96  // bit-width of outputs
// )(
//     input logic signed[VectorSize-1:0][WIDTH_I-1:0] operands_i,
//     output logic signed[WIDTH_O-1:0] sum_o,
//     output logic signed[WIDTH_O-1:0] carry_o
// );
//     localparam int unsigned N_A = VectorSize/2;
//     localparam int unsigned N_B = VectorSize - N_A;

//     generate
//         if (VectorSize==1) begin
//             assign sum_o = operands_i[0];
//             assign carry_o = '0;
//         end
//         else if(VectorSize==2) begin
//             assign sum_o = operands_i[0];
//             assign carry_o = operands_i[1];
//         end
//         else if(VectorSize==3) begin
//             compressor_3to2 #(
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) u_compressor_3to2(
//                 .operands_i(operands_i),
//                 .sum_o(sum_o),
//                 .carry_o(carry_o)
//             );
//         end
//         else if(VectorSize==4) begin
//             compressor_4to2 #(
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) u_compressor_4to2(
//                 .operands_i(operands_i),
//                 .sum_o(sum_o),
//                 .carry_o(carry_o)
//             );
//         end
//         else begin
//             logic signed [N_A-1:0][WIDTH_I-1:0] operands_i_A;
//             logic signed [N_B-1:0][WIDTH_I-1:0] operands_i_B;
//             logic signed [WIDTH_O-1:0] sum_o_A;
//             logic signed [WIDTH_O-1:0] sum_o_B;
//             logic signed [WIDTH_O-1:0] carry_o_A;
//             logic signed [WIDTH_O-1:0] carry_o_B;

//             // Divide the inputs into two chunks
//             assign operands_i_A = operands_i[N_A-1:0];
//             assign operands_i_B = operands_i[VectorSize-1:N_A];

//             csa_tree #(
//                 .VectorSize(N_A),
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) ua_csa_tree(
//                 .operands_i(operands_i_A),
//                 .sum_o(sum_o_A),
//                 .carry_o(carry_o_A)
//             );

//             csa_tree #(
//                 .VectorSize(N_B),
//                 .WIDTH_I(WIDTH_I),
//                 .WIDTH_O(WIDTH_O)
//             ) ub_csa_tree(
//                 .operands_i(operands_i_B),
//                 .sum_o(sum_o_B),
//                 .carry_o(carry_o_B)
//             );

//             logic signed [3:0][WIDTH_O-1:0] operands_i_C ;
//             assign operands_i_C = {sum_o_A, carry_o_A, sum_o_B, carry_o_B};
            
//             compressor_4to2 #(
//                 .WIDTH_I(WIDTH_O),
//                 .WIDTH_O(WIDTH_O)
//             ) uc_compressor_4to2(
//                 .operands_i(operands_i_C),
//                 .sum_o(sum_o),
//                 .carry_o(carry_o)
//             );
//         end
//     endgenerate
// endmodule

// module compressor_4to2 #(
//     parameter int unsigned WIDTH_I = 8,                             // bit-width of inputs
//     parameter int unsigned WIDTH_O = WIDTH_I + 5   // bit-width of outputs
// )(
//     input logic signed [3:0][WIDTH_I-1:0] operands_i,
//     output logic signed [WIDTH_O-1:0] sum_o,
//     output logic signed [WIDTH_O-1:0] carry_o
// );
//     logic signed[WIDTH_I-1:0] sum;
//     logic [WIDTH_I:0] cin;
//     logic [WIDTH_I-1:0] cout;
//     logic signed[WIDTH_I-1:0] carry;
    
//     assign cin[0] = 1'b0;

//     // Cascaded 5:3 counters according to input bit-width
//     generate
//         genvar i;
//         for(i=0;i<WIDTH_I;i++) begin
//             counter_5to3 u_counter_5to3(
//                 .x1(operands_i[0][i]),
//                 .x2(operands_i[1][i]),
//                 .x3(operands_i[2][i]),
//                 .x4(operands_i[3][i]),
//                 .cin(cin[i]),
//                 .sum(sum[i]),
//                 .carry(carry[i]),
//                 .cout(cout[i])
//             );
//             assign cin[i+1] = cout[i];
//         end
//     endgenerate

//     logic carry_temp;
    
//     assign sum_o = sum;
//     assign carry_temp = carry[WIDTH_I-1]|cin[WIDTH_I];

//     // 1) 组合出未扩展的 carry_o 原始向量 (宽度 WIDTH_I + 2)
//     logic signed [WIDTH_I:0] carry_raw;
//     assign carry_raw = {carry_temp, carry[WIDTH_I-2:0], 1'b0};

//     // 2) 按符号位扩展到 WIDTH_O 位
//     assign carry_o = {{(WIDTH_O-(WIDTH_I+1)){carry_raw[WIDTH_I]}}, carry_raw};
// endmodule

// module counter_5to3(
//     input logic x1,x2,x3,x4,cin,
//     output logic sum,carry,cout
// );
//     assign sum = x1 ^ x2 ^ x3 ^ x4 ^ cin;
//     assign cout = (x1 ^ x2) & x3 | ~(x1 ^ x2) & x1;
//     assign carry = (x1 ^ x2 ^ x3 ^ x4) & cin | ~(x1 ^ x2 ^ x3 ^ x4) & x4;
// endmodule