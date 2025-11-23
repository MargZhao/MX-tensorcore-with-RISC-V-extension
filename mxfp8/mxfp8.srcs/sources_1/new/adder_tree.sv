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
    output logic signed [ACC_WIDTH-1:0] sum_man,
    output logic signed [PROD_EXP_WIDTH-1:0] sum_sgn
);

    // ------------------------------------------------------------
    // 1) exp_max
    // ------------------------------------------------------------
    (* keep_hierarchy = "yes" *)
    exp_max #(
        .VectorSize(VectorSize),
        .EXPW(PROD_EXP_WIDTH)
    ) u_exp_max (
        .exp_sum(exp_sum),
        .exp_max(exp_max)
    );
    
    assign scale_aligned = signed'(scale_sum) + signed'(exp_max);

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

    // ------------------------------------------------------------
    // 4) CSA tree + CPA
    // ------------------------------------------------------------
    // logic signed [ACC_WIDTH-2:0] final_sum;
    // logic signed [ACC_WIDTH-2:0] final_carry;
    // (* keep_hierarchy = "yes" *)
    // csa_tree #(
    //     .VectorSize(VectorSize),
    //     .WIDTH_I(NORM_MAN_WIDTH),
    //     .WIDTH_O(ACC_WIDTH-1)
    // ) u_tree (
    //     .operands_i(man_align),
    //     .sum_o(final_sum),
    //     .carry_o(final_carry)
    // );

    // assign sum_all = final_sum + final_carry;
 
    logic signed [ACC_WIDTH-1:0] sum_all;
    always_comb begin
        sum_all = '0;
        for (int i = 0; i < VectorSize; i++) begin
            sum_all += man_align[i];
        end
    end

    always_comb begin : sign_extract
        sum_sgn = sum_all[ACC_WIDTH-1];

        if (sum_sgn) begin
            // 负数 → 取反 + 1，取高 NORM_MAN_WIDTH 位
            sum_man = (~sum_all[ACC_WIDTH-1 -: NORM_MAN_WIDTH]) + 1'b1;
        end else begin
            sum_man = sum_all[ACC_WIDTH-1 -: NORM_MAN_WIDTH];
        end
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

    logic signed [NORM_MAN_WIDTH-1:0] man_ext [VectorSize];
    logic signed [NORM_MAN_WIDTH-1:0] shifted  [VectorSize];

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


