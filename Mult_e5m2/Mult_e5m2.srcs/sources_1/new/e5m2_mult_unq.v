`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/11 16:55:34
// Design Name: 
// Module Name: e5m2_mult_unq
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module e5m2_mult_unq#(
    //parameters
)(
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
    output logic [12:0]           c_o,
    output logic                 inf,
    output logic                 NaN,
    output logic                 underflow
    //store intermediate in E6M4
    //output of MAC should be fp16 or fp32, TODO: verify this, should we convert it back in FP8 again?
);

    //////////////////////////////////parameters//////////////////////////////////////////////
    localparam int MANT_BITS  = 2;
    localparam int EXP_BITS   = 5;
    localparam int EXP_MAX    = (1<<EXP_BITS)-1;   // 31
    localparam int EXP_BIAS   = 15;                // e5 bias
    localparam int SIG_NORM_HI_BIT = MANT_BITS;    // for e5m2, 2 (so '1xx' => [4..7])
 
    //////////////////////////////////variables////////////////////////////////////////////////       
    logic a_sign;                 logic b_sign;              logic c_sign;
    logic [EXP_BITS-1:0]  a_exp;  logic [EXP_BITS-1:0]    b_exp;
    logic [MANT_BITS-1:0] a_man;  logic [MANT_BITS-1:0]   b_man;
    logic [EXP_BITS:0]    c_exp;  logic [(MANT_BITS+1)*2-1:0] c_man;
    //////////////////////////////////Functions////////////////////////////////////////////////
    //get sign, mentissa, exp
    function automatic void unpack(
    input  logic [7:0] in,
    output logic       sign,
    output logic [EXP_BITS-1:0] exp,
    output logic [MANT_BITS-1:0] mant
    );
    sign = in[7];
    exp  = in[6:2];
    mant = in[1:0];
    endfunction
    
    //////////////////////////////////Main logic////////////////////////////////////////////////
    
    /*E5M2
    inf:        S.11111.00
    NaN:        S.11111.{01, 10, 11}
    zero:       S.00000.00
    normal_max: S.11110.11 = ±57,344
    normal_min: S.00001.00 = ±2^(-14)
    subnor_max: S.00000.11 = ±0.75 * 2^(-14)
    subnor_min: S.00000.01 = ±2^(-16)
    exp_bias:   15
    */

    //exponent add
    always_comb begin
        unpack(a_i, a_sign, a_exp, a_man);
        unpack(b_i, b_sign, b_exp, b_man);
        if((a_exp==EXP_MAX&&a_man!=0)||(b_exp==EXP_MAX&&b_man!=0))begin
            //NaN prod anything is NaN
            c_exp = 6'b011111;
            c_man = 4'b0100;
            c_sign = a_sign^b_sign;
            NaN = 1;
            inf = 0;
        end else if((a_exp==EXP_MAX&&a_man==0)||(b_exp==EXP_MAX&&b_man==0)) begin
            //when one of them is inf
            if((a_exp==0&&a_man==0)||(b_exp==0&&b_man==0))begin
                //when one inf one zero, set as NaN
                c_exp = 6'b011111;
                c_man = 4'b0100;
                c_sign = a_sign^b_sign;
                NaN = 1;
                inf = 0;
                underflow = 0;
            end else begin
                //otherwise also inf
                c_exp = 6'b011111;
                c_man = 0;
                c_sign = a_sign^b_sign;
                NaN = 0;
                inf = 1;
                underflow = 0;
            end
        end else if ((a_exp==0&&a_man==0)||(b_exp==0&&b_man==0)) begin
            //zero
            if((a_exp==EXP_MAX&&a_man==0)||(b_exp==EXP_MAX&&b_man==0))begin
                //when one inf one zero, set as NaN、
                //could be deleted later, since this case is already covred above
                c_exp = 6'b011111;
                c_man = 4'b0100;
                c_sign = a_sign^b_sign;
                NaN = 1;
                inf = 0;
                underflow = 0;
            end else begin
                c_exp = 0;
                c_man = 0;
                c_sign = a_sign^b_sign;
                NaN = 0;
                inf = 0;
                underflow = 0;
            end    
        end else begin
            c_sign = a_sign^b_sign;
            NaN = 0;
            if (a_exp==0&&b_exp==0) begin   
                //subnormal*subnormal
                underflow = ({1'b0, a_exp} + {1'b0, b_exp} < EXP_BIAS) ? 1 : 0;
                if(underflow)begin
                    c_exp = 0;
                    c_man = 0;
                end else begin
                    c_man = {1'b0,a_man}*{1'b0,b_man};
                    c_exp = a_exp + b_exp-EXP_BIAS+2;
                end
            end else if (a_exp==0&&b_exp!=0) begin
                //subnormal*normal
                underflow = ({1'b0, a_exp} + {1'b0, b_exp} < EXP_BIAS) ? 1 : 0;
                if(underflow)begin
                    c_exp = 0;
                    c_man = 0;
                end else begin
                    c_man = {1'b0,a_man}*{1'b1,b_man};
                    c_exp = a_exp + b_exp-EXP_BIAS+1;
                end
            end else if (a_exp!=0&&b_exp==0) begin
                //normal*subnormal
                underflow = ({1'b0, a_exp} + {1'b0, b_exp} < EXP_BIAS) ? 1 : 0;
                if(underflow)begin
                    c_exp = 0;
                    c_man = 0;
                end else begin
                    c_man = {1'b1,a_man}*{1'b0,b_man};
                    c_exp = a_exp + b_exp-EXP_BIAS+1;
                end
            end else begin
                //normal*normal
                underflow = ({1'b0, a_exp} + {1'b0, b_exp} < EXP_BIAS) ? 1 : 0;
                c_exp = a_exp + b_exp-EXP_BIAS;
                inf = c_exp[EXP_BITS];
                if (inf) begin
                    //TODO: overflow case
                    c_exp = 6'b011111;
                    c_man = 0;
                end else if(underflow) begin
                    c_exp = 0;
                    c_man = 0;
                    underflow = 1;
                end else begin
                    c_man = {1'b1,a_man}*{1'b1,b_man};
                    
                    //normalize
                    if(c_man[(MANT_BITS+1)*2-1])begin
                        c_exp = c_exp+1;
                        c_man = c_man>>1;
                    end
                end
            end
            
        end   
    end
    assign c_o = {c_sign,c_exp,c_man};
    

    

    //normally, Xa+Xb, Pa+Pb
    //remember when doing mult,加上尾数隐含的一位，比如mantissa：10， 实际大小为1.10
    //case like 1.10* 1.10 = 10.0100, need to put the extra 1 in the exponent
    //
endmodule
