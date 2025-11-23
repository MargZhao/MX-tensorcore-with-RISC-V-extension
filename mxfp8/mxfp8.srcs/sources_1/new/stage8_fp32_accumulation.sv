(* keep_hierarchy = "yes" *)
(* keep_hierarchy = "yes" *)
module stage8_fp32_accumulator #(
    parameter int unsigned ACC_WIDTH      = 32,   // internal accumulated mantissa width (including guard)
    parameter int unsigned EXP_WIDTH      = 8,    // DST exponent width (unbiased signed range stored externally)
    parameter int unsigned DST_MAN_WIDTH  = 23,   // FP32 fraction width (no hidden bit)
    parameter int unsigned SCALE_WIDTH    = 8     // input scale width (bias-free magnitude width); scale_aligned is [SCALE_WIDTH:0]
) (
    input  logic                          clr,      // clear the accumulator (makes result zero)
    // operand A: from adder_tree (already aligned to global anchor scale)
    input  logic                          a_sgn,    // sign of accumulated fixed-point sum
    input  logic signed [SCALE_WIDTH:0]   a_exp,    // signed unbiased exponent of 'a' (scale_aligned)
    input  logic [ACC_WIDTH-1:0]          a_man,    // fixed-point mantissa magnitude for 'a' (unsigned magnitude, sign in a_sgn)
    // operand B: an existing FP32-like accumulator value stored as (sign, unbiased_exp, fraction)
    input  logic                          b_sgn,    // sign of stored FP32 value
    input  logic signed [EXP_WIDTH-1:0]   b_exp,    // signed unbiased exponent of stored FP32 (reg_exp)
    input  logic [DST_MAN_WIDTH-1:0]      b_man,    // stored FP32 fraction (no hidden bit)
    // outputs (unbiased exponent + fraction)
    output logic                          out_sgn,
    output logic signed [EXP_WIDTH-1:0]   out_exp,  // signed unbiased exponent
    output logic [DST_MAN_WIDTH-1:0]      out_man
);

    // -------------------------------------------------------------------------
    // local derived params
    // -------------------------------------------------------------------------
    // full mantissa width for b when expanded to accumulator dynamic range:
    localparam int unsigned B_FULL_WIDTH = 1 + DST_MAN_WIDTH; // hidden bit + fraction
    // we will align b into ACC_WIDTH bits (unsigned magnitude) when forming fixed-point value
    // width for leading-one detection
    localparam int unsigned LEAD_POS_WIDTH = $clog2(ACC_WIDTH+1);

    // -------------------------------------------------------------------------
    // Form full mantissa for B (include hidden bit for normalized numbers)
    // Note: external logic sets b_exp==0 for zero -> treat hidden bit = 0
    // -------------------------------------------------------------------------
    logic [B_FULL_WIDTH-1:0] b_mant_full; // contains hidden + fraction
    always_comb begin
        if (b_exp == '0) begin
            // zero or denorm treated as zero here (if you need denorm support, expand here)
            b_mant_full = '0;
        end else begin
            // normalized FP32: implicit 1
            b_mant_full = {1'b1, b_man};
        end
    end

    // -------------------------------------------------------------------------
    // Expand both operands to ACC_WIDTH aligned unsigned magnitudes (before sign)
    // We'll create signed representations then add/sub.
    // Convention:
    //   fixed_value = mantissa_mag * 2^(exp)   (both unbiased)
    // a_man is ACC_WIDTH bits magnitude (coming from adder_tree)
    // b_mant_full is B_FULL_WIDTH bits -> expand to ACC_WIDTH
    // -------------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] a_fix; // signed extended with sign bit applied later
    logic signed [ACC_WIDTH-1:0] b_fix;

    // compute exponent difference: delta = a_exp - b_exp
    logic signed [SCALE_WIDTH:0] exp_diff_full; // a_exp is SCALE_WIDTH+1 bits; b_exp is EXP_WIDTH bits but both are unbiased signed
    // widen b_exp to match scale width before subtraction
    logic signed [SCALE_WIDTH:0] b_exp_wide;
    // extend/regress signed properly
    always_comb begin
        // sign-extend b_exp into SCALE_WIDTH+1
        b_exp_wide = $signed({ {(SCALE_WIDTH+1-EXP_WIDTH){b_exp[EXP_WIDTH-1]}}, b_exp});
        exp_diff_full = $signed(a_exp) - $signed(b_exp_wide);
    end

    // shift/align b mantissa into ACC_WIDTH magnitude
    // First expand b_mant_full to ACC_WIDTH bits left-justified (MSB at ACC_WIDTH-1)
    logic [ACC_WIDTH-1:0] b_mant_align_left;
    localparam int unsigned B_EXPAND_SHIFT = ACC_WIDTH - B_FULL_WIDTH;
    assign b_mant_align_left = {b_mant_full, {B_EXPAND_SHIFT{1'b0}}}; // left-justified

    // For a_man we assume a_man is already right-justified at LSB (i.e., fixed-point integer magnitude)
    // If your adder_tree produced different alignment, adjust accordingly.

    // Now perform shifts depending on exp_diff_full:
    // if exp_diff_full >= 0 : a has larger exponent => shift b right by exp_diff_full
    // else shift a right by -exp_diff_full

    // temporary unsigned aligned mantissas (magnitude)
    logic [ACC_WIDTH-1:0] mant_a_aligned_u;
    logic [ACC_WIDTH-1:0] mant_b_aligned_u;

    always_comb begin
        // default
        mant_a_aligned_u = a_man;
        mant_b_aligned_u = b_mant_align_left;

        if (clr) begin
            mant_a_aligned_u = '0;
            mant_b_aligned_u = '0;
        end else begin
            if (exp_diff_full >= 0) begin
                // shift b right (logical) by min(exp_diff, ACC_WIDTH-1)
                if (exp_diff_full >= ACC_WIDTH) begin
                    mant_b_aligned_u = '0;
                end else begin
                    mant_b_aligned_u = b_mant_align_left >> exp_diff_full;
                end
                mant_a_aligned_u = a_man;
            end else begin
                // shift a right by -exp_diff_full
                if (-exp_diff_full >= ACC_WIDTH) begin
                    mant_a_aligned_u = '0;
                end else begin
                    mant_a_aligned_u = a_man >> (-exp_diff_full);
                end
                mant_b_aligned_u = b_mant_align_left;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Apply signs and add/subtract
    // Convert magnitudes to signed with their sign bits
    // -------------------------------------------------------------------------
    logic signed [ACC_WIDTH:0] a_signed_ext; // one extra bit for detect overflow
    logic signed [ACC_WIDTH:0] b_signed_ext;
    logic signed [ACC_WIDTH:0] sum_signed_ext;

    always_comb begin
        a_signed_ext = a_sgn ? -$signed({1'b0, mant_a_aligned_u}) : $signed({1'b0, mant_a_aligned_u});
        b_signed_ext = b_sgn ? -$signed({1'b0, mant_b_aligned_u}) : $signed({1'b0, mant_b_aligned_u});
        sum_signed_ext = a_signed_ext + b_signed_ext;
        if (clr) sum_signed_ext = '0;
    end

    // -------------------------------------------------------------------------
    // Determine sign and absolute magnitude
    // -------------------------------------------------------------------------
    logic result_sgn_local;
    logic [ACC_WIDTH-1:0] result_mag_u; // magnitude absolute value
    logic signed [ACC_WIDTH:0] sum_signed_abs_ext;

    always_comb begin
        result_sgn_local = sum_signed_ext[ACC_WIDTH]; // sign bit of signed extended
        // absolute value
        if (sum_signed_ext[ACC_WIDTH] == 1'b1) begin
            sum_signed_abs_ext = -sum_signed_ext;
        end else begin
            sum_signed_abs_ext = sum_signed_ext;
        end
        result_mag_u = sum_signed_abs_ext[ACC_WIDTH-1:0];
    end

    // -------------------------------------------------------------------------
    // Normalize: find leading one position, shift-left to obtain normalized fraction
    // We want fraction result: 1.<DST_MAN_WIDTH bits> stored in out_man (no hidden bit)
    // and compute new unbiased exponent = max(a_exp, b_exp) + adjust
    // Note: when sum==0 -> output zero (exp=0, man=0)
    // -------------------------------------------------------------------------
   
 
    int shift_left;
    logic [ACC_WIDTH-1:0] norm_shifted;
    logic signed [SCALE_WIDTH+1:0] exp_adjust; // may need extra bit for +- range
    logic signed [EXP_WIDTH-1:0] exp_large_wide; // selected base exponent (widened then truncated)

    logic [$clog2(ACC_WIDTH)-1:0] leading_pos;
    logic                        leading_valid;

    // instantiate priority encoder
    leading_one_detector #(
        .ACC_WIDTH(ACC_WIDTH)
    ) u_lod (
        .in(result_mag_u),
        .pos(leading_pos),
        .valid(leading_valid)
    );

    // compute exponent adjustment
    always_comb begin
        if (!leading_valid) begin
            norm_shifted = '0;
            exp_adjust  = 0;
        end else begin
            // shift left so leading one is at DST_MAN_WIDTH position
            int shift_left;
            shift_left = DST_MAN_WIDTH - leading_pos;
            if (shift_left >= 0)
                norm_shifted = result_mag_u << shift_left;
            else
                norm_shifted = result_mag_u >> (-shift_left);

            exp_adjust = leading_pos - DST_MAN_WIDTH;
        end
    end

    // compute final out_exp by adding exp_large_wide + exp_adjust
    // We must convert exp_large_wide (width SCALE_WIDTH+1) down to EXP_WIDTH signed (careful with range)
    logic signed [EXP_WIDTH-1:0] out_exp_local;
    logic signed [SCALE_WIDTH+1:0] tmp_sum;
    logic signed [SCALE_WIDTH+1:0] exp_large_sext;
    logic signed [SCALE_WIDTH+1:0] exp_adjust_sext;
    logic signed [SCALE_WIDTH+1:0] exp_sum_wide;
    always_comb begin
        if (result_mag_u == '0) begin
            out_exp_local = '0;
        end else begin
            // widen both to a signed temp of sufficient width and add
            // sign-extend exp_large_wide (SCALE_WIDTH+1) to SCALE_WIDTH+2 maybe
            tmp_sum = $signed({exp_large_wide, 1'b0}) >>> 1; // cheap way to convert width, actually better do direct sign-extension
            // better: sign-extend correctly:
            exp_large_sext = $signed({ {(SCALE_WIDTH+1- (SCALE_WIDTH+1)){exp_large_wide[SCALE_WIDTH]}}, exp_large_wide});
            // final exponent:
            // out_exp = exp_large_wide + exp_adjust
            // But exp_adjust is signed int; convert to same width
            exp_adjust_sext = exp_adjust;
            exp_sum_wide = exp_large_sext + exp_adjust_sext;
            // truncate / saturate to EXP_WIDTH if necessary (here simple truncation)
            out_exp_local = $signed(exp_sum_wide[EXP_WIDTH-1:0]);
        end
    end

    // Extract fraction bits for out_man:
    // norm_shifted currently holds normalized mantissa where its MSB is at index ACC_WIDTH-1 if fully left-shifted.
    // We constructed it so that the leading 1 is at bit index DST_MAN_WIDTH (see above). To get fraction bits (no hidden bit),
    // we take bits [DST_MAN_WIDTH-1 : DST_MAN_WIDTH - DST_MAN_WIDTH] => i.e., the next DST_MAN_WIDTH bits right of the leading 1.
    // More concretely, choose frac_msb_index = DST_MAN_WIDTH-1 after shift.
    logic [DST_MAN_WIDTH-1:0] out_frac_local;
    always_comb begin
        if (result_mag_u == '0) begin
            out_frac_local = '0;
        end else begin
            // After the shift in norm_shifted, the leading one should be at bit index DST_MAN_WIDTH
            // So take bits [DST_MAN_WIDTH-1 : 0]
            out_frac_local = norm_shifted[DST_MAN_WIDTH-1:0];
        end
    end

    // -------------------------------------------------------------------------
    // Assign outputs (combinational)
    // -------------------------------------------------------------------------
    always_comb begin
        out_sgn = (clr) ? 1'b0 : result_sgn_local;
        out_exp = (clr) ? '0 : out_exp_local;
        out_man = (clr) ? '0 : out_frac_local;
        // Note: out_man is fraction (no hidden bit). To create IEEE-754 you must later add bias when forming exponent
    end

endmodule

module leading_one_detector #(
    parameter ACC_WIDTH = 36
)(
    input  logic [ACC_WIDTH-1:0] in,
    output logic [$clog2(ACC_WIDTH)-1:0] pos,
    output logic                    valid
);

    // This is a combinational priority encoder without long loops
    // Implemented as a casez tree
    always_comb begin
        pos = '0;
        valid = |in;
        casex (in)
            {1'b1, {(ACC_WIDTH-1){1'bx}}}: pos = ACC_WIDTH-1;
            {1'b0, 1'b1, {(ACC_WIDTH-2){1'bx}}}: pos = ACC_WIDTH-2;
            {2'b00, 1'b1, {(ACC_WIDTH-3){1'bx}}}: pos = ACC_WIDTH-3;
            {3'b000, 1'b1, {(ACC_WIDTH-4){1'bx}}}: pos = ACC_WIDTH-4;
            {4'b0000, 1'b1, {(ACC_WIDTH-5){1'bx}}}: pos = ACC_WIDTH-5;
            // ... generate pattern down to 0
            default: pos = 0;
        endcase
    end
endmodule


// module stage8_fp32_accumulator#(
//     parameter ACC_WIDTH = 32,
//     parameter EXP_WIDTH  = 8,
//     parameter DST_MAN_WIDTH = 23,
//     parameter SCALE_WIDTH = 8
// )(
//     input logic clr,
//     input logic a_sgn,
//     input logic [SCALE_WIDTH:0] a_exp,
//     input logic [ACC_WIDTH-1:0] a_man,
//     input logic b_sgn,
//     input logic [EXP_WIDTH-1:0] b_exp,
//     input logic [ACC_WIDTH-1:0] b_man,
//     output logic out_sgn,
//     output logic [EXP_WIDTH-1:0] out_exp,
//     output logic [DST_MAN_WIDTH-1:0] out_man
// );

//     //Align exponent
//     logic signed [EXP_WIDTH-1:0] exp_diff;
//     logic [ACC_WIDTH:0] mant_a_shifted, mant_b_shifted;
//     logic signed [EXP_WIDTH-1:0] exp_large;
//     logic b_sgn_sel;
//     logic signed [EXP_WIDTH:0] b_exp_sel;
//     logic [ACC_WIDTH:0] b_man_sel;

    
//     assign  {b_sgn_sel,b_exp_sel,b_man_sel} = (clr)? 22'h0:{b_sgn,b_exp,b_man};
    

//     always_comb begin
//         exp_diff = signed'(a_exp) - signed'({b_exp[EXP_WIDTH-1],b_exp});
//         else if (exp_diff > 0) begin
//             // A has larger exponent
//             exp_large      = a_exp;
//             mant_a_shifted = {a_man};//20 = 8 + 12
//             mant_b_shifted = b_man_sel >> exp_diff;
//         end else if (exp_diff < 0) begin
//             exp_large      = b_exp_sel;
//             mant_a_shifted = {a_man} >> (-exp_diff);
//             mant_b_shifted = b_man_sel;
//         end else begin
//             exp_large      = a_exp;
//             mant_a_shifted = a_man;
//             mant_b_shifted = b_man_sel;
//         end
//     end

//     // -------------------------------------------------------------------------
//     // Step 3: Apply signs and add/subtract
//     // -------------------------------------------------------------------------
//     logic signed [NORM_MAN_WIDTH+1:0] mant_sum_signed; // 18 bits
//     always_comb begin
//         if (a_sgn == b_sgn)
//             mant_sum_signed = $signed({1'b0, mant_a_shifted}) + $signed({1'b0, mant_b_shifted});
//         else
//             mant_sum_signed = $signed({1'b0, mant_a_shifted}) - $signed({1'b0, mant_b_shifted});
//     end

//     // Determine sign of result
//     logic sum_negative;
//     assign sum_negative = mant_sum_signed[NORM_MAN_WIDTH+1];

//     // -------------------------------------------------------------------------
//     // Step 4: Normalize result
//     // -------------------------------------------------------------------------
//     logic [NORM_MAN_WIDTH:0] mant_norm_abs;
//     logic [4:0] lead_shift; // normalization shift
//     logic signed [EXP_WIDTH-1:0] exp_adjust;

//     function automatic [4:0] leading_one_pos(input logic [NORM_MAN_WIDTH:0] val);
//         int i;
//         leading_one_pos = 0;
//         for (i = NORM_MAN_WIDTH; i >= 0; i--) begin
//             if (val[i]) begin
//                 leading_one_pos = NORM_MAN_WIDTH - i;
//                 break;
//             end
//         end
//     endfunction

//     logic [NORM_MAN_WIDTH:0] mant_abs;
//     always_comb begin
//         mant_abs = sum_negative ? -mant_sum_signed[NORM_MAN_WIDTH:0] : mant_sum_signed[NORM_MAN_WIDTH:0];
//         lead_shift = leading_one_pos(mant_abs);

//         // Shift left until MSB = 1
//         mant_norm_abs = mant_abs << lead_shift;
//         exp_adjust    = -lead_shift + 1;
//     end

//     // -------------------------------------------------------------------------
//     // Step 5: Assign output fields
//     // -------------------------------------------------------------------------
//     always_comb begin
//         out_sgn = sum_negative;
//         out_exp  = (lead_shift == 'd0) ? 5'h0 : (exp_large + exp_adjust);
//         out_man = mant_norm_abs[NORM_MAN_WIDTH:1]; 
//     end


// endmodule