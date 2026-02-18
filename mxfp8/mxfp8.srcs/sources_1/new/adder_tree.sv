(* keep_hierarchy = "yes" *)
module adder_tree#(

    parameter int VectorSize= 32,
    parameter int PROD_EXP_WIDTH = 6,
    parameter int PROD_MAN_WIDTH = 8,
    parameter int NORM_MAN_WIDTH = 32,
    parameter int SCALE_WIDTH = 8,
    parameter int GUARD_BITS = $clog2(VectorSize),
    parameter int ACC_WIDTH  = NORM_MAN_WIDTH + GUARD_BITS + 1

)(
    input  logic signed  [VectorSize-1:0][PROD_EXP_WIDTH-1:0] exp_sum,
    input  logic [VectorSize-1:0][PROD_MAN_WIDTH-1:0] man_prod,
    input  logic [VectorSize-1:0] sgn_prod,
    input  logic signed [SCALE_WIDTH:0] scale_sum,
    output logic signed [SCALE_WIDTH:0] scale_aligned,
    output logic signed [NORM_MAN_WIDTH-1:0] sum_man,
    output logic signed [PROD_EXP_WIDTH-1:0] sum_sgn
);

    // ------------------------------------------------------------
    // 1) exp_max
    // ------------------------------------------------------------
    logic signed [PROD_EXP_WIDTH-1:0] exp_max;

    (* keep_hierarchy = "yes" *)
    exp_max #(
        .VectorSize(VectorSize),
        .EXPW(PROD_EXP_WIDTH)
    ) u_exp_max (
        .exp_sum(exp_sum),
        .exp_max(exp_max)
    );
    logic signed [SCALE_WIDTH:0] scale_exp;
    assign scale_exp = signed'(scale_sum) + signed'(exp_max)+1;

    // ------------------------------------------------------------
    // 2) diff = exp_max - exp_sum
    // ------------------------------------------------------------
    (* keep_hierarchy = "yes" *)
    logic signed [VectorSize-1:0][PROD_EXP_WIDTH-1:0] diff;

    exp_diff #(
        .VectorSize(VectorSize),
        .EXPW(PROD_EXP_WIDTH)
    ) u_exp_diff (
        .exp_max(exp_max),
        .exp_sum(exp_sum),
        .diff(diff)
    );

    // ------------------------------------------------------------
    // 3) align stage (barrel shifter inside)
    // ------------------------------------------------------------
    logic signed [VectorSize-1:0][NORM_MAN_WIDTH-1:0] man_align;
    (* keep_hierarchy = "yes" *)
    align_unit #(
        .VectorSize(VectorSize),
        .PROD_MAN_WIDTH(PROD_MAN_WIDTH),
        .NORM_MAN_WIDTH(NORM_MAN_WIDTH),
        .EXPW(PROD_EXP_WIDTH)
    ) u_align (
        .man_prod (man_prod),
        .sgn_prod (sgn_prod),
        .exp_diff (diff),
        .man_align(man_align)
    );
 
    logic signed [ACC_WIDTH-1:0] sum_all;
    always_comb begin
        sum_all = '0;
        for (int i = 0; i < VectorSize; i++) begin
            sum_all += $signed(man_align[i]);
        end
    end

    // -------------------------------------------------------------------------
    // Step 4: Normalize result
    // -------------------------------------------------------------------------
    logic [4:0] lead_shift; // normalization shift
    logic signed [PROD_EXP_WIDTH-1:0] exp_adjust;

    function automatic [4:0] leading_one_pos(input logic [ACC_WIDTH-1:0] val);
        int i;
        leading_one_pos = 0;
        for (i = ACC_WIDTH-1; i >= 0; i--) begin
            if (val[i]) begin
                break;
            end
            leading_one_pos += 1;
        end
    endfunction

    logic signed [ACC_WIDTH-1:0] mant_abs;
    logic signed [ACC_WIDTH-1:0] mant_norm_abs;
    always_comb begin
        sum_sgn = sum_all[ACC_WIDTH-1];
        mant_abs = (sum_sgn) ? -sum_all[ACC_WIDTH-1:0] : sum_all[ACC_WIDTH-1:0];
        lead_shift = leading_one_pos(mant_abs);

        // Shift left until MSB = 1
        mant_norm_abs = mant_abs << lead_shift;
        sum_man = mant_norm_abs[ACC_WIDTH-1-:NORM_MAN_WIDTH];
        exp_adjust    = -lead_shift + 1 + ACC_WIDTH -NORM_MAN_WIDTH;
        scale_aligned = scale_exp + exp_adjust;
    end


