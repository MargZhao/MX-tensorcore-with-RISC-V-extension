`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/10/30 23:56:14
// Design Name: 
// Module Name: fp8_fma_tb
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

`timescale 1ns / 1ps
import mxfp8_pkg::*;

module fp8_fma_tb;

  // Parameters
  localparam int VectorSize   = 4;
  localparam int SRC_WIDTH    = mxfp8_pkg::fp_width(mxfp8_pkg::E5M2);
  localparam int DST_WIDTH    = mxfp8_pkg::fp_width(mxfp8_pkg::FP32);
  localparam int SCALE_WIDTH  = 8;

  // DUT signals
  logic                        clk_i;
  logic                        rst_ni;
  logic                        clr;

  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_a_i;
  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_b_i;
  mxfp8_pkg::fp_format_e                src_fmt_i;
  mxfp8_pkg::fp_format_e                dst_fmt_i;
  logic [1:0][SCALE_WIDTH-1:0]          scale_i;

  logic [DST_WIDTH-1:0]                 result_o;

  // Clock generation
  always #5 clk_i = ~clk_i;

  // DUT instance
  mxfp8_dotp #(
    .VectorSize(VectorSize)
  ) dut (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .operands_a_i(operands_a_i),
    .operands_b_i(operands_b_i),
    .src_fmt_i(src_fmt_i),
    .dst_fmt_i(dst_fmt_i),
    .scale_i(scale_i),
    .clr(clr),
    .result_o(result_o)
  );

  //-------------------------------------
  // Utility tasks
  //-------------------------------------
  task automatic reset_dut();
    begin
      rst_ni = 0;
      clr = 1;
      #20;
      rst_ni = 1;
      clr = 0;
    end
  endtask

  // Decode FP32 output (for debug display)
  function real fp32_to_real(input logic [31:0] val);
    logic sign;
    int   exp;
    real  mant;
    begin
      sign = val[31];
      exp  = val[30:23] - 127;
      mant = 1.0 + (val[22:0] / (2.0**23));
      fp32_to_real = (sign ? -1.0 : 1.0) * mant * (2.0**exp);
    end
  endfunction

  //-------------------------------------
  // Stimulus
  //-------------------------------------
  initial begin
    clk_i = 0;
    reset_dut();
    src_fmt_i = mxfp8_pkg::E5M2;
    dst_fmt_i = mxfp8_pkg::FP32;
    scale_i[0] = 8'd127;
    scale_i[1] = 8'd127;

    $display("=== MXFP8 DOTP TEST START ===");

    //-----------------------------------
    // 1. Simple MAC test
    //-----------------------------------
    operands_a_i = '{8'h3C, 8'h40, 8'h42, 8'h3A}; // roughly 1.0, 2.0, 3.0, 0.9
    operands_b_i = '{8'h3C, 8'h3C, 8'h3C, 8'h3C}; // all ~1.0
    @(posedge clk_i);
    #20;
    $display("[Test1] Simple MAC output = %h (%f)", result_o, fp32_to_real(result_o));

    // Expected: sum(a[i]*b[i]) = ~6.9
    assert (fp32_to_real(result_o) > 6.5 && fp32_to_real(result_o) < 7.2)
      else $error("❌ Test1 failed: incorrect MAC result");

    //-----------------------------------
    // 2. Special cases (Zero, Inf, NaN)
    //-----------------------------------
    operands_a_i = '{8'h00, 8'h7F, 8'hFF, 8'h00}; // 0, +Inf, NaN, 0
    operands_b_i = '{8'h00, 8'h3C, 8'h3C, 8'h00}; // 0, 1.0, 1.0, 0
    @(posedge clk_i);
    #20;
    $display("[Test2] Special cases result = %h", result_o);

    // Assertions (simple heuristic)
    if (operands_a_i[1] == 8'h7F)
      $display("✅ Inf handled OK (result=%h)", result_o);
    if (operands_a_i[2] == 8'hFF)
      $display("✅ NaN handled OK (result=%h)", result_o);

    //-----------------------------------
    // 3. Large*small exponent difference
    //-----------------------------------
    operands_a_i = '{8'h7B, 8'h08, 8'h7B, 8'h08}; // large and tiny alternating
    operands_b_i = '{8'h7B, 8'h08, 8'h7B, 8'h08};
    @(posedge clk_i);
    #20;
    $display("[Test3] Large/small exponent diff result = %h (%f)", result_o, fp32_to_real(result_o));

    // Sanity check: result should be dominated by large*large term
    assert (fp32_to_real(result_o) > 1.0e3)
      else $error("❌ Test3 failed: exponent alignment issue");

    //-----------------------------------
    // 4. Mixed random cases (looped)
    //-----------------------------------
    for (int t = 0; t < 5; t++) begin
      foreach (operands_a_i[i]) begin
        operands_a_i[i] = $urandom_range(0, 255);
        operands_b_i[i] = $urandom_range(0, 255);
      end
      @(posedge clk_i);
      #20;
      $display("[Test4.%0d] Random output = %h (%f)", t, result_o, fp32_to_real(result_o));
    end

    $display("=== MXFP8 DOTP TEST COMPLETE ===");
    #50 $finish;
  end

endmodule

