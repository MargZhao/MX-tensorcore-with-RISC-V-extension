module stage8_fp32_accumulator#(
    parameter MANT_WIDTH = 8,
    parameter NORM_MAN_WIDTH = 16,
    parameter EXP_WIDTH  = 5
)(
    input logic clr,
    input logic a_sgn,
    input logic [EXP_WIDTH-1:0] a_exp,
    input logic [NORM_MAN_WIDTH-1:0] a_man,
    input logic b_sgn,
    input logic [EXP_WIDTH-1:0] b_exp,
    input logic [NORM_MAN_WIDTH-1:0] b_man,
    output logic out_sgn,
    output logic [EXP_WIDTH-1:0] out_exp,
    output logic [NORM_MAN_WIDTH-1:0] out_man
);

    //Align exponent
    logic signed [EXP_WIDTH-1:0] exp_diff;
    logic [NORM_MAN_WIDTH:0] mant_a_shifted, mant_b_shifted;
    logic signed [EXP_WIDTH-1:0] exp_large;
    logic b_sgn_sel;
    logic signed [EXP_WIDTH:0] b_exp_sel;
    logic [NORM_MAN_WIDTH:0] b_man_sel;

    
    assign  {b_sgn_sel,b_exp_sel,b_man_sel} = (clr)? 22'h0:{b_sgn,b_exp,b_man};
    

    always_comb begin
        exp_diff = a_exp - b_exp;
        if (exp_diff > 0) begin
            // A has larger exponent
            exp_large      = a_exp;
            mant_a_shifted = {a_man};//20 = 8 + 12
            mant_b_shifted = b_man_sel >> exp_diff;
        end else if (exp_diff < 0) begin
            exp_large      = b_exp_sel;
            mant_a_shifted = {a_man} >> (-exp_diff);
            mant_b_shifted = b_man_sel;
        end else begin
            exp_large      = a_exp;
            mant_a_shifted = a_man;
            mant_b_shifted = b_man_sel;
        end
    end

    // -------------------------------------------------------------------------
    // Step 3: Apply signs and add/subtract
    // -------------------------------------------------------------------------
    logic signed [NORM_MAN_WIDTH+1:0] mant_sum_signed; // 18 bits
    always_comb begin
        if (a_sgn == b_sgn)
            mant_sum_signed = $signed({1'b0, mant_a_shifted}) + $signed({1'b0, mant_b_shifted});
        else
            mant_sum_signed = $signed({1'b0, mant_a_shifted}) - $signed({1'b0, mant_b_shifted});
    end

    // Determine sign of result
    logic sum_negative;
    assign sum_negative = mant_sum_signed[NORM_MAN_WIDTH+1];

    // -------------------------------------------------------------------------
    // Step 4: Normalize result
    // -------------------------------------------------------------------------
    logic [NORM_MAN_WIDTH:0] mant_norm_abs;
    logic [4:0] lead_shift; // normalization shift
    logic signed [EXP_WIDTH-1:0] exp_adjust;

    function automatic [4:0] leading_one_pos(input logic [NORM_MAN_WIDTH:0] val);
        int i;
        leading_one_pos = 0;
        for (i = NORM_MAN_WIDTH; i >= 0; i--) begin
            if (val[i]) begin
                leading_one_pos = NORM_MAN_WIDTH - i;
                break;
            end
        end
    endfunction

    logic [NORM_MAN_WIDTH:0] mant_abs;
    always_comb begin
        mant_abs = sum_negative ? -mant_sum_signed[NORM_MAN_WIDTH:0] : mant_sum_signed[NORM_MAN_WIDTH:0];
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
        out_man = mant_norm_abs[NORM_MAN_WIDTH:1]; 
    end


endmodule