endmodule

module align_unit #(
    parameter int VectorSize = 32,
    parameter int PROD_MAN_WIDTH = 8,
    parameter int NORM_MAN_WIDTH = 32,
    parameter int EXPW = 6
)(
    input  logic [VectorSize-1:0][PROD_MAN_WIDTH-1:0] man_prod,
    input  logic [VectorSize-1:0] sgn_prod,
    input  logic [VectorSize-1:0][EXPW-1:0] exp_diff,

    output logic signed [VectorSize-1:0][NORM_MAN_WIDTH-1:0] man_align
);

    logic signed [VectorSize-1:0][NORM_MAN_WIDTH-1:0] man_ext ;
    logic signed [VectorSize-1:0][NORM_MAN_WIDTH-1:0] shifted ;

    generate
        for (genvar i = 0; i < VectorSize; i++) begin : G_ALIGN

            // Sign-extend
            always_comb begin
                man_ext[i] = $signed({
                    1'b0,
                    man_prod[i],
                    {(NORM_MAN_WIDTH-PROD_MAN_WIDTH-1){1'b0}}
                });

                if (sgn_prod[i])
                    man_ext[i] = -man_ext[i];
            end

            // Barrel shifter instance
            (* keep_hierarchy = "yes" *)
            barrel_shifter #(
                .WIDTH(NORM_MAN_WIDTH)
            ) u_bs (
                .din  (man_ext[i]),
                .shift(exp_diff[i][ $clog2(NORM_MAN_WIDTH)-1 : 0 ]),
                .dout (shifted[i])
            );

            // Too-large shift → zero
            always_comb begin
                if (exp_diff[i] >= NORM_MAN_WIDTH)
                    man_align[i] = '0;
                else
                    man_align[i] = shifted[i];
            end

        end
    endgenerate

endmodule

module exp_max #(
    parameter int VectorSize = 32,
    parameter int EXPW = 6
)(
    input  logic signed [VectorSize-1:0][EXPW-1:0] exp_sum,
    output logic signed [EXPW-1:0] exp_max
);
    always_comb begin
        exp_max = exp_sum[0];
        for (int i = 1; i < VectorSize; i++)
            if ($signed(exp_sum[i]) > $signed(exp_max))
                exp_max = exp_sum[i];
    end
endmodule

module exp_diff #(
    parameter int VectorSize = 32,
    parameter int EXPW = 6
)(
    input  logic signed [EXPW-1:0] exp_max,
    input  logic signed [VectorSize-1:0][EXPW-1:0] exp_sum,
    output logic signed [VectorSize-1:0][EXPW-1:0] diff
);

    always_comb begin
        for (int i = 0; i < VectorSize; i++)
            diff[i] = exp_max - exp_sum[i];
    end
endmodule

module barrel_shifter #(
    parameter int WIDTH = 32,
    parameter int SHIFTW = $clog2(WIDTH)
)(
    input  logic signed [WIDTH-1:0] din,
    input  logic [SHIFTW-1:0]       shift,
    output logic signed [WIDTH-1:0] dout
);
    logic signed [WIDTH-1:0] tmp;

    always_comb begin
        tmp = din;
        for (int k = 0; k < SHIFTW; k++)
            if (shift[k])
                tmp = tmp >>> (1 << k);

        dout = tmp;
    end
endmodule

