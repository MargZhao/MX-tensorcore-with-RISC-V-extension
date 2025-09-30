/*E5M2
inf:        S.11111.00
NaN:        S.11111.{01, 10, 11}
zero:       S.00000.00
normal_max: S.11110.11 = ±57,344
normal_min: S.00001.00 = ±2^(-14)
subnor_max: S.00000.11 = ±0.75 * 2^(-14)
subnor_min: S.00000.012 = ±2^(-16)
exp_bias:   15
*/

//scalar mul, should be vector tho
module e5m2_MAC #(
    //parameters
) (
    /* implement these later
    input  logic                 clk_i,
    input  logic                 rst_ni,
    output logic                 a_ready_o,
    input  logic                 a_valid_o,
    output logic                 b_ready_o,
    input  logic                 b_valid_o,
    output logic                 b_ready_o,
    input  logic                 b_valid_o,
    input  logic                 mode_i,                  
    */
    input  logic [7:0]           a_i,
    input  logic [7:0]           b_i,
    output logic [15:0]          c_o 
    //output as fp16 or fp32, TODO: verify this, should we convert it back in FP8 again?

);
    logic a_sign; logic b_sign;
    logic [4:0] a_exp; logic [4:0] b_exp;
    logic [1:0] a_man; logic [1:0] b_man;
    logic c_sign;
    


endmodule