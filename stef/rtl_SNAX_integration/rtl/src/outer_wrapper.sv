module outer_wrapper (
	input  logic clk_i,
	input  logic rstn,
	
	input  logic [1:0] prec_mode_in,
	input  logic [1:0] FP_mode_in,

	input  logic        send_output_in,
	input  logic [1:0]  prec_mode_quan_in,
	input  logic [1:0]  FP_mode_quan_in,

	input  logic        A_valid_in,
	input  logic        B_valid_in,
	output reg          A_ready_out,
	output reg          B_ready_out,

	//Data in
	// 64bits
	input  logic [0:7][7:0] A_INT8_in, //8-bit Mantissa
	// 64bits
	input  logic [0:7][7:0] B_INT8_in,

	// 256bits
	input  logic [0:7][0:3][7:0] A_FP8_in, //Sign,Exponent,Mantissa
	// 256bits
	input  logic [0:7][0:3][7:0] B_FP8_in,

	// 192bits
	input  logic [0:7][0:3][5:0] A_FP6_in, //Sign,Exponent,Mantissa
	input  logic [0:7][0:3][5:0] B_FP6_in,

	// 256bits
	input  logic [0:7][0:7][3:0] A_FP4_in, //Sign,Exponent,Mantissa
	input  logic [0:7][0:7][3:0] B_FP4_in,

	// 8bits
	input  logic [7:0]      shared_exp_A_in,
	// 8bits
	input  logic [7:0]      shared_exp_B_in,

	//Data out
	output reg   [0:7][0:7][7:0] Out_out, //Sign,Exponent,Mantissa,padding_zeros
	output reg   [7:0]           shared_exp_out_out
);


reg [1:0] prec_mode;
reg [1:0] FP_mode;

reg        send_output;
reg [1:0]  prec_mode_quan;
reg [1:0]  FP_mode_quan;

reg        A_valid;
reg        B_valid;
logic        A_ready;
logic        B_ready;

//Data in
// 64bits
reg [0:7][7:0] A_INT8; //8-bit Mantissa
// 64bits
reg [0:7][7:0] B_INT8;

// 256bits
reg [0:7][0:3][7:0] A_FP8; //Sign,Exponent,Mantissa
// 256bits
reg [0:7][0:3][7:0] B_FP8;

// 192bits
reg [0:7][0:3][5:0] A_FP6; //Sign,Exponent,Mantissa
reg [0:7][0:3][5:0] B_FP6;

// 256bits
reg [0:7][0:7][3:0] A_FP4; //Sign,Exponent,Mantissa
reg [0:7][0:7][3:0] B_FP4;

// 8bits
reg [7:0]      shared_exp_A;
// 8bits
reg [7:0]      shared_exp_B;

//Data out
logic [0:7][0:7][7:0] Out; //Sign,Exponent,Mantissa,padding_zeros
logic [7:0]           shared_exp_out;

always @(posedge clk_i or negedge rstn) begin
	if (~rstn) begin
		prec_mode <= '0; FP_mode <= '0; send_output <= '0; prec_mode_quan <= '0; FP_mode_quan <= '0; A_valid <= '0; B_valid <= '0;
		A_INT8 <= '0; B_INT8 <= '0; A_FP8 <= '0; B_FP8 <= '0; A_FP6 <= '0; B_FP6 <= '0; A_FP4 <= '0; B_FP4 <= '0; shared_exp_A <= '0; shared_exp_B <= '0; 
		Out_out <= '0; shared_exp_out_out <= '0; A_ready_out <= '0; B_ready_out <= '0;
	end
	else begin
		prec_mode <= prec_mode_in; FP_mode <= FP_mode_in; send_output <= send_output_in; prec_mode_quan <= prec_mode_quan_in; FP_mode_quan <= FP_mode_quan_in; A_valid <= A_valid_in; B_valid <= B_valid_in;
		A_INT8 <= A_INT8_in; B_INT8 <= B_INT8_in; A_FP8 <= A_FP8_in; B_FP8 <= B_FP8_in; A_FP6 <= A_FP6_in; B_FP6 <= B_FP6_in; A_FP4 <= A_FP4_in; B_FP4 <= B_FP4_in; shared_exp_A <= shared_exp_A_in; shared_exp_B <= shared_exp_B_in; 
		Out_out <= Out; shared_exp_out_out <= shared_exp_out; A_ready_out <= A_ready; B_ready_out <= B_ready;		
	end
end


Block_PE_wrapper Block_PE_wrapper0 (.clk_i(clk_i), .rstn(rstn), .prec_mode(prec_mode), .FP_mode(FP_mode), .send_output(send_output), .prec_mode_quan(prec_mode_quan), .FP_mode_quan(FP_mode_quan),
.A_valid(A_valid), .B_valid(B_valid), .A_INT8(A_INT8), .B_INT8(B_INT8), .A_FP8(A_FP8), .B_FP8(B_FP8), .A_FP6(A_FP6), .B_FP6(B_FP6), .A_FP4(A_FP4), .B_FP4(B_FP4),
.shared_exp_A(shared_exp_A), .shared_exp_B(shared_exp_B), .Out(Out), .shared_exp_out(shared_exp_out), .A_ready(A_ready), .B_ready(B_ready));


endmodule


