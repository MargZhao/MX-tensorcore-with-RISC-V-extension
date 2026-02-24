`timescale 1ns / 1ps

module tb_onedotproduct();

    // Parameters
    localparam int unsigned SRC_WIDTH = 8;
    localparam int unsigned SCALE_WIDTH = 8;
    localparam int unsigned DST_WIDTH = 32;

    // Clock and Reset
    logic clk;
    logic rst_n;

    // Inputs
    logic [SRC_WIDTH-1:0] operands_a_i;
    logic [SRC_WIDTH-1:0] operands_b_i;
    mxfp8_pkg::fp_format_e src_fmt_i;
    mxfp8_pkg::fp_format_e dst_fmt_i;
    logic [1:0][SCALE_WIDTH-1:0] scale_i;
    logic a_valid_i;
    logic b_valid_i;
    logic init_save_i;

    // Outputs
    logic done_o;
    logic [DST_WIDTH-1:0] result_o;

    // Instantiate UUT (Unit Under Test)
    onedotproduct #(
        .SRC_WIDTH(SRC_WIDTH),
        .SCALE_WIDTH(SCALE_WIDTH),
        .DST_WIDTH(DST_WIDTH)
    ) uut (
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
        .done_o(done_o),
        .result_o(result_o)
    );

    // Clock generation
    initial begin
        clk = 1;
        forever #5 clk = ~clk; // 100MHz
    end
    
    // 定义一个任务 (Task) 来简化数据驱动逻辑
    task automatic drive_sample(
        input logic [SRC_WIDTH-1:0] a,
        input logic [SRC_WIDTH-1:0] b,
        input logic init = 0
    );
        @(posedge clk);
        operands_a_i <= a;
        operands_b_i <= b;
        a_valid_i    <= 1;
        b_valid_i    <= 1;
        init_save_i  <= init;

        // 等待硬件给出完成信号 (done_o 对应你代码中的 reg_valid)
        // 它会在 a_valid_i 后的第一个时钟上升沿跳变
        wait(done_o === 1'b1);
        
        // 在完成信号跳变后的瞬间（稍微偏移避开沿）采样
        #1; 
        $display("Time: %0t | In: (%h, %h) | Result: %h | Done: %b", 
                 $time, a, b, result_o, done_o);

        // 采样完成后撤销输入
        @(posedge clk);
        a_valid_i    <= 0;
        b_valid_i    <= 0;
        init_save_i  <= 0;
    endtask

    initial begin
        // --- 1. 初始化 ---
        rst_n = 0;
        a_valid_i = 0; b_valid_i = 0; init_save_i = 0;
        scale_i[0] = 8'd127; scale_i[1] = 8'd127;
        src_fmt_i = mxfp8_pkg::E5M2;
        
        #25 rst_n = 1;
        repeat(2) @(posedge clk);

        // --- 2. Test 1: 1.0 * 1.0 (使用自动触发任务) ---
        $display("\n--- Test 1: 1.0 * 1.0 ---");
        drive_sample(8'h3C, 8'h3C, 1); // 开启 init_save_i 清空累加器

        // --- 3. Test 2: Accumulation (Add 2.0) ---
        $display("\n--- Test 2: Adding 2.0 ---");
        drive_sample(8'h40, 8'h3C, 0); // 1.0 + 2.0 = 3.0

        // --- 4. Test 3: Scale factor check ---
        $display("\n--- Test 3: Changing Scale to 2.0x ---");
        scale_i[0] = 8'd128; // 2^1 权重
        // 注意：Scale 改变后需要一次有效计算来触发寄存器更新
        drive_sample(8'h00, 8'h00, 0); // 3.0 + 0 = 3.0, 但 Scale 变为 2.0x 结果应变为 6.0

        #100;
        $display("\nSimulation Finished.");
        $finish;
    end
endmodule
