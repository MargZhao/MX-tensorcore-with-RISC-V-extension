`timescale 1ns/1ps

module tb_e5m2_MULT;

  ////////////// DUT I/O //////////////
  logic [7:0] a_i, b_i;
  logic [7:0] c_o;
  logic       inf, NaN;

  ////////////// Instantiate DUT //////////////
  e5m2_MAC dut (
    .a_i(a_i),
    .b_i(b_i),
    .c_o(c_o),
    .inf(inf),
    .NaN(NaN)
  );

  ////////////// Local parameters for decoding //////////////
  localparam int EXP_BITS  = 5;
  localparam int MANT_BITS = 2;
  localparam int EXP_BIAS  = 15;

  ////////////// Utility functions //////////////
  // Decode E5M2 -> real
  function real e5m2_to_real(input logic [7:0] val);
    logic sign;
    int exp;
    int mant;
    real frac;
    begin
      sign = val[7];
      exp  = val[6:2];
      mant = val[1:0];
      if (exp == 0 && mant == 0)
        e5m2_to_real = 0.0;
      else if (exp == 0) begin
        frac = mant / 4.0;  // 2^(-MANT_BITS)
        e5m2_to_real = (sign ? -1 : 1) * frac * (2.0 ** (1 - EXP_BIAS));
      end else if (exp == 31 && mant == 0)
        e5m2_to_real = (sign ? -1 : 1) * 1.0 / 0.0; // Inf
      else if (exp == 31)
        e5m2_to_real = 0.0 / 0.0; // NaN
      else begin
        frac = 1.0 + mant / 4.0;
        e5m2_to_real = (sign ? -1 : 1) * frac * (2.0 ** (exp - EXP_BIAS));
      end
    end
  endfunction

  // Encode from real to E5M2 (approx model)
  function automatic logic [7:0] real_to_e5m2(input real val);
  real absval, scaled;
  int exp, mant;
  logic sign;
  logic [4:0] exp_field;

  begin
    sign = (val < 0);
    absval = (sign) ? -val : val;

    if (absval == 0.0)
      return {sign, 7'b0000000};
    else if ($isinf(absval))
      return {sign, 7'b1111100};
    else if ($isnan(absval))
      return {sign, 7'b1111101};

    exp = $clog2(absval);

    if (exp + 15 >= 31)
      return {sign, 7'b1111100}; // inf
    else if (exp + 15 <= 0)
      return {sign, 7'b0000001}; // subnormal approx

    scaled = absval / (2.0 ** exp);
    mant   = int'((scaled - 1.0) * 4.0 + 0.5);
    
    exp_field = exp + 15;

    return {sign, exp_field, mant[1:0]};
  end
endfunction


  ////////////// Test procedure //////////////
  task automatic check(input logic [7:0] a, input logic [7:0] b);
    real a_real, b_real, expect_real, dut_real;
    logic [7:0] expect_e5m2;
    begin
      a_i = a;
      b_i = b;
      #1;  // small delta for DUT

      a_real = e5m2_to_real(a);
      b_real = e5m2_to_real(b);
      expect_real = a_real * b_real;
      expect_e5m2 = real_to_e5m2(expect_real);
      dut_real = e5m2_to_real(c_o);

      $display("\n----------------------------------------");
      $display("A = 0x%h (%f),  B = 0x%h (%f)", a, a_real, b, b_real);
      $display("Expected (SW): 0x%h  (%e)", expect_e5m2, expect_real);
      $display("DUT Output  : 0x%h  (%e)", c_o, dut_real);
      if (NaN) $display("DUT flag: NaN");
      if (inf) $display("DUT flag: Inf");
      $display("----------------------------------------\n");
    end
  endtask

  ////////////// Test Vectors //////////////
  initial begin
    $display("------ E5M2 Multiplier Testbench Start ------");

    // (1) Zero * Anything
    check(8'b00000000, 8'b00000000);  // 0 * 0
    check(8'b00000000, 8'b01111011);  // 0 * max normal
    check(8'b00000000, 8'b11111000);  // 0 * -inf

    // (2) Inf & NaN
    check(8'b01111100, 8'b01111100);  // +inf * +inf
    check(8'b11111100, 8'b01111100);  // -inf * +inf
    check(8'b01111100, 8'b00000000);  // inf * 0 → NaN
    check(8'b01111101, 8'b00000000);  // NaN * 0

    // (3) Normal * Normal
    check(8'b00101000, 8'b00101000);  // small * small
    check(8'b01111011, 8'b01111011);  // max * max

    // (4) Subnormal * Normal
    check(8'b00000001, 8'b00100000);  // submin * normal
    check(8'b00000011, 8'b00100000);  // submax * normal

    // (5) Random Signs
    check(8'b10100000, 8'b00100000);  // -normal * +normal
    check(8'b10100000, 8'b10100000);  // -normal * -normal

    $display("------ E5M2 Multiplier Testbench End ------");
    $finish;
  end

endmodule
