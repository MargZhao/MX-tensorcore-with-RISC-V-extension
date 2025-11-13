module mxfp8_classifier#(
    parameter int unsigned             NumOperands = 1,
    parameter int unsigned             MX = 1,
    parameter int unsigned             SUPER_SRC_MAN_WIDTH = 3,
    parameter int unsigned             SUPER_SRC_EXP_WIDTH = 5,
    parameter int unsigned             SRC_WIDTH = 8
) (
    input  mxfp8_pkg::fp_format_e src_fmt_i,
    input  logic                [NumOperands-1:0][SRC_WIDTH-1:0] operands_i,
    output mxfp8_pkg::fp_info_t [NumOperands-1:0]            info_o,
    output logic                [NumOperands-1:0][SUPER_SRC_MAN_WIDTH-1:0]    man_i ,
    output logic unsigned       [NumOperands-1:0][SUPER_SRC_EXP_WIDTH-1:0]    exp_i ,
    output logic                [NumOperands-1:0]            sign_i,
    output logic                [NumOperands-1:0]            isnormal
);

  //denote bitwidth of mant and exponent according to src_fmt_i
    logic unsigned[1:0] man_bits;
    logic unsigned[2:0] exp_bits;

    always_comb begin
        unique case (src_fmt_i)
            mxfp8_pkg::E5M2: begin
                exp_bits= 5;
                man_bits= 2;
            end
            mxfp8_pkg::E4M3: begin
                exp_bits = 4;
                man_bits = 3;
            end
            default: begin
                exp_bits = 0;
                man_bits = 0;
            end
        endcase
    end

  // Iterate through all operands
  for (genvar op = 0; op < int'(NumOperands); op++) begin : gen_num_values

    logic [SRC_WIDTH-1:0] value;
    logic is_boxed;
    logic is_normal;
    logic is_inf;
    logic is_nan;
    logic is_signalling;
    logic is_quiet;
    logic is_zero;
    logic is_subnormal;

    always_comb begin: classify_input
        value = operands_i[op];

        if(MX==1 && src_fmt_i == mxfp8_pkg::E5M2) begin
            is_inf    = (value[(SRC_WIDTH-2) -: 5] == '1) && (value[0 +: 2] == '0);
            is_nan    = (value[(SRC_WIDTH-2) -: 5] == '1) && (value[0 +: 2] != '0);
            is_normal = (value[(SRC_WIDTH-2) -: 5] != '0) && (value[(SRC_WIDTH-2) -: 5] != '1);
            is_zero   = (value[(SRC_WIDTH-2) -: 5] == '0) && (value[0 +: 2] == '0);
            exp_i[op] = value[(SRC_WIDTH-2) -: 5];
            is_subnormal  = (value[(SRC_WIDTH-2) -: 5] == '0) && !is_zero;
            is_signalling = is_nan && (value[0 +: 2] == 1'b0);
            man_i[op] = value[ 0+:2]<<1; 
        
        end else if (MX==1 && src_fmt_i == mxfp8_pkg::E4M3)begin
            // No inf in E4M3
            is_inf    = 1'b0;
            is_nan    = (value[(SRC_WIDTH-2) -: 4] == '1) && (value[0 +: 3] == '1);
            is_normal = (value[(SRC_WIDTH-2) -: 4] != '0) && !is_nan;
            is_zero       = (value[(SRC_WIDTH-2) -: 4] == '0) && (value[0 +: 3] == '0);
            exp_i[op] = {{1'b0},value[(SRC_WIDTH-2) -: 4]};
            is_subnormal  = (value[(SRC_WIDTH-2) -: 4] == '0) && !is_zero;
            is_signalling = is_nan && (value[0 +: 3] == 1'b0);
            man_i[op] = value[ 0+:3];
        end else begin
            //other data type, add later
            is_inf    =  1'b1;
            is_nan    =  1'b1;
            is_normal =  1'b1;
            is_zero   = 1'b1;
            exp_i[op] = {{1'b0},value[(SRC_WIDTH-2) -: 4]};
            is_subnormal  = 1'b1;
            is_signalling = 1'b1;
            man_i[op] = value[ 0+:3];
        end

        
        sign_i[op] = value[SRC_WIDTH-1];
       
        
        is_quiet      = is_nan && !is_signalling;
        // Assign output for current input
        info_o[op].is_normal     = is_normal;
        info_o[op].is_subnormal  = is_subnormal;
        info_o[op].is_zero       = is_zero;
        info_o[op].is_inf        = is_inf;
        info_o[op].is_nan        = is_nan;
        info_o[op].is_signalling = is_signalling;
        info_o[op].is_quiet      = is_quiet;
        info_o[op].is_boxed      = is_boxed;
        isnormal[op] = info_o[op].is_normal;
    end
  end


endmodule