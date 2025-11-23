(* use_dsp = "no" *)
module mxdotp_mxfull #(
  // config
  parameter int unsigned             VectorSize    = 32,
  // const
  localparam int unsigned SRC_WIDTH  = mxfp8_pkg::fp_width(mxfp8_pkg::E5M2), // 源格式：E5M2 (可根据需要改)
  localparam int unsigned SCALE_WIDTH= 8,                                    // E8M0 共享 scale
  localparam int unsigned DST_WIDTH  = mxfp8_pkg::fp_width(mxfp8_pkg::FP32), // 目标格式：FP32
  localparam int unsigned NUM_OPERANDS = 2*VectorSize+1                      // 2 输入向量 + 1 结果
)(
  input  logic                        clk_i,
  input  logic                        rst_ni,

  // --------- 输入：向量 A/B（MXFP8）+ 共享 scale（E8M0） ---------
  input  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_a_i,
  input  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_b_i,
  input  mxfp8_pkg::fp_format_e                src_fmt_i,   // 源格式：E4M3 / E5M2
  input  mxfp8_pkg::fp_format_e                dst_fmt_i,   // 目标格式：当前假定为 FP32
  input  logic [1:0][SCALE_WIDTH-1:0]          scale_i,     // A/B 对应的 per-block 共享 scale（E8M0）

  // --------- 输入：旧的 accumulator C_old（FP32） ---------
  input  logic [DST_WIDTH-1:0]        acc_in_i,  // 上一轮 C

  // 控制
  input  logic                        clr,       // 清零内部 accumulator

  // --------- 输出：新的 C_new = dot(A,B) + C_old（FP32） ---------
  output logic [DST_WIDTH-1:0]        result_o
);

  // ----------------------------------------------------------------
  // 一些常量定义
  // ----------------------------------------------------------------
  // MXFP8 super format: mantissa 位数（不含隐含位）
  localparam int unsigned SUPER_SRC_MAN_WIDTH = 3;
  localparam int unsigned PRECISION_BITS      = SUPER_SRC_MAN_WIDTH + 1; // p = m+1 = 4
  localparam int unsigned SUPER_SRC_EXP_WIDTH = 5;

  // mantissa product / exponent sum 宽度
  localparam int unsigned PROD_MAN_WIDTH      = 2*PRECISION_BITS;        // 8 bits
  localparam int unsigned PROD_EXP_WIDTH      = SUPER_SRC_EXP_WIDTH + 2; // 给多一点 headroom

  // FP32 目标格式
  localparam int unsigned DST_MAN_BITS        = 23;
  localparam int unsigned DST_PRECISION_BITS  = DST_MAN_BITS + 1;        // 24

  // 固定小数点域的位置：real_value * 2^ANCHOR
  localparam int signed   ANCHOR              = 34;

  // E8M0 共享 scale 的 bias（和 FP32 exponent 一样）
  localparam int signed   SCALE_BIAS          = 127;

  // 累加器宽度（选择得比较保守）
  localparam int unsigned ACC_WIDTH           = 96;
  localparam int unsigned LZC_WIDTH           = $clog2(ACC_WIDTH+1);//7
  localparam int unsigned IDX_WIDTH           = $clog2(ACC_WIDTH);//7

  // ----------------------------------------------------------------
  // 1) classifier：拆 A/B 为 sign / exponent / mantissa
  // ----------------------------------------------------------------
  logic [VectorSize-1:0][SUPER_SRC_MAN_WIDTH-1:0]       a_man_i, b_man_i;
  logic unsigned [VectorSize-1:0][SUPER_SRC_EXP_WIDTH-1:0] a_exp_i, b_exp_i;
  logic [VectorSize-1:0]                                a_sign_i, b_sign_i;
  logic [VectorSize-1:0]                                a_isnormal, b_isnormal;

  mxfp8_pkg::fp_info_t [VectorSize-1:0]                 info_a, info_b;

  // operand A
  mxfp8_classifier #(
    .NumOperands        (VectorSize),
    .MX                 (1),
    .SUPER_SRC_MAN_WIDTH(SUPER_SRC_MAN_WIDTH),
    .SUPER_SRC_EXP_WIDTH(SUPER_SRC_EXP_WIDTH),
    .SRC_WIDTH          (SRC_WIDTH)
  ) u_mxfp8_classifier_a (
    .src_fmt_i          (src_fmt_i),
    .operands_i         (operands_a_i),
    .info_o             (info_a),
    .man_i              (a_man_i),
    .exp_i              (a_exp_i),
    .sign_i             (a_sign_i),
    .isnormal           (a_isnormal)
  );

  // operand B
  mxfp8_classifier #(
    .NumOperands        (VectorSize),
    .MX                 (1),
    .SUPER_SRC_MAN_WIDTH(SUPER_SRC_MAN_WIDTH),
    .SUPER_SRC_EXP_WIDTH(SUPER_SRC_EXP_WIDTH),
    .SRC_WIDTH          (SRC_WIDTH)
  ) u_mxfp8_classifier_b (
    .src_fmt_i          (src_fmt_i),
    .operands_i         (operands_b_i),
    .info_o             (info_b),
    .man_i              (b_man_i),
    .exp_i              (b_exp_i),
    .sign_i             (b_sign_i),
    .isnormal           (b_isnormal)
  );

  // ----------------------------------------------------------------
  // 2) mantissa 相乘 / exponent 相加 / sign XOR
  //    mxfp8_mult 输出：
  //    - man_prod   : mantissa 乘积 (整数)
  //    - exp_sum    : (rawA - bias) + (rawB - bias)  → “真实指数”
  //    - sign_prod  : 符号
  // ----------------------------------------------------------------
  logic [VectorSize-1:0][PROD_MAN_WIDTH-1:0]          man_prod;
  logic signed [VectorSize-1:0][PROD_EXP_WIDTH-1:0]   exp_sum;
  logic        [VectorSize-1:0]                       sign_prod;

  mxfp8_mult #(
    .VectorSize       (VectorSize),
    .PROD_MAN_WIDTH   (PROD_MAN_WIDTH),
    .PROD_EXP_WIDTH   (PROD_EXP_WIDTH)
  ) u_mxfp8_mult (
    .A_mant           (a_man_i),
    .B_mant           (b_man_i),
    .A_exp            (a_exp_i),
    .B_exp            (b_exp_i),
    .A_sign           (a_sign_i),
    .B_sign           (b_sign_i),
    .A_isnormal       (a_isnormal),
    .B_isnormal       (b_isnormal),
    .src_fmt_i        (src_fmt_i),
    .man_prod         (man_prod),
    .exp_sum          (exp_sum),    // = (rawA - bias) + (rawB - bias)
    .sign_prod        (sign_prod)
  );

  // 有符号 product mantissa
  logic signed [VectorSize-1:0][PROD_MAN_WIDTH:0] man_prod_signed;

  genvar gi;
  generate
    for (gi = 0; gi < VectorSize; gi++) begin : gen_signed_prod
      always_comb begin
        man_prod_signed[gi] = sign_prod[gi] ?
                              -$signed({1'b0, man_prod[gi]}) :
                               $signed({1'b0, man_prod[gi]});
      end
    end
  endgenerate

  // ----------------------------------------------------------------
  // 3) 计算 per-block 共享 scale 的真实指数偏移
  //    scale_i 是 E8M0（8-bit，bias=127）：
  //    scale_real = scale_raw - 127
  //    两个向量共享：总 exponent 再加 (scaleA_real + scaleB_real)
  // ----------------------------------------------------------------
  logic signed [SCALE_WIDTH:0]       scale_add_real;

  always_comb begin
    scale_add_real = ($signed({1'b0, scale_i[0]}) - SCALE_BIAS)
                   + ($signed({1'b0, scale_i[1]}) - SCALE_BIAS);
  end

  // ----------------------------------------------------------------
  // 4) 把每个 product 映射到统一 fixed-point 域：
  //   p = 1+3 = 4 
  //   ANCHOR = 34
  //   A_real = mantA_int * 2^{expA_real - (p-1)} * 2^{scaleA_real}
  //   B_real = mantB_int * 2^{expB_real - (p-1)} * 2^{scaleB_real}
  //   prod_real = man_prod * 2^{exp_sum + scaleA_real + scaleB_real - 2*(p-1)}
  //
  //   fixed 域定义：fixed = real * 2^{ANCHOR}
  //
  //   → prod_fixed = man_prod_signed << (exp_sum + scale_add_real - 2*(p-1) + ANCHOR)
  // ----------------------------------------------------------------
  logic signed [VectorSize-1:0][ACC_WIDTH-1:0] sop_contrib;
  integer i;

  localparam int signed P_SHIFT = -2*(PRECISION_BITS-1) + ANCHOR; // = -2*3 + 34 = 28
  int signed exp_full;
  int signed sh;
  logic signed [ACC_WIDTH-1:0] prod_ext;
  
  always_comb begin
    for (i = 0; i < VectorSize; i++) begin
      // 真实 exponent：exp_sum + scaleA_real + scaleB_real
      
      exp_full = exp_sum[i] + scale_add_real; // 这里 exp_sum 是 real exp，scale_add_real 也是 real

      // shift = exp_full - 2*(p-1) + ANCHOR
      sh = exp_full + P_SHIFT;

      // 限制 shift 到 [-ACC_WIDTH+1, ACC_WIDTH-1] 以避免过度移位
      if (sh > (ACC_WIDTH-1)) sh = ACC_WIDTH-1;
      if (sh < -(ACC_WIDTH-1)) sh = -(ACC_WIDTH-1);

      // sign-extend man_prod 到 ACC_WIDTH
      
      prod_ext = {{(ACC_WIDTH-PROD_MAN_WIDTH-1){man_prod_signed[i][PROD_MAN_WIDTH]}},
                  man_prod_signed[i]};

      if (sh >= 0) begin
        sop_contrib[i] = prod_ext <<< sh;
      end else begin
        sop_contrib[i] = prod_ext >>> -sh;
      end
    end
  end

  // ----------------------------------------------------------------
  // 5) SoP 累加：得到 dot-product 的 fixed-point 结果 sop_fixed
  // ----------------------------------------------------------------
  // N= 8, delay:  12.447 ns  area: 480 LUTS
  // N=16, delay:  14.812 ns  area: 860 LUTS
  // N = 32, delay: 15.275 ns area: 1628 LUTS
  logic signed [ACC_WIDTH-1:0] sop_fixed;
  // logic signed [ACC_WIDTH-2:0] sum_csa;
  // logic signed [ACC_WIDTH-2:0] carry_csa;
  always_comb begin
    sop_fixed = '0;
    for (i = 0; i < VectorSize; i++) begin
      sop_fixed += sop_contrib[i];
    end
  end
  // csa_tree #(
  //   .VectorSize(VectorSize),
  //   .WIDTH_I(ACC_WIDTH),
  //   .WIDTH_O(ACC_WIDTH-1)
  // )(
  //   .operands_i(sop_contrib),
  //   .sum_o      (sum_csa),
  //   .carry_o    (carry_csa)
  // );

  // assign sop_fixed =  $signed({sum_csa[ACC_WIDTH-2],   sum_csa}) +
  //                    $signed({carry_csa[ACC_WIDTH-2], carry_csa});

  // ----------------------------------------------------------------
  // 6) 把旧 accumulator C_old (FP32) 也映射到同一 fixed-point 域
  //
  //    C_real = mantC_int * 2^{expC_real - 23}
  //           = mantC_int * 2^{(expC_raw-127) - 23}
  //
  //    C_fixed = mantC_int << ( (expC_raw - 127) - 23 + ANCHOR )
  // ----------------------------------------------------------------
  logic        acc_in_sign;
  logic [7:0]  acc_in_exp_raw;
  logic [22:0] acc_in_frac;
  logic [DST_PRECISION_BITS-1:0] acc_in_mant;   // 24 bits

  assign acc_in_sign    = acc_in_i[31];
  assign acc_in_exp_raw = acc_in_i[30:23];
  assign acc_in_frac    = acc_in_i[22:0];
  assign acc_in_mant    = {1'b1, acc_in_frac};  // 加隐含位

  logic signed [ACC_WIDTH-1:0] acc_fixed;
  int signed exp_c_real;
  int signed sh_acc;
  logic signed [ACC_WIDTH-1:0] mant_ext;
  logic signed [ACC_WIDTH-1:0] tmp;
  always_comb begin
    if (acc_in_exp_raw == 8'd0 && acc_in_frac == 23'd0) begin
      acc_fixed = '0; // 0
    end else begin
      
      exp_c_real = $signed(acc_in_exp_raw) - 127;   // FP32 real exponent

      // shift = (expC_real - 23 + ANCHOR)
      
      sh_acc = exp_c_real - 23 + ANCHOR;

      if (sh_acc > (ACC_WIDTH-1))  sh_acc = ACC_WIDTH-1;
      if (sh_acc < -(ACC_WIDTH-1)) sh_acc = -(ACC_WIDTH-1);

      
      mant_ext = {{(ACC_WIDTH-DST_PRECISION_BITS){1'b0}}, acc_in_mant};

      
      if (sh_acc >= 0) begin
        tmp = mant_ext <<< sh_acc;
      end else begin
        tmp = mant_ext >>> -sh_acc;
      end

      acc_fixed = acc_in_sign ? -tmp : tmp;
    end
  end

  // ----------------------------------------------------------------
  // 7) 总 fixed-point 和：total_fixed = sop_fixed + acc_fixed
  // ----------------------------------------------------------------
  logic signed [ACC_WIDTH-1:0] total_fixed;

  always_comb begin
    if (clr) begin
      total_fixed = sop_fixed;   // 清零时，忽略旧 C
    end else begin
      total_fixed = sop_fixed + acc_fixed;
    end
  end

  // ----------------------------------------------------------------
  // 8) 归一化 total_fixed → FP32：LZC + exponent + mantissa
  //
  //    fixed 域定义： total_fixed = real_total * 2^{ANCHOR}
  //
  //    找到最高位 j：
  //      real_total = norm_int * 2^{j - 23 - ANCHOR}
  //      exp_real_out = j - ANCHOR
  //      exp_raw_out  = exp_real_out + 127
  // ----------------------------------------------------------------
  logic                   total_sign;
  logic signed [ACC_WIDTH-1:0] total_abs;
  logic [LZC_WIDTH-1:0]   lzc;
  logic [IDX_WIDTH-1:0]   msb_idx;

  assign total_sign = total_fixed[ACC_WIDTH-1];
  assign total_abs  = total_sign ? -total_fixed : total_fixed;
    // 定义在 always_comb 外面
    integer j;
    integer lzc_int;
    integer msb_int;

    // LZC：找最高位 1 的 index
    always_comb begin
    // 默认值
    lzc     = '0;
    msb_idx = '0;
    lzc_int = 0;
    msb_int = 0;

    if (total_abs == '0) begin
        // 全零的情况，lzc/msb_idx 设成 0 就行了，后面你已经 special case 处理 total_abs == 0
        lzc     = '0;
        msb_idx = '0;
    end else begin
        for (j = ACC_WIDTH-1; j >= 0; j = j - 1) begin
        if (total_abs[j]) begin
            msb_int = j;
            lzc_int = (ACC_WIDTH-1) - j;
            break;
        end
        end
        // 把 integer 压成你定义好的位宽
        lzc     = lzc_int[LZC_WIDTH-1:0];
        msb_idx = msb_int[IDX_WIDTH-1:0];
    end
    end

  // 根据 msb_idx 构造 FP32 exponent & mantissa
  logic [7:0]  exp_fp32;
  logic [22:0] man_fp32;
  int signed E_real;
  int signed shift_for_mant;
  logic [DST_PRECISION_BITS-1:0] mant_full;
  always_comb begin
    if (total_abs == '0) begin
      exp_fp32 = 8'd0;
      man_fp32 = 23'd0;
    end else begin
      
      E_real  = $signed(msb_idx) - ANCHOR; // real exponent
      exp_fp32 = E_real + 127;            // FP32 bias

      // 归一化：把最高位移到 bit 23（mantissa 总共 24 bits 含隐含位）
      
      if (msb_idx >= (DST_PRECISION_BITS-1)) begin
        shift_for_mant = msb_idx - (DST_PRECISION_BITS-1);
        mant_full      = total_abs >> shift_for_mant;
      end else begin
        shift_for_mant = (DST_PRECISION_BITS-1) - msb_idx;
        mant_full      = total_abs << shift_for_mant;
      end

      // mant_full[23] 是隐含 1，mant_full[22:0] 是 fraction（简单截断，不做 rounding）
      man_fp32 = mant_full[DST_PRECISION_BITS-2:0];
    end
  end

  // ----------------------------------------------------------------
  // 9) 寄存器：输出新的 C（FP32）
  // ----------------------------------------------------------------
  logic        reg_sgn;
  logic [7:0]  reg_exp;
  logic [22:0] reg_man;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reg_sgn <= 1'b0;
      reg_exp <= 8'd0;
      reg_man <= 23'd0;
    end else if (clr) begin
      reg_sgn <= 1'b0;
      reg_exp <= 8'd0;
      reg_man <= 23'd0;
    end else begin
      reg_sgn <= total_sign;
      reg_exp <= exp_fp32;
      reg_man <= man_fp32;
    end
  end

  assign result_o = {reg_sgn, reg_exp, reg_man};

endmodule
