`timescale 1ns/1ps

module tb_compressor_tree;

  // Parameters
  localparam int ACC_WIDTH = 22;
  localparam int NUM_INPUTS = 32;

  // DUT signals
  logic clk;
  logic [ACC_WIDTH-1:0] in_vec [NUM_INPUTS-1:0];
  logic [ACC_WIDTH-1:0] final_sum, final_carry;

  // DUT instance
  csa_tree #( .VectorSize(NUM_INPUTS),
        .WIDTH_I(ACC_WIDTH)) dut (
      .operands_i(in_vec),
      .sum_o(final_sum),
      .carry_o(final_carry)
  );

  // Clock generator
  initial begin
      clk = 0;
      forever #5 clk = ~clk;
  end

  // ============================================================
  // Stimulus
  // ============================================================
  initial begin
      integer i;
      logic signed [ACC_WIDTH+6:0] total_expected;
      logic signed [ACC_WIDTH+6:0] total_dut;
      logic signed [ACC_WIDTH-1:0] sum_s, carry_s;

      // 初始化输入
      for (i = 0; i < NUM_INPUTS; i++) begin
          in_vec[i] = i + 1;   // 测试简单序列：1,2,3,...,32
      end

      #1; // 等待 combinational 稳定

      // 打印输入
      $display("\n==== Input Values (decimal) ====");
      for (i = 0; i < NUM_INPUTS; i++)
          $display("in_vec[%0d] = %0d", i, in_vec[i]);

      // 理论求和
      total_expected = 0;
      for (i = 0; i < NUM_INPUTS; i++)
          total_expected += in_vec[i];

      // DUT 输出求和
      sum_s   = $signed(final_sum);
      carry_s = $signed(final_carry);
      total_dut = sum_s + carry_s; // carry 左移1再加

      // 打印结果
      $display("\n==== Compressor Tree Result ====");
      $display("Expected total = %0d", total_expected);
      $display("DUT total      = %0d", total_dut);

      if (total_dut === total_expected)
          $display("✅ PASS: Output matches expected sum!");
      else
          $display("❌ FAIL: Mismatch! Expected %0d, got %0d",
                   total_expected, total_dut);

      $finish;
  end

endmodule
