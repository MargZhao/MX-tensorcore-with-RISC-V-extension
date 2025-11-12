(* keep_hierarchy = "yes" *)
module stage7_normalize_accum (
    input  logic signed [15:0] sum_all,
    input  logic [9:0] scale_aligned,
    output logic norm_sgn,
    output logic signed [4:0] norm_exp,
    output logic [15:0] norm_man
);
    function automatic [4:0] leading_zero_detect(input logic [15:0] val);
        int count = 0;
        for (int i = 15; i >= 0; i--) begin
            if (val[i] == 1'b0)
                count++;
            else
                break;
        end
        return count[4:0];
    endfunction

    logic [4:0] lzd;
    logic [15:0] norm_man;
    logic signed [4:0] norm_exp;
    logic norm_sgn;

    always_comb begin
        norm_sgn = sum_all[15];
        lzd = leading_zero_detect(norm_sgn ? -sum_all : sum_all);
        norm_man = (norm_sgn ? -sum_all : sum_all) << lzd;
        norm_exp = (lzd == 'd16) ? 5'h0 : (scale_aligned - lzd + 3);
    end
endmodule
