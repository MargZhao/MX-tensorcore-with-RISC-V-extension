`timescale 1ns / 1ps

module adder_tree_tb;

  // ---------------------------------
  // Parameters
  // ---------------------------------
  localparam int VectorSize      = 8;
  localparam int PROD_EXP_WIDTH  = 8;
  localparam int PROD_MAN_WIDTH  = 8;
  localparam int NORM_MAN_WIDTH  = 16;
  localparam int SCALE_WIDTH     = 8;
  localparam int GUARD_BITS      = $clog2(VectorSize);
  localparam int ACC_WIDTH       = NORM_MAN_WIDTH + GUARD_BITS + 1;

  // ---------------------------------
  // DUT signals
  // ---------------------------------
  logic clk;
  logic signed [VectorSize-1:0][PROD_EXP_WIDTH-1:0] exp_sum   ;
  logic [VectorSize-1:0][PROD_MAN_WIDTH-1:0]        man_prod  ;
  logic [VectorSize-1:0]            sgn_prod;
  logic [SCALE_WIDTH:0]             scale_sum;

  logic [SCALE_WIDTH:0]             scale_aligned;
  logic [ACC_WIDTH-1:0]             sum_man;
  logic                             sum_sgn;

  // ---------------------------------
  // DUT instance
  // ---------------------------------
  adder_tree #(
    .VectorSize(VectorSize),
    .PROD_EXP_WIDTH(PROD_EXP_WIDTH),
    .PROD_MAN_WIDTH(PROD_MAN_WIDTH),
    .NORM_MAN_WIDTH(NORM_MAN_WIDTH),
    .SCALE_WIDTH(SCALE_WIDTH)
  ) dut (
    .clk(clk),
    .exp_sum(exp_sum),
    .man_prod(man_prod),
    .sgn_prod(sgn_prod),
    .scale_sum(scale_sum),
    .scale_aligned(scale_aligned),
    .sum_man(sum_man),
    .sum_sgn(sum_sgn)
  );

  // ---------------------------------
  // Clock
  // ---------------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  // ---------------------------------
  // Reference model
  // ---------------------------------
  task reference_model(
    output real ref_val,
    output integer max_exp
  );
    integer i;
    integer exp_diff;
    real mant, sign;
    ref_val = 0.0;
    max_exp = exp_sum[0];
    for (i = 1; i < VectorSize; i = i + 1)
      if (exp_sum[i] > max_exp)
        max_exp = exp_sum[i];

    for (i = 0; i < VectorSize; i = i + 1) begin
      exp_diff = max_exp - exp_sum[i];
      sign = sgn_prod[i] ? -1.0 : 1.0;
      mant = man_prod[i];
      ref_val = ref_val + sign * (mant / (2.0 ** exp_diff));
    end
  endtask

  // ---------------------------------
  // Test procedure
  // ---------------------------------
  integer i;
  real ref_val;
  integer exp_max;
  real dut_val;

  initial begin
    $display("Starting adder_tree test...");
    scale_sum = 8'd10;

    // Case 1
    $display("\n[Case 1] All exponents equal");
    for (i = 0; i < VectorSize; i = i + 1) begin
      exp_sum[i]  = 5;
      man_prod[i] = i;
      sgn_prod[i] = 0;
    end
    run_case();

       // Case 1
    $display("\n[Case 1.5] All exponents equal but different sgn");
    for (i = 0; i < VectorSize; i = i + 1) begin
      exp_sum[i]  = 5;
      man_prod[i] = i;
      sgn_prod[i] = $urandom_range(0, 1);
    end
    run_case();

    // Case 2
    $display("\n[Case 2] Different exponents simple");
    for (i = 0; i < VectorSize; i = i + 1) begin
      exp_sum[i]  = $urandom_range(0, 4);
      man_prod[i] = 1;
      sgn_prod[i] = 0;
    end
    run_case();

     // Case 2
    $display("\n[Case 2.5] Different exponents different sgn");
    for (i = 0; i < VectorSize; i = i + 1) begin
      exp_sum[i]  = $urandom_range(0, 4);
      man_prod[i] = 1;
      sgn_prod[i] = $urandom_range(0, 1);
    end
    run_case();

    // Case 3
    $display("\n[Case 3] Large exp_diff");
    for (i = 0; i < VectorSize; i = i + 1) begin
      exp_sum[i]  = (i == 0) ? 20 : 1;
      man_prod[i] = $urandom_range(20, 180);
      sgn_prod[i] = $urandom_range(0, 1);
    end
    run_case();

    $display("\nSimulation finished.");
    $finish;
  end

  // ---------------------------------
  // Case execution
  // ---------------------------------
  task run_case;
    begin
      $display(" Test start.......");
      reference_model(ref_val, exp_max);
      @(posedge clk);
      @(posedge clk);

      dut_val = (sum_sgn ? -1.0 : 1.0) * sum_man/(2**7);

      $display(" exp_max = %0d, scale_aligned = %0d", exp_max, scale_aligned);
      $display(" Reference = %f, DUT = %f , ref binary = %b", ref_val, dut_val,ref_val);
      if ((ref_val > dut_val ? ref_val - dut_val : dut_val - ref_val) < 1.0)
        $display(" PASS (within tolerance)");
      else
        $display(" FAIL (mismatch)");
      $display(" Test end.......");
    end
  endtask

endmodule

