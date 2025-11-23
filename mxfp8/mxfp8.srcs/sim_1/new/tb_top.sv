`timescale 1ns / 1ps

module mxfp8_dotp_tb;

  localparam int VectorSize   = 8;   // 你可以改回 32
  localparam int SRC_WIDTH    = 8;   // E5M2 = 8 bits
  localparam int SCALE_WIDTH  = 8;
  localparam int DST_WIDTH    = 32;

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

  logic clr;
  logic [DST_WIDTH-1:0] result_o;

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
    .clr(clr),

    .result_o(result_o)
  );


  // -------------------------
  // Utility functions
  // -------------------------

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
    clr   = 1;
    src_fmt_i = mxfp8_pkg::E5M2;
    dst_fmt_i = mxfp8_pkg::FP32;

    scale_i[0] = 127;
    scale_i[1] = 127;

    @(posedge clk);
    rst_n = 1;
    clr   = 0;

    // -------------------------------------
    // TESTCASE 1：简单固定输入
    // -------------------------------------
    $display("\n[TEST] Simple fixed vector");
    operands_a_i = '{8'hD4, 8'h67, 8'hBC, 8'hA2, 8'hDB, 8'hD1, 8'h88, 8'h55};
    operands_b_i = '{8'h23, 8'h87, 8'h44, 8'hDC, 8'h61, 8'h0C, 8'h30, 8'h13};
    scale_i = '{8'd127, 8'd127};
   
    // 等待流水线输出
    repeat(12) @(posedge clk);

    $display("DUT result_o = %x", result_o);



    $display("---- TEST END ----");
    $finish;
  end

endmodule

