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

//   // -------------------------
//   // Utility functions
//   // -------------------------
// task automatic mac_pe_golden_task(
//     input  logic [VectorSize-1:0][SRC_WIDTH-1:0] A_i,
//     input  logic [VectorSize-1:0][SRC_WIDTH-1:0] B_i,
//     input  mxfp8_pkg::fp_format_e src_fmt_i,
//     input  logic [1:0][SCALE_WIDTH-1:0] scale_i,
//     input  logic init_save, // 用于控制累加器清零
//     output logic [DST_WIDTH-1:0] C_o
// );

//     real val_a, val_b;
//     real dot_product_step = 0.0;
//     real scale_a, scale_b;
//     real final_result;
    
//     // 1. **控制累加器初始化**
//     if (init_save == 1'b1) begin
//         acc_golden = 0.0; // DUT 的 init_save=1 应该意味着从 0 开始
//     end

//     // 2. Compute the Dot Product for THIS STEP
//     for (int i = 0; i < VectorSize; i++) begin
//         val_a = mxfp8_to_real(A_i[i], src_fmt_i);
//         val_b = mxfp8_to_real(B_i[i], src_fmt_i);
//         dot_product_step += val_a * val_b; // 仅计算当前向量的点积
//     end

//     // 3. **累加到全局状态**
//     acc_golden += dot_product_step;

//     // 4. Apply Scaling and Output Formatting (只在需要输出时进行)
//     scale_a = 2.0 ** (real'(scale_i[0]) - 127.0);
//     scale_b = 2.0 ** (real'(scale_i[1]) - 127.0);
    
//     final_result = acc_golden * scale_a * scale_b;

//     // 5. Convert to FP32 bits
//     C_o = $shortrealtobits(shortreal'(final_result));

// endtask

// // =======================================================================
// // Helper Function: Convert MXFP8 bits to Real
// // =======================================================================
// function automatic real mxfp8_to_real(
//     input logic [SRC_WIDTH:0] data,
//     input mxfp8_pkg::fp_format_e fmt
// );
//     logic sign;
//     logic [4:0] exp5;
//     logic [3:0] exp4;
//     logic [1:0] mant2;
//     logic [2:0] mant3;
    
//     real result;
//     int exponent;
//     real fraction;
    
//     sign = data[7];

//     if (fmt == mxfp8_pkg::E5M2) begin
//         // --- E5M2 Format (Standard IEEE-like) ---
//         // S:1, E:5, M:2 | Bias = 15
//         exp5 = data[6:2];
//         mant2 = data[1:0];
        
//         if (exp5 == '0) begin 
//             // Subnormal: (-1)^S * 2^(1-Bias) * (0.Mant)
//             if (mant2 == '0) return (sign) ? -0.0 : 0.0; // Zero
//             exponent = 1 - 15;
//             fraction = real'(mant2) / 4.0;
//         end else begin
//             // Normal: (-1)^S * 2^(Exp-Bias) * (1.Mant)
//             exponent = int'(exp5) - 15;
//             fraction = 1.0 + (real'(mant2) / 4.0);
//         end
        
//     end else begin
//         // --- E4M3 Format (OCP/NVIDIA Standard) ---
//         // S:1, E:4, M:3 | Bias = 7
//         // Note: E4M3 has no Infinity, only NaN at 0x7F (S0 E1111 M111) and 0xFF (S1 E1111 M111)
//         exp4 = data[6:3];
//         mant3 = data[2:0];
        
//         if (exp4 == '0) begin
//             // Subnormal: (-1)^S * 2^(1-Bias) * (0.Mant)
//             if (mant3 == '0) return (sign) ? -0.0 : 0.0;
//             exponent = 1 - 7;
//             fraction = real'(mant3) / 8.0;
//         end else if (exp4 == 4'b1111 && mant3 == 3'b111) begin
//             // NaN case in E4M3
//             return 0.0; // Or handle as specific NaN logic
//         end else begin
//             // Normal
//             exponent = int'(exp4) - 7;
//             fraction = 1.0 + (real'(mant3) / 8.0);
//         end
//     end