module csa_tree #(
    parameter int unsigned VectorSize = 32,
    parameter int unsigned WIDTH_I = 8,     // bit-width of inputs
    parameter int unsigned WIDTH_O = WIDTH_I + 4 + 1   // bit-width of outputs
)(
    input logic signed[VectorSize-1:0][WIDTH_I-1:0] operands_i,
    output logic signed[WIDTH_O-1:0] sum_o,
    output logic signed[WIDTH_O-1:0] carry_o
);
    localparam int unsigned N_A = VectorSize/2;
    localparam int unsigned N_B = VectorSize - N_A;

    generate
        if (VectorSize==1) begin
            assign sum_o = operands_i[0];
            assign carry_o = '0;
        end
        else if(VectorSize==2) begin
            assign sum_o = operands_i[0];
            assign carry_o = operands_i[1];
        end
        else if(VectorSize==3) begin
            compressor_3to2 #(
                .WIDTH_I(WIDTH_I),
                .WIDTH_O(WIDTH_O)
            ) u_compressor_3to2(
                .operands_i(operands_i),
                .sum_o(sum_o),
                .carry_o(carry_o)
            );
        end
        else if(VectorSize==4) begin
            compressor_4to2 #(
                .WIDTH_I(WIDTH_I),
                .WIDTH_O(WIDTH_O)
            ) u_compressor_4to2(
                .operands_i(operands_i),
                .sum_o(sum_o),
                .carry_o(carry_o)
            );
        end
        else begin
            logic signed [N_A-1:0][WIDTH_I-1:0] operands_i_A;
            logic signed [N_B-1:0][WIDTH_I-1:0] operands_i_B;
            logic signed [WIDTH_O-1:0] sum_o_A;
            logic signed [WIDTH_O-1:0] sum_o_B;
            logic signed [WIDTH_O-1:0] carry_o_A;
            logic signed [WIDTH_O-1:0] carry_o_B;

            // Divide the inputs into two chunks
            assign operands_i_A = operands_i[N_A-1:0];
            assign operands_i_B = operands_i[VectorSize-1:N_A];

            csa_tree #(
                .VectorSize(N_A),
                .WIDTH_I(WIDTH_I),
                .WIDTH_O(WIDTH_O)
            ) ua_csa_tree(
                .operands_i(operands_i_A),
                .sum_o(sum_o_A),
                .carry_o(carry_o_A)
            );

            csa_tree #(
                .VectorSize(N_B),
                .WIDTH_I(WIDTH_I),
                .WIDTH_O(WIDTH_O)
            ) ub_csa_tree(
                .operands_i(operands_i_B),
                .sum_o(sum_o_B),
                .carry_o(carry_o_B)
            );

            logic signed [3:0][WIDTH_O-1:0] operands_i_C ;
            assign operands_i_C = {sum_o_A, carry_o_A, sum_o_B, carry_o_B};
            
            compressor_4to2 #(
                .WIDTH_I(WIDTH_O),
                .WIDTH_O(WIDTH_O)
            ) uc_compressor_4to2(
                .operands_i(operands_i_C),
                .sum_o(sum_o),
                .carry_o(carry_o)
            );
        end
    endgenerate
endmodule

module compressor_4to2 #(
    parameter int unsigned WIDTH_I = 8,                             // bit-width of inputs
    parameter int unsigned WIDTH_O = WIDTH_I + 5   // bit-width of outputs
)(
    input logic signed [3:0][WIDTH_I-1:0] operands_i,
    output logic signed [WIDTH_O-1:0] sum_o,
    output logic signed [WIDTH_O-1:0] carry_o
);
    logic signed[WIDTH_I-1:0] sum;
    logic [WIDTH_I:0] cin;
    logic [WIDTH_I-1:0] cout;
    logic signed[WIDTH_I-1:0] carry;
    
    assign cin[0] = 1'b0;

    // Cascaded 5:3 counters according to input bit-width
    generate
        genvar i;
        for(i=0;i<WIDTH_I;i++) begin
            counter_5to3 u_counter_5to3(
                .x1(operands_i[0][i]),
                .x2(operands_i[1][i]),
                .x3(operands_i[2][i]),
                .x4(operands_i[3][i]),
                .cin(cin[i]),
                .sum(sum[i]),
                .carry(carry[i]),
                .cout(cout[i])
            );
            assign cin[i+1] = cout[i];
        end
    endgenerate

    logic carry_temp;
    
    assign sum_o = sum;
    assign carry_temp = carry[WIDTH_I-1]|cin[WIDTH_I];

    // 1) 组合出未扩展的 carry_o 原始向量 (宽度 WIDTH_I + 2)
    logic signed [WIDTH_I:0] carry_raw;
    assign carry_raw = {carry_temp, carry[WIDTH_I-2:0], 1'b0};

    // 2) 按符号位扩展到 WIDTH_O 位
    assign carry_o = {{(WIDTH_O-(WIDTH_I+1)){carry_raw[WIDTH_I]}}, carry_raw};
endmodule

module counter_5to3(
    input logic x1,x2,x3,x4,cin,
    output logic sum,carry,cout
);
    assign sum = x1 ^ x2 ^ x3 ^ x4 ^ cin;
    assign cout = (x1 ^ x2) & x3 | ~(x1 ^ x2) & x1;
    assign carry = (x1 ^ x2 ^ x3 ^ x4) & cin | ~(x1 ^ x2 ^ x3 ^ x4) & x4;
endmodule

