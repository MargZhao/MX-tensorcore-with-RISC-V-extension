(* keep_hierarchy = "yes" *)
module adder_tree#(

    //config
    parameter int unsigned VectorSize= 4,
    parameter int unsigned PROD_EXP_WIDTH = 6,
    parameter int unsigned PROD_MAN_WIDTH = 8,
    parameter int unsigned NORM_MAN_WIDTH = 16,
    parameter int unsigned SCALE_WIDTH = 8

)
 (
    input  logic signed [PROD_EXP_WIDTH-1:0] exp_sum[VectorSize-1:0],
    input  logic [PROD_MAN_WIDTH-1:0] man_prod[VectorSize-1:0],
    input  logic [VectorSize-1:0] sgn_prod,
    input  logic [SCALE_WIDTH:0] scale_sum,
    output logic [SCALE_WIDTH:0] scale_aligned,
    output logic [NORM_MAN_WIDTH-1:0] sum_man,
    output logic sum_sgn
);
    logic signed [PROD_EXP_WIDTH-1:0] exp_max;
    logic [PROD_EXP_WIDTH-1:0]  exp_diff[VectorSize-1:0];
    logic signed [NORM_MAN_WIDTH-1:0]  man_align[VectorSize-1:0];
    logic signed [NORM_MAN_WIDTH-1:0] sum_ab,sum_cd;
    logic signed [NORM_MAN_WIDTH-1:0] sum_all; //16
    //Max Reduce
        always_comb begin: find_max
            exp_max = exp_sum[0];
            for (int i = 1; i < 4; i++)
                if (exp_sum[i] > exp_max)
                    exp_max = exp_sum[i];
        end

        always_comb begin: reduce_exp
            scale_aligned = scale_sum + exp_max;
            for (int i = 0; i < 4; i++)
                exp_diff[i] = exp_max - exp_sum[i];
        end
    //Alignment
        always_comb begin: alignment
            for (int i = 0; i < 4; i++) begin
                if(exp_diff[i] >= PROD_MAN_WIDTH) begin
                    man_align[i] = 'h0;
                end
                else begin
                    man_align[i] = sgn_prod[i] ?
                        -($signed({1'b0, man_prod[i], {(NORM_MAN_WIDTH-PROD_MAN_WIDTH-1){1'b0}}}) >>> exp_diff[i]) :
                        ($signed({1'b0, man_prod[i], {(NORM_MAN_WIDTH-PROD_MAN_WIDTH-1){1'b0}}}) >>> exp_diff[i]);
                end
            end
        end
    //AdderTree
        always_comb begin:adder_tree
            sum_ab  = man_align[0] + man_align[1];
            sum_cd  = man_align[2] + man_align[3];
            sum_all = sum_ab + sum_cd;
        end

    //Sign and 2's complement
    always_comb begin : sign_extract
        sum_sgn = sum_all[PROD_MAN_WIDTH-1];
        sum_man = sum_sgn ? (~sum_all + 1'b1) : sum_all;
    end

endmodule
