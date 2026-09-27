//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    cdc_reset_sync.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Asynchronous Assert Synchronous Deassert (AASD) Reset Synchronizer.
//              Guarantees glitch-free reset release aligned to target clock.
//==============================================================================

`ifndef CDC_RESET_SYNC_SV
`define CDC_RESET_SYNC_SV

module cdc_reset_sync #(
  parameter int STAGES = 2
) (
  input  logic clk,
  input  logic async_rst_n,
  output logic sync_rst_n
);

  // Synthesis directives to preserve synchronizer chain and prevent retiming
  (* ASYNC_REG = "TRUE", dont_touch = "true" *)
  logic [STAGES-1:0] sync_reg;

  always_ff @(posedge clk or negedge async_rst_n) begin
    if (!async_rst_n) begin
      sync_reg <= '0;
    end else begin
      sync_reg <= {sync_reg[STAGES-2:0], 1'b1};
    end
  end

  assign sync_rst_n = sync_reg[STAGES-1];

endmodule : cdc_reset_sync

`endif // CDC_RESET_SYNC_SV