//     // Combine parts
//     result = fraction * (2.0 ** exponent);
//     return (sign) ? -result : result;

// endfunction


// function real fp32_to_real(input logic [31:0] fp);
//     int exp;
//     int man;
//     int sgn;
//     begin
//       sgn = fp[31];
//       exp = fp[30 -:8];
//       man = fp[22:0];

//       if (exp == 0)
//         fp32_to_real = (sgn ? -1.0 : 1.0) * man * 2.0**(-2);
//       else
//         fp32_to_real = (sgn ? -1.0 : 1.0) * (1.0 + man / 4.0) * 2.0**(exp - 127);
//     end
//   endfunction



//   // -------------------------
//   // Test procedure
//   // -------------------------
//   real ref_dot;
//   real ref_a[VectorSize];
//   real ref_b[VectorSize];

//   initial begin
//     $display("---- MXFP8 DOTP TESTBENCH START ----");

//     // Waveform dump
//     $dumpfile("dotp.vcd");
//     $dumpvars(0, mxfp8_dotp_tb);

//     rst_n = 0;
//     acc_clr_i   = 1;
//     src_fmt_i = mxfp8_pkg::E5M2;
//     dst_fmt_i = mxfp8_pkg::FP32;
//     for (int i=0;i<VectorSize;i++)begin
//       operands_a_i[i] = '0;
//       operands_b_i[i] = '0;
//     end

//     scale_i[0] = 127;
//     scale_i[1] = 127;

//     @(posedge clk);
//     rst_n = 1;
//     acc_clr_i   = 0;

//     // -------------------------------------
//     // SEQUENTIAL ACCUMULATION TEST (Test 0 + Test 1)
//     // -------------------------------------

//     // === Step 1: Execute Test 0 (Start Accumulation) ===
//     $display("--- Step 1: Execute Test 0 (Dot Product = 4.0) ---");
//     // Test 0 Inputs
//     operands_a_i = {8'h3C, 8'h40, 8'h3E, 8'hC4};
//     operands_b_i = {8'h3C, 8'h38, 8'h40, 8'h34};
//     scale_i[0] = 8'h7F; // 1.0
//     scale_i[1] = 8'h7F; // 1.0
    
//     // **DUT**: 激活清零/初始化信号
//     init_save_i = 1; 
//     a_valid_i = 1;
//     b_valid_i = 1;
    
//     @(posedge clk);
//     #100;
    
//     // **Golden**: 计算 Test 0 的点积并清零 acc_golden
//     mac_pe_golden_task(operands_a_i, operands_b_i, src_fmt_i, scale_i, 1'b1, golden_result_o);
    
//     // 检查 Test 0 结果 (可选，但推荐)
//     $display("Test 0 (4.0) - Golden: %h, DUT: %h", golden_result_o, result_o);
//     if (golden_result_o !== result_o) $fatal("FAIL: Test 0 failed initial check!");
    
    
//     // === Step 2: Execute Test 1 (Continue Accumulation) ===
//     $display("--- Step 2: Execute Test 1 (Dot Product = -2.0) ---");
//     // Test 1 Inputs
//     operands_a_i = {8'h40, 8'hC0, 8'h3C, 8'hBC};
//     operands_b_i = {8'h3C, 8'h40, 8'h3C, 8'h3C};
    
//     // **DUT**: 禁用清零信号 (继续累加)
//     init_save_i = 0; 
    
//     @(posedge clk);
//     #100;
    
//     // **Golden**: 计算 Test 1 的点积并累加到 acc_golden
//     mac_pe_golden_task(operands_a_i, operands_b_i, src_fmt_i, scale_i, 1'b0, golden_result_o);
    
    
//     // === Final Check: Total Result (4.0 + -2.0 = 2.0) ===
//     $display("--- Final Check: Total Accumulation (2.0) ---");

//     // 预期结果 (2.0) 的 FP32 二进制表示
//     // S=0, Exp=128 (2^1), Mant=00...0
//     // Binary: 0_10000000_000...0
//     // Hex: 32'h40000000
//     //logic [31:0] expected_final = 32'h40000000;

