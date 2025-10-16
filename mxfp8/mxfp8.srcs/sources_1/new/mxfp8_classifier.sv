module mxfp8_classifier#(
    parameter mxfp8_pkg::fp_format_e FpFormat = mxfp8_pkg::E5M2,
    parameter int unsigned             NumOperands = 1,
    parameter int unsigned             MX = 1,
    localparam int unsigned WIDTH = mxfp8_pkg::fp_width(FpFormat)
) (
    input  logic                [NumOperands-1:0][WIDTH-1:0] operands_i,
    output mxfp8_pkg::fp_info_t [NumOperands-1:0]            info_o
);

  localparam int unsigned EXP_BITS = mxfp8_pkg::exp_bits(FpFormat);
  localparam int unsigned MAN_BITS = mxfp8_pkg::man_bits(FpFormat);

  // Type definition
  typedef struct packed {
    logic                sign;
    logic [EXP_BITS-1:0] exponent;
    logic [MAN_BITS-1:0] mantissa;
  } fp_t;

  // Iterate through all operands
  for (genvar op = 0; op < int'(NumOperands); op++) begin : gen_num_values

    fp_t value;
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

        if(MX==1 && FpFormat == mxfp8_pkg::E5M2) begin
            is_inf    =  ((value.exponent == '1) && (value.mantissa == '0));
            is_nan    =  ((value.exponent == '1) && (value.mantissa != '0));
            is_normal =  (value.exponent != '0) && (value.exponent != '1);
        end else if (MX==1 && FpFormat == mxfp8_pkg::E4M3)begin
            // No inf in E4M3
            is_inf    = 1'b0;
            is_nan    = ((value.exponent == '1) && (value.mantissa == '1));
            is_normal = (value.exponent != '0) && !is_nan;
        end else begin
            //other data type, add later
            is_inf    =  1'b1;
            is_nan    =  1'b1;
            is_normal =  1'b1;
        end

        is_zero       = (value.exponent == '0) && (value.mantissa == '0);
        is_subnormal  = (value.exponent == '0) && !is_zero;
        is_signalling = is_nan && (value.mantissa[MAN_BITS-1] == 1'b0);
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
    end
  end

endmodule