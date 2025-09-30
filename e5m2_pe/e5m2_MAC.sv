module e5m2_MAC #(
    //parameters
) (
    input logic [7:0] a,
    input logic [7:0] b,
    output logic [15:0] result //output as fp16 or fp32, TODO: verify this, should we convert it back in FP8 again?

);
    logic a_sign; logic b_sign;
    logic [4:0] a_exp; logic [4:0] b_exp;
    

endmodule