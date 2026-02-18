`timescale 1ns / 1ps

module mxfp8_dotp_tb;

  localparam int VectorSize   = 4;   // 你可以改回 32
  localparam int SRC_WIDTH    = 8;   // E5M2 = 8 bits
  localparam int SCALE_WIDTH  = 8;
  localparam int DST_WIDTH    = 32;
  localparam int COUNT_WIDTH  = 5;


  //---------------------------
  // Test Parameters
  //---------------------------
  parameter int unsigned NumTests = 4;

  // -------------------------
  // Global Golden Accumulator
  // -------------------------
  real acc_golden; // 用于保留所有测试步骤的累加结果

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

  //FSM Controller Signals
  logic fsm_start;
  logic fsm_input_valid;
  logic fsm_result_valid;
  logic fsm_busy;
  logic fsm_done;
  logic [COUNT_WIDTH-1:0] fsm_ceiling;
  logic [COUNT_WIDTH-1:0] fsm_count;

  // -------------------------
  // Test Vector Arrays (Memory)
  // -------------------------
  // 我们定义一个数组来存放 sequential inputs
  // 假设我们要累加 2 组数据 (Test 0 + Test 1)
  logic [VectorSize-1:0][SRC_WIDTH-1:0] tv_a [2]; 
  logic [VectorSize-1:0][SRC_WIDTH-1:0] tv_b [2];

  // Global Golden Accumulator
  real acc_golden; 
  logic [DST_WIDTH-1:0] golden_result_bits;
  

  // -------------------------
  // Clock
  // -------------------------
  initial clk = 0;
  always #5 clk = ~clk;

  //FSM
  controller #(
    .CountWidth(COUNT_WIDTH)
  )controller_i(
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .start_i          (fsm_start),
    .input_valid_i    (fsm_input_valid),
    .result_valid_o   (fsm_result_valid),
    .busy_o           (fsm_busy),
    .done_o           (fsm_done),
    .ceiling_i        (fsm_ceiling),
    .count_o          (fsm_count)
  );

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
  // 3. Signal Mapping Logic
  // -------------------------
  
  // A. 将 FSM 的 count_o 作为地址，从测试数组中取数
  assign operands_a_i = tv_a[fsm_count];
  assign operands_b_i = tv_b[fsm_count];

  // B. 控制 DUT 的 init_save_i
  // 当 count == 0 时，我们要开始新的累加，所以 init_save_i = 1
  // 注意：必须在 FSM 忙碌且 input_valid 有效时才生效
  assign init_save_i = (fsm_result_valid||fsm_start); 

  // C. 简单的控制逻辑
  assign a_valid_i = fsm_input_valid;
  assign b_valid_i = fsm_input_valid;


  // -------------------------
  // 4. Test Procedure
  // -------------------------
  initial begin
    $dumpfile("fsm_test.vcd");
    $dumpvars(0, mxfp8_dotp_tb);

    // Initialize
    rst_n = 0;
    acc_clr_i = 1;
    fsm_start = 0;
    fsm_input_valid = 0;
    fsm_ceiling = 0;
    
    // Test Vectors Setup
    // Set 0: Expected DotP = 4.0
    tv_a[0] = {8'h3C, 8'h40, 8'h3E, 8'hC4};
    tv_b[0] = {8'h3C, 8'h38, 8'h40, 8'h34};
    // Set 1: Expected DotP = -2.0
    tv_a[1] = {8'h40, 8'hC0, 8'h3C, 8'hBC};
    tv_b[1] = {8'h3C, 8'h40, 8'h3C, 8'h3C};

    scale_i[0] = 8'h7F; // 1.0
    scale_i[1] = 8'h7F; // 1.0
    src_fmt_i = mxfp8_pkg::E5M2;
    dst_fmt_i = mxfp8_pkg::FP32;

    @(posedge clk);
    rst_n = 1;
    acc_clr_i = 0;
    
    // -----------------------------------------------------------
    // Start FSM Test Sequence
    // -----------------------------------------------------------
    $display("=== Starting FSM Controlled Accumulation Test ===");
    
    // 配置 FSM：我们要处理 2 组向量
    fsm_ceiling = 2; 

    // 启动 FSM
    @(posedge clk);
    fsm_start = 1;
    @(posedge clk);
    fsm_start = 0;

    // 保持 input valid，让计数器自动运行
    // 在真实场景中，这里可能包含握手逻辑
    fsm_input_valid = 1;

    // 等待 FSM 完成
    $display("=== WAIT FOR DONE ===");
    
    wait(fsm_done);
    @(posedge clk);
    fsm_input_valid = 0;

    $display("=== Test Finished ===");
    $finish;
  end

  // -------------------------
  // 5. Golden Model Monitor
  // -------------------------
  // 这个 block 模拟 Golden Model 的逐周期行为
  // 当 FSM 处于 Busy 且 valid 时，Golden Model 也要累加
  always @(posedge clk) begin
    if (!rst_n) begin
        acc_golden = 0.0;
    end else if (fsm_input_valid && fsm_busy) begin
        // --- Golden Accumulation Step ---
        
        // 1. 如果是 count=0，先清空 Golden 累加器 (模拟 init_save)
        if (fsm_count == 0) begin
            acc_golden = 0.0;
            $display("[Time %t] Golden: Init Accumulator", $time);
        end

        // 2. 计算当前拍的点积并累加
        update_golden_acc(operands_a_i, operands_b_i, src_fmt_i);
        
        $display("[Time %t] Step %0d Processed. Current Acc: %f", $time, fsm_count, acc_golden);
    end
  end

  // --- Check Result on Done ---
  always @(posedge clk) begin
    if (fsm_done) begin
        // 计算最终 FP32 bits
        $display("---------------------------------------------------");
        golden_result_bits = get_final_fp32(scale_i);
        
        
        $display("CHECK: FSM Done. Comparing Results...");
        $display("DUT Result    : %h (%f)", result_o, fp32_to_real(result_o));
        $display("Golden Result : %h (%f)", golden_result_bits, acc_golden);
        
        if (result_o === golden_result_bits) begin
             $display("PASS: Sequential Accumulation matches!");
        end else begin
             $display("FAIL: Mismatch!");
             $fatal;
        end
        $display("---------------------------------------------------");
    end
  end

  // -------------------------
  // Tasks / Functions
  // -------------------------
  
  // 更新 Golden 累加器 (不包含 Scaling，Scaling 在最后做)
  task automatic update_golden_acc(
    input logic [VectorSize-1:0][SRC_WIDTH-1:0] A,
    input logic [VectorSize-1:0][SRC_WIDTH-1:0] B,
    input mxfp8_pkg::fp_format_e fmt
  );
    real val_a, val_b;
    for (int i = 0; i < VectorSize; i++) begin
        val_a = mxfp8_to_real(A[i], fmt);
        val_b = mxfp8_to_real(B[i], fmt);
        acc_golden += val_a * val_b;
    end
  endtask

  // 将 Golden 累加值转换为 FP32
  function logic [31:0] get_final_fp32(logic [1:0][SCALE_WIDTH-1:0] scales);
    real scale_a, scale_b, final_val;
    scale_a = 2.0 ** (real'(scales[0]) - 127.0);
    scale_b = 2.0 ** (real'(scales[1]) - 127.0);
    final_val = acc_golden * scale_a * scale_b;
    return $shortrealtobits(shortreal'(final_val));
  endfunction

  // Helper: MXFP8 to Real (Copy from previous code)
  function automatic real mxfp8_to_real(input logic [7:0] data, input mxfp8_pkg::fp_format_e fmt);
    logic sign;
    logic [4:0] exp5;
    logic [1:0] mant2;
    real result;
    int exponent;
    real fraction;
    
    // Simplified E5M2 for demo
    sign = data[7];
    exp5 = data[6:2];
    mant2 = data[1:0];
    
    if (exp5 == 0) begin // Subnormal
        exponent = 1 - 15;
        fraction = real'(mant2) / 4.0;
    end else begin // Normal
        exponent = int'(exp5) - 15;
        fraction = 1.0 + (real'(mant2) / 4.0);
    end
    result = fraction * (2.0 ** exponent);
    return (sign) ? -result : result;
  endfunction

  // Helper: FP32 to Real (for display)
  function real fp32_to_real(input logic [31:0] fp);
     int sgn, exp; 
     real man;
     sgn = fp[31];
     exp = fp[30:23];
     man = real'(fp[22:0]) / 8388608.0; // 2^23
     if (exp == 0) return 0.0; 
     return (sgn ? -1.0 : 1.0) * (1.0 + man) * (2.0 ** (exp - 127));
  endfunction

endmodule
