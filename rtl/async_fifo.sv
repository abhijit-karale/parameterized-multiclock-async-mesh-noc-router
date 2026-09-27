//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    async_fifo.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Parameterized Dual-Clock Asynchronous FIFO with Gray-Code Pointers,
//              2-FF CDC Synchronizers, and FWFT (First-Word Fall-Through) support.
//              Follows Cummings CDC Architecture for safe multi-clock domains.
//==============================================================================

`ifndef ASYNC_FIFO_SV
`define ASYNC_FIFO_SV

module async_fifo #(
  parameter int DATA_WIDTH = 55,
  parameter int DEPTH      = 8,     // Must be power of 2
  parameter int SYNC_STAGE = 2
) (
  // Write Domain (Upstream Transmitter / PE)
  input  logic                  wr_clk,
  input  logic                  wr_rst_n,
  input  logic                  wr_en,
  input  logic [DATA_WIDTH-1:0] wr_data,
  output logic                  wr_full,
  output logic                  wr_almost_full,
  output logic [$clog2(DEPTH):0] wr_free_slots,

  // Read Domain (Router Mesh Core)
  input  logic                  rd_clk,
  input  logic                  rd_rst_n,
  input  logic                  rd_en,
  output logic [DATA_WIDTH-1:0] rd_data,
  output logic                  rd_empty,
  output logic                  rd_valid,
  output logic [$clog2(DEPTH):0] rd_occupancy
);

  localparam int ADDR_W = $clog2(DEPTH);

  // Assert DEPTH is power of 2
  initial begin
    if ((DEPTH & (DEPTH - 1)) != 0 || DEPTH < 2) begin
      $fatal(1, "async_fifo DEPTH must be a power of 2, got %0d", DEPTH);
    end
  end

  // Memory Array
  logic [DATA_WIDTH-1:0] mem [DEPTH];

  // Binary and Gray Pointers
  logic [ADDR_W:0] wptr_bin,   wptr_bin_next;
  logic [ADDR_W:0] wptr_gray,  wptr_gray_next;
  logic [ADDR_W:0] rptr_bin,   rptr_bin_next;
  logic [ADDR_W:0] rptr_gray,  rptr_gray_next;

  // Synchronized Pointers
  logic [ADDR_W:0] wq2_rptr_gray, wq2_rptr_bin;
  logic [ADDR_W:0] rq2_wptr_gray, rq2_wptr_bin;

  // CDC Synchronizer: Read pointer to Write clock domain
  cdc_gray_sync #(
    .ADDR_WIDTH (ADDR_W),
    .STAGES     (SYNC_STAGE)
  ) u_sync_r2w (
    .dst_clk      (wr_clk),
    .dst_rst_n    (wr_rst_n),
    .src_ptr_gray (rptr_gray),
    .dst_ptr_gray (wq2_rptr_gray),
    .dst_ptr_bin  (wq2_rptr_bin)
  );

  // CDC Synchronizer: Write pointer to Read clock domain
  cdc_gray_sync #(
    .ADDR_WIDTH (ADDR_W),
    .STAGES     (SYNC_STAGE)
  ) u_sync_w2r (
    .dst_clk      (rd_clk),
    .dst_rst_n    (rd_rst_n),
    .src_ptr_gray (wptr_gray),
    .dst_ptr_gray (rq2_wptr_gray),
    .dst_ptr_bin  (rq2_wptr_bin)
  );

  //----------------------------------------------------------------------------
  // Write Domain Logic
  //----------------------------------------------------------------------------
  assign wptr_bin_next  = wptr_bin + (wr_en && !wr_full);
  assign wptr_gray_next = wptr_bin_next ^ (wptr_bin_next >> 1);

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wptr_bin  <= '0;
      wptr_gray <= '0;
    end else begin
      wptr_bin  <= wptr_bin_next;
      wptr_gray <= wptr_gray_next;
    end
  end

  // Memory Write
  always_ff @(posedge wr_clk) begin
    if (wr_en && !wr_full) begin
      mem[wptr_bin[ADDR_W-1:0]] <= wr_data;
    end
  end

  // Full condition: MSB and MSB-1 differ, remaining bits identical
  logic wr_full_val;
  assign wr_full_val = (wptr_gray_next == {~wq2_rptr_gray[ADDR_W:ADDR_W-1], 
                                            wq2_rptr_gray[ADDR_W-2:0]});

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_full <= 1'b0;
    end else begin
      wr_full <= wr_full_val;
    end
  end

  // Free slots calculation in write domain
  logic [ADDR_W:0] w_used;
  assign w_used          = wptr_bin - wq2_rptr_bin;
  assign wr_free_slots   = DEPTH[ADDR_W:0] - w_used;
  assign wr_almost_full  = (w_used >= (DEPTH[ADDR_W:0] - 1'b1));

  //----------------------------------------------------------------------------
  // Read Domain Logic (First-Word Fall-Through)
  //----------------------------------------------------------------------------
  assign rptr_bin_next  = rptr_bin + (rd_en && !rd_empty);
  assign rptr_gray_next = rptr_bin_next ^ (rptr_bin_next >> 1);

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rptr_bin  <= '0;
      rptr_gray <= '0;
    end else begin
      rptr_bin  <= rptr_bin_next;
      rptr_gray <= rptr_gray_next;
    end
  end

  // Empty condition: Read Gray pointer matches synchronized Write Gray pointer
  logic rd_empty_val;
  assign rd_empty_val = (rptr_gray_next == rq2_wptr_gray);

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_empty <= 1'b1;
    end else begin
      rd_empty <= rd_empty_val;
    end
  end

  // FWFT Output Data Presentation
  assign rd_data      = mem[rptr_bin[ADDR_W-1:0]];
  assign rd_valid     = !rd_empty;
  assign rd_occupancy = rq2_wptr_bin - rptr_bin;

endmodule : async_fifo

`endif // ASYNC_FIFO_SV
