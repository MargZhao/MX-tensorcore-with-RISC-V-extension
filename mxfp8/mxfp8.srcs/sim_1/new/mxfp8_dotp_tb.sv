`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/13 10:41:56
// Design Name: 
// Module Name: mxfp8_dotp_tb
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

import mxfp8_pkg::*;
module mxfp8_dotp_tb;

  // =====================
  // 参数配置
  // =====================
  localparam int VectorSize = 32;   // 测试向量大小
  localparam int SRC_WIDTH  = 8;   // FP8: E5M2
  localparam int DST_WIDTH  = 32;
  localparam int SCALE_WIDTH = 8;

  // =====================
  // DUT 端口信号
  // =====================
  logic clk_i;
  logic rst_ni;
  logic clr;

  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_a_i;
  logic [VectorSize-1:0][SRC_WIDTH-1:0] operands_b_i;
  logic [1:0][SCALE_WIDTH-1:0]          scale_i;
  logic [DST_WIDTH-1:0]                 result_o;
  mxfp8_pkg::fp_format_e src_fmt_i;
  mxfp8_pkg::fp_format_e dst_fmt_i;

  // 假设 src_fmt_i / dst_fmt_i 是简单的 logic [2:0]
  // 如果是 typedef enum, 可以根据你的 mxfp8_pkg 改
 

  initial begin
    clk_i = 0;
    src_fmt_i = mxfp8_pkg::E5M2;
    dst_fmt_i = mxfp8_pkg::FP32;
    forever #5 clk_i = ~clk_i;  // 100 MHz
  end

  initial begin
    rst_ni = 0;
    clr = 0;
    #50;
    rst_ni = 1;
  end

  initial begin
    // Dump 仿真波形（功耗分析时必须）
    $dumpfile("mxfp8_dotp_wave.vcd");
    $dumpvars(0, mxfp8_dotp_tb);

    // 初始化输入
    for (int i = 0; i < VectorSize; i++) begin
      operands_a_i[i] = $urandom_range(0, 255);  
      operands_b_i[i] = $urandom_range(0, 255);
    end
    scale_i[0] = 8'd127;
    scale_i[1] = 8'd127;

    clr = 0;

    // 多组测试，反复切换以产生动态功耗
    repeat (1000) begin
      @(posedge clk_i);
      for (int i = 0; i < VectorSize; i++) begin
        operands_a_i[i] = $urandom_range(0, 255);
        operands_b_i[i] = $urandom_range(0, 255);
      end
      scale_i[0] = $urandom_range(120, 135);
      scale_i[1] = $urandom_range(120, 135);
    end

   #100;
    $finish;
  end

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

endmodule
