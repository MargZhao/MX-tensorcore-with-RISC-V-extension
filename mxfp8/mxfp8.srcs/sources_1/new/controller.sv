`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/12/11 23:44:10
// Design Name: 
// Module Name: controller
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


module controller#(
    parameter int unsigned CountWidth=5
)(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic start_i,
  input  logic input_valid_i,
  output logic result_valid_o,
  output logic busy_o,
  output logic done_o,
  input  logic [CountWidth-1:0]ceiling_i,
  output logic [CountWidth-1:0]count_o

 );

 logic move_counter;
 logic clear_counters;
 logic last_counter_last_value;

  // State machine states
  typedef enum logic [1:0] {
    ControllerIdle,
    ControllerBusy,
    ControllerFinish
  } controller_state_t;

  controller_state_t current_state, next_state;

  assign busy_o = (current_state == ControllerBusy  ) ||
                  (current_state == ControllerFinish);

 ceiling_counter #(
        .Width        (      CountWidth ),
        .HasCeiling   (              1 )
    ) i_K_counter (
        .clk_i        ( clk_i          ),
        .rst_ni       ( rst_ni         ),
        .tick_i       ( move_counter ),
        .clear_i      ( clear_counters ),
        .ceiling_i    ( ceiling_i ),
        .count_o      ( count_o      ),
        .last_value_o ( last_counter_last_value )
    );



// Main controller state machine
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      current_state <= ControllerIdle;
    end else begin
      current_state <= next_state;
    end
  end

  always_comb begin
    // Default assignments
    next_state     = current_state;
    clear_counters = 0;
    move_counter   = 0;
    result_valid_o = 1'b0;
    done_o         = 1'b0;

    case (current_state)
      ControllerIdle: begin
        if (start_i) begin
          move_counter = input_valid_i;
          if(last_counter_last_value) begin
            next_state = ControllerFinish;
          end else begin
            next_state = ControllerBusy;
          end
        end
      end

      ControllerBusy: begin
        // Check if we are done
        move_counter = input_valid_i;

        if(input_valid_i && count_o == '0) begin
            result_valid_o = 1'b1;
        end

        if(last_counter_last_value) begin
            next_state = ControllerFinish;
        end
      end

      ControllerFinish: begin
        done_o         = 1'b1;
        clear_counters = 1'b1;
        result_valid_o = 1'b1;
        next_state     = ControllerIdle;
      end

      default: begin
        next_state = ControllerIdle;
      end
    endcase
  end
endmodule

module ceiling_counter #(
  parameter int Width      = 8,
  parameter int HasCeiling = 1
) (
  input  logic             clk_i,
  input  logic             rst_ni,       // active-low async reset
  input  logic             tick_i,
  input  logic             clear_i,      // active-high sync clear
  input  logic [Width-1:0] ceiling_i,
  output logic [Width-1:0] count_o,
  output logic             last_value_o
);

  // Main counter
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // Asynchronous reset to 0
      count_o <= '0;
    end else if (clear_i) begin
      // Synchronous "clear" input
      count_o <= '0;
    end else if (tick_i) begin
      // Only update on tick
      if (HasCeiling) begin
        // Compare against (ceiling_i - 1)
        if (count_o < (ceiling_i - 1'b1))
          count_o <= count_o + 1'b1;
        else count_o <= '0;
      end else begin
        // Free-running counter
        count_o <= count_o + 1'b1;
      end
    end
  end

  always_comb begin
    if (HasCeiling) begin
      // last_value_o is true if count_o == (ceiling_i - 1) AND a tick occurs
      last_value_o = (count_o == (ceiling_i - 1'b1)) && tick_i;
    end else begin
      // last_value_o is true if all bits of count_o are 1 AND a tick occurs
      last_value_o = (&count_o) && tick_i;
    end
  end

endmodule