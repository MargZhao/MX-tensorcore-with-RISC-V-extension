`timescale 1ns / 1ps

module mxfp8_dotp_tb;

  localparam int VectorSize   = 4;   // 你可以改回 32
  localparam int SRC_WIDTH    = 8;   // E5M2 = 8 bits
  localparam int SCALE_WIDTH  = 8;
  localparam int DST_WIDTH    = 32;


  //---------------------------
  // Test Parameters
  //---------------------------
  parameter int unsigned NumTests = 10;

  // -------------------------
  // DUT signals
  // -------------------------
  logic clk;
  logic rst_n;

  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_a_i;
  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_b_i;

  logic [1:0][SCALE_WIDTH-1:0] scale_i;

  mxfp8_pkg::fp_format_e src_fmt_i;
  mxfp8_pkg::fp_format_e dst_fmt_i;


  logic a_valid_i;
  logic b_valid_i;
  logic init_save_i;
  logic acc_clr_i;
  logic [DST_WIDTH-1:0] result_o;
  logic [DST_WIDTH-1:0] golden_result_o;

  // -------------------------
  // Clock
  // -------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // -------------------------
  // DUT
  // -------------------------
  mxfp8_dotp #(
    .VectorSize(VectorSize)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),

    .operands_a_i(operands_a_i),
    .operands_b_i(operands_b_i),
    .src_fmt_i(src_fmt_i),
    .dst_fmt_i(dst_fmt_i),
    .scale_i(scale_i),

    .a_valid_i(a_valid_i),
    .b_valid_i(b_valid_i),
    .init_save_i(init_save_i),
    .acc_clr_i(acc_clr_i),

    .result_o(result_o)
  );


  // -------------------------
  // Utility functions
  // -------------------------

 function automatic void mac_pe_golden(
    input  logic  [VectorSize-1:0][SRC_WIDTH-1:0] A_i,
    input  logic  [VectorSize-1:0][SRC_WIDTH-1:0] B_i,
    input  mxfp8_pkg::fp_format_e src_fmt_i,
    input  mxfp8_pkg::fp_format_e dst_fmt_i, // Used if output needs specific rounding, currently assumes FP32 out
    input  logic  [1:0][SCALE_WIDTH-1:0] scale_i,
    output logic  [DST_WIDTH-1:0] C_o
  );

    // Internal high-precision variables
    real acc_real;
    real val_a, val_b;
    real scale_a, scale_b;
    real final_result;
    
    // 1. Initialize Accumulator
    acc_real = 0.0;

    // 2. Compute the Dot Product
    for (int i = 0; i < VectorSize; i++) begin
        // Convert binary inputs to SystemVerilog real
        val_a = mxfp8_to_real(A_i[i], src_fmt_i);
        val_b = mxfp8_to_real(B_i[i], src_fmt_i);
        
        // MAC operation
        acc_real += val_a * val_b;
    end

    // 3. Apply Scaling
    // MXFP scales are E8M0 (unbiased exponent: 2^(val - 127))
    // We treat the 8-bit integer as an exponent directly.
    // Use standard pow function: 2.0^(exponent - bias)
    scale_a = 2.0 ** (real'(scale_i[0]) - 127.0);
    scale_b = 2.0 ** (real'(scale_i[1]) - 127.0);
    
    final_result = acc_real * scale_a * scale_b;

    // 4. Output Formatting
    // Convert the high-precision real to IEEE 754 Single Precision (32-bit) bits
    // If your OutDataWidth is different (e.g. 16 for BF16), this casting needs adjustment.
    C_o = $shortrealtobits(shortreal'(final_result));

endfunction

// =======================================================================
// Helper Function: Convert MXFP8 bits to Real
// =======================================================================
function automatic real mxfp8_to_real(
    input logic [SRC_WIDTH:0] data,
    input mxfp8_pkg::fp_format_e fmt
);
    logic sign;
    logic [4:0] exp5;
    logic [3:0] exp4;
    logic [1:0] mant2;
    logic [2:0] mant3;
    
    real result;
    int exponent;
    real fraction;
    
    sign = data[7];

    if (fmt == mxfp8_pkg::E5M2) begin
        // --- E5M2 Format (Standard IEEE-like) ---
        // S:1, E:5, M:2 | Bias = 15
        exp5 = data[6:2];
        mant2 = data[1:0];
        
        if (exp5 == '0) begin 
            // Subnormal: (-1)^S * 2^(1-Bias) * (0.Mant)
            if (mant2 == '0) return (sign) ? -0.0 : 0.0; // Zero
            exponent = 1 - 15;
            fraction = real'(mant2) / 4.0;
        end else begin
            // Normal: (-1)^S * 2^(Exp-Bias) * (1.Mant)
            exponent = int'(exp5) - 15;
            fraction = 1.0 + (real'(mant2) / 4.0);
        end
        
    end else begin
        // --- E4M3 Format (OCP/NVIDIA Standard) ---
        // S:1, E:4, M:3 | Bias = 7
        // Note: E4M3 has no Infinity, only NaN at 0x7F (S0 E1111 M111) and 0xFF (S1 E1111 M111)
        exp4 = data[6:3];
        mant3 = data[2:0];
        
        if (exp4 == '0) begin
            // Subnormal: (-1)^S * 2^(1-Bias) * (0.Mant)
            if (mant3 == '0) return (sign) ? -0.0 : 0.0;
            exponent = 1 - 7;
            fraction = real'(mant3) / 8.0;
        end else if (exp4 == 4'b1111 && mant3 == 3'b111) begin
            // NaN case in E4M3
            return 0.0; // Or handle as specific NaN logic
        end else begin
            // Normal
            exponent = int'(exp4) - 7;
            fraction = 1.0 + (real'(mant3) / 8.0);
        end
    end

    // Combine parts
    result = fraction * (2.0 ** exponent);
    return (sign) ? -result : result;

endfunction


  // FP8 → real   (Simple E5M2 decoder)
  function real fp8_to_real(input logic [7:0] fp);
    int exp;
    int man;
    int sgn;
    begin
      sgn = fp[7];
      exp = fp[6:2];
      man = fp[1:0];

      if (exp == 0)
        fp8_to_real = (sgn ? -1.0 : 1.0) * man * 2.0**(-2);
      else
        fp8_to_real = (sgn ? -1.0 : 1.0) * (1.0 + man / 4.0) * 2.0**(exp - 15);
    end
  endfunction

function real fp32_to_real(input logic [31:0] fp);
    int exp;
    int man;
    int sgn;
    begin
      sgn = fp[31];
      exp = fp[30 -:8];
      man = fp[22:0];

      if (exp == 0)
        fp32_to_real = (sgn ? -1.0 : 1.0) * man * 2.0**(-2);
      else
        fp32_to_real = (sgn ? -1.0 : 1.0) * (1.0 + man / 4.0) * 2.0**(exp - 127);
    end
  endfunction



  // -------------------------
  // Test procedure
  // -------------------------
  real ref_dot;
  real ref_a[VectorSize];
  real ref_b[VectorSize];

  initial begin
    $display("---- MXFP8 DOTP TESTBENCH START ----");

    // Waveform dump
    $dumpfile("dotp.vcd");
    $dumpvars(0, mxfp8_dotp_tb);

    rst_n = 0;
    acc_clr_i   = 1;
    src_fmt_i = mxfp8_pkg::E5M2;
    dst_fmt_i = mxfp8_pkg::FP32;
    for (int i=0;i<VectorSize;i++)begin
      operands_a_i[i] = '0;
      operands_b_i[i] = '0;
    end

    scale_i[0] = 127;
    scale_i[1] = 127;

    @(posedge clk);
    rst_n = 1;
    acc_clr_i   = 0;

    // -------------------------------------
    // TESTCASE 1：简单固定输入
    // -------------------------------------
    for (int i = 0; i < NumTests; i++) begin

      if(i== 0) begin
        //1.0,2.0,1.5,-4.0
        operands_a_i = {8'h3C,8'h40,8'h3E,8'hC4};
        //1.0,0.5,2.0,0.25
        operands_b_i = {8'h3C,8'h38,8'h40,8'h34};
        // for (int j = 0; j < VectorSize; j++) begin
        //   operands_a_i[j] = $urandom();
        //   operands_b_i[j] = $urandom();
        // end

        scale_i[0] = 8'h7F;//1.0 
        scale_i[1] = 8'h7F;//1.0
      end
      else if (i==1)begin
        //2,-2,1,-1
        operands_a_i = {8'h40,8'hC0,8'h3C,8'hBC};
        //1,2,1,1
        operands_b_i = {8'h3C,8'h40,8'h3C,8'h3C};
        // for (int j = 0; j < VectorSize; j++) begin
        //   operands_a_i[j] = $urandom();
        //   operands_b_i[j] = $urandom();
        // end

        scale_i[0] = 8'h7F;//1.0 
        scale_i[1] = 8'h7F;//1.0
      end else begin
        for (int j = 0; j < VectorSize; j++) begin
          operands_a_i[j] = $urandom();
          operands_b_i[j] = $urandom();
        end
        scale_i[0] = 8'h7F;//1.0 
        scale_i[1] = 8'h7F;//1.0
      end
        // Calculate golden value
        mac_pe_golden(operands_a_i, operands_b_i, src_fmt_i,dst_fmt_i, scale_i, golden_result_o);

        // Set the valid signals
        a_valid_i = 1;
        b_valid_i = 1;
        init_save_i = 1;
        #100

        // Check if answer is correct
        if(golden_result_o !== result_o) begin
          $display("XXXXXXXXXXXXXXError in test %0dXXXXXXXXXXXXXXX", i);

          for (int j = 0; j < VectorSize; j++) begin
          $display("A[%0d]: %b, B[%0d]: %b",
            j, operands_a_i[j], j, operands_b_i[j]);
          end
          $display("OUT: %b, GOLDEN: %b", result_o, golden_result_o);
          $display("OUT: %h, GOLDEN: %h", result_o, golden_result_o);
          $display("OUT: %d, GOLDEN: %d", $signed(fp32_to_real(result_o)), $signed(fp32_to_real(golden_result_o)));
          $display("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");
          $fatal;
         
        end else begin
          $display("OOOOOOOOOOOOTest %0d passed. OOOOOOOOOOOOOO", i);
          for (int j = 0; j < VectorSize; j++) begin
          $display("A[%0d]: %b, B[%0d]: %b",
            j, operands_a_i[j], j, operands_b_i[j]);
          end
          $display("OUT: %b, GOLDEN: %b", result_o, golden_result_o);
          $display("OUT: %h, GOLDEN: %h", result_o, golden_result_o);
          $display("OUT: %d, GOLDEN: %d", $signed(fp32_to_real(result_o)), $signed(fp32_to_real(golden_result_o)));
          $display("OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO");
        end
        
      end

      // Finish simulation after some time
      #20
      $display("All tests passed!");

      $finish;
  end

endmodule

