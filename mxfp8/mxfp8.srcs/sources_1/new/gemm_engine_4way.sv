`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/02/24 03:30:06
// Design Name: 
// Module Name: gemm_engine_4way
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


module gemm_engine_4way #(
    parameter int unsigned SRC_WIDTH   = 8,
    parameter int unsigned DST_WIDTH   = 32,
    parameter int unsigned SCALE_WIDTH = 8
)(
    input  logic clk_i,
    input  logic rst_ni,

    // --- Control Interface ---
    input  logic        start_i,        // Start a batch of accumulations
    input  logic        init_i,         // Reset accumulators for a new row/col
    output logic        busy_o,         // High while calculating
    output logic        done_o,         // Pulse when specific count reached
    output logic [15:0] acc_count_o,    // Current accumulation step

    // --- Configuration ---
    input  logic [15:0] target_count_i, // How many steps to accumulate before 'done'
    
    // --- Data Interface (Quad-way SIMD) ---
    input  logic [3:0][SRC_WIDTH-1:0] op_a_i, // 4 separate A operands
    input  logic [3:0][SRC_WIDTH-1:0] op_b_i, // 4 separate B operands
    input  logic [1:0][SCALE_WIDTH-1:0] scale_i,
    
    // --- Output Interface ---
    output logic [3:0][DST_WIDTH-1:0] results_o
);

    logic [3:0] dot_done_bus;
    logic       internal_valid;

    // --- Control System & Counter ---
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            acc_count_o    <= '0;
            busy_o         <= 1'b0;
            internal_valid <= 1'b0;
        end else begin
            if (start_i && !busy_o) begin
                busy_o         <= 1'b1;
                acc_count_o    <= '0;
                internal_valid <= 1'b1;
            end else if (busy_o) begin
                if (dot_done_bus[0]) begin // Use unit 0 as the reference for the counter
                    acc_count_o <= acc_count_o + 1;
                    
                    // Automatically stop when target is reached
                    if (acc_count_o >= target_count_i - 1) begin
                        busy_o         <= 1'b0;
                        internal_valid <= 1'b0;
                    end
                end
            end
        end
    end

    assign done_o = (acc_count_o == target_count_i) && !busy_o;

    // --- Quad Unit Instantiation ---
    generate
        for (genvar i = 0; i < 4; i++) begin : gen_units
            onedotproduct #(
                .SRC_WIDTH(SRC_WIDTH),
                .SCALE_WIDTH(SCALE_WIDTH),
                .DST_WIDTH(DST_WIDTH)
            ) u_dot (
                .clk_i       (clk_i),
                .rst_ni      (rst_ni),
                .operands_a_i(op_a_i[i]),
                .operands_b_i(op_b_i[i]),
                .src_fmt_i   (mxfp8_pkg::E5M2),
                .dst_fmt_i   (mxfp8_pkg::FP32),
                .scale_i     (scale_i),
                .a_valid_i   (internal_valid),
                .b_valid_i   (internal_valid),
                .init_save_i (init_i),
                .done_o      (dot_done_bus[i]),
                .result_o    (results_o[i])
            );
        end
    endgenerate

endmodule