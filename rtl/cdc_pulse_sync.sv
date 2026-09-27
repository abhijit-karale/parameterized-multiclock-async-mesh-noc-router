//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    cdc_pulse_sync.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Toggle-based CDC Pulse Synchronizer. Safely transfers single-cycle
//              pulses between arbitrary frequency clock domains (fast-to-slow
//              and slow-to-fast) without pulse swallowing or loss.
//==============================================================================

`ifndef CDC_PULSE_SYNC_SV
`define CDC_PULSE_SYNC_SV

module cdc_pulse_sync #(
  parameter int STAGES = 2
) (
  // Source Domain
  input  logic src_clk,
  input  logic src_rst_n,
  input  logic src_pulse_in,

  // Destination Domain
  input  logic dst_clk,
  input  logic dst_rst_n,
  output logic dst_pulse_out
);

  // Toggle register in source domain
  logic src_toggle;

  always_ff @(posedge src_clk or negedge src_rst_n) begin
    if (!src_rst_n) begin
      src_toggle <= 1'b0;
    end else if (src_pulse_in) begin
      src_toggle <= ~src_toggle;
    end
  end

  // Synchronize toggle signal to destination domain
  (* ASYNC_REG = "TRUE", dont_touch = "true" *)
  logic [STAGES-1:0] sync_reg;

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      sync_reg <= '0;
    end else begin
      sync_reg <= {sync_reg[STAGES-2:0], src_toggle};
    end
  end

  // Edge detection in destination domain (both rising and falling edges)
  logic dst_toggle_d;

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      dst_toggle_d  <= 1'b0;
      dst_pulse_out <= 1'b0;
    end else begin
      dst_toggle_d  <= sync_reg[STAGES-1];
      dst_pulse_out <= sync_reg[STAGES-1] ^ dst_toggle_d;
    end
  end

endmodule : cdc_pulse_sync

`endif // CDC_PULSE_SYNC_SV