//     if (golden_result_o !== result_o) begin
//         $display("XXXXXXXXXXXXXXError in Sequential AccumulationXXXXXXXXXXXXXXX");
//         $display("OUT: %h, GOLDEN: %h", result_o, golden_result_o);
//         $display("Expected 2.0 (0x40000000). DUT Value: %f, Golden Value: %f", 
//                   fp32_to_real(result_o), fp32_to_real(golden_result_o));
//         $fatal;
//     end else begin
//         $display("OOOOOOOOOOOSequential Accumulation Passed! (Result: 2.0) OOOOOOOOOOOOOO");
//     end

//     // -------------------------------------
//     // TESTCASE 1：简单固定输入
//     // -------------------------------------
//     for (int i = 0; i < NumTests; i++) begin

//       if(i== 0) begin
//         init_save_i = 1;
//         //1.0,2.0,1.5,-4.0
//         operands_a_i = {8'h3C,8'h40,8'h3E,8'hC4};
//         //1.0,0.5,2.0,0.25
//         operands_b_i = {8'h3C,8'h38,8'h40,8'h34};
//         // for (int j = 0; j < VectorSize; j++) begin
//         //   operands_a_i[j] = $urandom();
//         //   operands_b_i[j] = $urandom();
//         // end

//         scale_i[0] = 8'h7F;//1.0 
//         scale_i[1] = 8'h7F;//1.0
//       end
//       else if (i==1)begin
//         init_save_i = 1;
//         //2,-2,1,-1
//         operands_a_i = {8'h40,8'hC0,8'h3C,8'hBC};
//         //1,2,1,1
//         operands_b_i = {8'h3C,8'h40,8'h3C,8'h3C};
//         // for (int j = 0; j < VectorSize; j++) begin
//         //   operands_a_i[j] = $urandom();
//         //   operands_b_i[j] = $urandom();
//         // end

//         scale_i[0] = 8'h7F;//1.0 
//         scale_i[1] = 8'h7F;//1.0
//       end else begin
//         init_save_i = 1;
//         for (int j = 0; j < VectorSize; j++) begin
//           operands_a_i[j] = $urandom();
//           operands_b_i[j] = $urandom();
//         end
//         scale_i[0] = 8'h7F;//1.0 
//         scale_i[1] = 8'h7F;//1.0
//       end
//         // Calculate golden value
//         mac_pe_golden_task(operands_a_i, operands_b_i, src_fmt_i, scale_i,init_save_i, golden_result_o);

//         // Set the valid signals
//         a_valid_i = 1;
//         b_valid_i = 1;
        
//         #100

//         // Check if answer is correct
//         if(golden_result_o !== result_o) begin
//           $display("XXXXXXXXXXXXXXError in test %0dXXXXXXXXXXXXXXX", i);

//           for (int j = 0; j < VectorSize; j++) begin
//           $display("A[%0d]: %b, B[%0d]: %b",
//             j, operands_a_i[j], j, operands_b_i[j]);
//           end
//           $display("OUT: %b, GOLDEN: %b", result_o, golden_result_o);
//           $display("OUT: %h, GOLDEN: %h", result_o, golden_result_o);
//           $display("OUT: %d, GOLDEN: %d", $signed(fp32_to_real(result_o)), $signed(fp32_to_real(golden_result_o)));
//           $display("XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX");
//           $fatal;
         
//         end else begin
//           $display("OOOOOOOOOOOOTest %0d passed. OOOOOOOOOOOOOO", i);
//           for (int j = 0; j < VectorSize; j++) begin
//           $display("A[%0d]: %b, B[%0d]: %b",
//             j, operands_a_i[j], j, operands_b_i[j]);
//           end
//           $display("OUT: %b, GOLDEN: %b", result_o, golden_result_o);
//           $display("OUT: %h, GOLDEN: %h", result_o, golden_result_o);
//           $display("OUT: %d, GOLDEN: %d", $signed(fp32_to_real(result_o)), $signed(fp32_to_real(golden_result_o)));
//           $display("OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO");
//         end
        
//       end

//       // Finish simulation after some time
//       #20
//       $display("All tests passed!");

//       $finish;
//   end

// endmodule

