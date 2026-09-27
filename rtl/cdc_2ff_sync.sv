//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    cdc_2ff_sync.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Multi-stage Flip-Flop Synchronizer with ASYNC_REG attributes.
//              Mitigates metastability across asynchronous clock boundaries.
//==============================================================================

`ifndef CDC_2FF_SYNC_SV
`define CDC_2FF_SYNC_SV

module cdc_2ff_sync #(
  parameter int WIDTH  = 1,
  parameter int STAGES = 2
) (
  input  logic             clk,
  input  logic             rst_n,
  input  logic [WIDTH-1:0] async_data_in,
  output logic [WIDTH-1:0] sync_data_out
);

  // Synchronizer pipeline registers with EDA synthesis attributes
  (* ASYNC_REG = "TRUE", dont_touch = "true" *)
  logic [WIDTH-1:0] sync_stage [STAGES];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < STAGES; i++) begin
        sync_stage[i] <= '0;
      end
    end else begin
      sync_stage[0] <= async_data_in;
      for (int i = 1; i < STAGES; i++) begin
        sync_stage[i] <= sync_stage[i-1];
      end
    end
  end

  assign sync_data_out = sync_stage[STAGES-1];

endmodule : cdc_2ff_sync

`endif // CDC_2FF_SYNC_SV
