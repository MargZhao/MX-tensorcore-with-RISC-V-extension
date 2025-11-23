(* keep_hierarchy = "yes" *)
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