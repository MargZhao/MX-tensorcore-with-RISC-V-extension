(* keep_hierarchy = "yes" *)
module stage8_fp32_accumulator#(
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
    logic [ACC_WIDTH:0] mant_a_shifted, mant_b_shifted;
    logic signed [EXP_WIDTH-1:0] exp_large;
    

    always_comb begin
        exp_diff = signed'(a_exp) - signed'({b_exp[EXP_WIDTH-1],b_exp});
        if (exp_diff > 0) begin
            // A has larger exponent
            exp_large      = a_exp;
            mant_a_shifted = {a_man};//20 = 8 + 12
            mant_b_shifted = b_man >> exp_diff;
        end else if (exp_diff < 0) begin
            exp_large      = b_exp;
            mant_a_shifted = {a_man} >> (-exp_diff);
            mant_b_shifted = b_man;
        end else begin
            exp_large      = a_exp;
            mant_a_shifted = a_man;
            mant_b_shifted = b_man;
        end
    end

    // -------------------------------------------------------------------------
    // Step 3: Apply signs and add/subtract
    // -------------------------------------------------------------------------
    logic signed [ACC_WIDTH+1:0] mant_sum_signed; // 18 bits
    always_comb begin
        if (a_sgn == b_sgn)
            mant_sum_signed = $signed({1'b0, mant_a_shifted}) + $signed({1'b0, mant_b_shifted});
        else
            mant_sum_signed = $signed({1'b0, mant_a_shifted}) - $signed({1'b0, mant_b_shifted});
    end

    // Determine sign of result
    logic sum_negative;
    assign sum_negative = mant_sum_signed[ACC_WIDTH+1];

    // -------------------------------------------------------------------------
    // Step 4: Normalize result
    // -------------------------------------------------------------------------
    logic [ACC_WIDTH:0] mant_norm_abs;
    logic [4:0] lead_shift; // normalization shift
    logic signed [EXP_WIDTH-1:0] exp_adjust;

    function automatic [4:0] leading_one_pos(input logic [ACC_WIDTH:0] val);
        int i;
        leading_one_pos = 0;
        for (i = ACC_WIDTH; i >= 0; i--) begin
            if (val[i]) begin
                leading_one_pos = ACC_WIDTH - i;
                break;
            end
        end
    endfunction

    logic [ACC_WIDTH:0] mant_abs;
    always_comb begin
        mant_abs = sum_negative ? -mant_sum_signed[ACC_WIDTH:0] : mant_sum_signed[ACC_WIDTH:0];
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
        out_exp  = (lead_shift == 'd0) ? 5'h0 : (exp_large + exp_adjust);
        out_man = mant_norm_abs[ACC_WIDTH-1 -:DST_MAN_WIDTH]; 
    end


endmodule