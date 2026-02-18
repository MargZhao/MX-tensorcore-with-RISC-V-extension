module fp32_accumulator#(
    parameter ACC_WIDTH = 32,
    parameter EXP_WIDTH  = 8,
    parameter DST_MAN_WIDTH = 23,
    parameter SCALE_WIDTH = 8
)(
    input logic a_sgn,
    input logic signed [SCALE_WIDTH:0] a_exp,
    input logic [ACC_WIDTH-1:0] a_man,
    input logic b_sgn,
    input logic signed [EXP_WIDTH-1:0] b_exp,
    input logic [DST_MAN_WIDTH-1:0] b_man,
    output logic out_sgn,
    output logic signed [EXP_WIDTH-1:0] out_exp,
    output logic [DST_MAN_WIDTH-1:0] out_man
);

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
    logic b_is_nonzero;
    
    assign b_is_nonzero = (b_exp != 0); // 简单判断，忽略 Subnormal
    assign b_man_full   = b_is_nonzero ? {1'b1, b_man} : '0;
    

    always_comb begin
        exp_diff = signed'(a_exp) - signed'({b_exp[EXP_WIDTH-1],b_exp});
        if (exp_diff > 0) begin
            // A has larger exponent
            exp_large      = a_exp;
            mant_a_shifted = a_man;//20 = 8 + 12
            mant_b_shifted = {b_man_full,{(ACC_WIDTH-DST_MAN_WIDTH-1){1'b0}}} >> exp_diff;
        end else if (exp_diff < 0) begin
            exp_large      = b_exp;
            mant_a_shifted = a_man >> (-exp_diff);
            mant_b_shifted = {b_man_full,{(ACC_WIDTH-DST_MAN_WIDTH-1){1'b0}}};
        end else begin
            exp_large      = a_exp;
            mant_a_shifted = a_man;
            mant_b_shifted = {b_man_full,{(ACC_WIDTH-DST_MAN_WIDTH-1){1'b0}}};
        end
    end

    // -------------------------------------------------------------------------
    // Step 3: Apply signs and add/subtract (Full Signed Arithmetic)
    // -------------------------------------------------------------------------
    
    // 1. 扩展位宽以防止溢出，并转换为带符号补码
    // 如果 a_sgn 是 1 (负)，则取 -mant (2's comp)
    // 如果 a_sgn 是 0 (正)，则取 +mant
    
    logic signed [ACC_WIDTH+2:0] val_a_signed;
    logic signed [ACC_WIDTH+2:0] val_b_signed;
    logic signed [ACC_WIDTH+2:0] result_signed;

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
    assign sum_negative = result_signed[ACC_WIDTH+2];

    // 结果的绝对值 (Magnitude)
    // 如果结果是负数，取反加一变回正数绝对值；如果是正数，保持不变
    always_comb begin
        if (sum_negative) 
            mant_abs = -result_signed; // 2's complement to magnitude
        else 
            mant_abs = result_signed;
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

    logic [ACC_WIDTH:0] mant_abs;
    always_comb begin
        lead_shift = leading_one_pos(mant_abs);

        // Shift left until MSB = 1
        mant_norm_abs = mant_abs << lead_shift;
        exp_adjust    = -lead_shift + 1;
    end

    // -------------------------------------------------------------------------
    // Step 5: Assign output fields
    // -------------------------------------------------------------------------
    always_comb begin
        out_sgn = sum_negative;
        out_exp  = (mant_norm_abs == '0) ? exp_large : (exp_large + exp_adjust);
        out_man = mant_norm_abs[ACC_WIDTH-1 -:DST_MAN_WIDTH]; 
    end


endmodule