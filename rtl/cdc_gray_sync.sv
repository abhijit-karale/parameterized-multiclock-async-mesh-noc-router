//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    cdc_gray_sync.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Parameterized Gray Code Pointer Multi-Stage CDC Synchronizer.
//              Synchronizes an asynchronous Gray-coded pointer from source
//              domain into destination domain, and decodes back to binary.
//==============================================================================

`ifndef CDC_GRAY_SYNC_SV
`define CDC_GRAY_SYNC_SV

module cdc_gray_sync #(
  parameter int ADDR_WIDTH = 4,
  parameter int STAGES     = 2
) (
  // Destination Clock Domain
  input  logic                  dst_clk,
  input  logic                  dst_rst_n,
  input  logic [ADDR_WIDTH:0]   src_ptr_gray, // Asynchronous input from src domain
  output logic [ADDR_WIDTH:0]   dst_ptr_gray, // Synchronized Gray pointer
  output logic [ADDR_WIDTH:0]   dst_ptr_bin   // Synchronized Binary pointer
);

  // Multi-FF Synchronizer into Destination Domain
  (* ASYNC_REG = "TRUE", dont_touch = "true" *)
  logic [ADDR_WIDTH:0] sync_reg [STAGES];

  always_ff @(posedge dst_clk or negedge dst_rst_n) begin
    if (!dst_rst_n) begin
      for (int i = 0; i < STAGES; i++) begin
        sync_reg[i] <= '0;
      end
    end else begin
      sync_reg[0] <= src_ptr_gray;
      for (int i = 1; i < STAGES; i++) begin
        sync_reg[i] <= sync_reg[i-1];
      end
    end
  end

  assign dst_ptr_gray = sync_reg[STAGES-1];

  // Destination Domain: Gray to Binary Conversion
  always_comb begin
    dst_ptr_bin[ADDR_WIDTH] = dst_ptr_gray[ADDR_WIDTH];
    for (int i = ADDR_WIDTH - 1; i >= 0; i--) begin
      dst_ptr_bin[i] = dst_ptr_bin[i+1] ^ dst_ptr_gray[i];
    end
  end

endmodule : cdc_gray_sync

`endif // CDC_GRAY_SYNC_SV
