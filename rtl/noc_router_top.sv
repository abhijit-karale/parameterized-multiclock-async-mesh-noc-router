//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_router_top.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm (Independent Core @ 150MHz, Mesh @ 250MHz)
// Description: Production-grade 5-port Multi-Clock Asynchronous Mesh NoC Router.
//              Integrates Dual-Clock Gray-Code VC FIFOs, Dimension-Order XY
//              Routing, 5x5 Non-blocking Crossbar, and Credit Flow Control.
//==============================================================================

`ifndef NOC_ROUTER_TOP_SV
`define NOC_ROUTER_TOP_SV

import noc_pkg::*;

module noc_router_top #(
  parameter int ROUTER_X   = 0,
  parameter int ROUTER_Y   = 0,
  parameter int NUM_PORTS  = noc_pkg::NUM_PORTS,
  parameter int NUM_VCS    = noc_pkg::DEFAULT_NUM_VCS,
  parameter int VC_WIDTH   = noc_pkg::DEFAULT_VC_WIDTH,
  parameter int X_WIDTH    = noc_pkg::DEFAULT_X_WIDTH,
  parameter int Y_WIDTH    = noc_pkg::DEFAULT_Y_WIDTH,
  parameter int DATA_WIDTH = noc_pkg::DEFAULT_DATA_W,
  parameter int FIFO_DEPTH = noc_pkg::DEFAULT_FIFO_DEP,
  parameter int SYNC_STAGE = 2
) (
  // Central Router Mesh Clock & Reset Domain (250 MHz)
  input  logic                      clk_mesh,
  input  logic                      rst_n_mesh,

  // Asynchronous Input Ports (Local @ 150MHz, Mesh links @ 250MHz / Async)
  input  logic [NUM_PORTS-1:0]      rx_clk,
  input  logic [NUM_PORTS-1:0]      rx_rst_n,
  input  logic [NUM_PORTS-1:0]      rx_valid,
  input  logic [noc_pkg::FLIT_WIDTH-1:0] rx_data [NUM_PORTS],
  output logic [NUM_VCS-1:0]        credit_out [NUM_PORTS],

  // Synchronous Output Ports (Transmitted in clk_mesh domain)
  output logic                      tx_clk,
  output logic                      tx_rst_n,
  output logic [NUM_PORTS-1:0]      tx_valid,
  output logic [noc_pkg::FLIT_WIDTH-1:0] tx_data [NUM_PORTS],
  input  logic [NUM_PORTS-1:0]      credit_in_clk, // Clock of returning credit
  input  logic [NUM_PORTS-1:0]      credit_in_rst_n,
  input  logic [NUM_VCS-1:0]        credit_in  [NUM_PORTS]
);

  import noc_pkg::*;

  localparam int FLIT_W = noc_pkg::FLIT_WIDTH;

  // Synchronized Mesh Reset
  logic sync_mesh_rst_n;
  cdc_reset_sync #(
    .STAGES (SYNC_STAGE)
  ) u_mesh_rst_sync (
    .clk         (clk_mesh),
    .async_rst_n (rst_n_mesh),
    .sync_rst_n  (sync_mesh_rst_n)
  );

  assign tx_clk   = clk_mesh;
  assign tx_rst_n = sync_mesh_rst_n;

  //----------------------------------------------------------------------------
  // Input Port Asynchronous VC Buffers (CDC Boundary: rx_clk -> clk_mesh)
  //----------------------------------------------------------------------------
  logic [NUM_VCS-1:0] vc_pop   [NUM_PORTS];
  logic [NUM_VCS-1:0] vc_valid [NUM_PORTS];
  logic [FLIT_W-1:0]  vc_data  [NUM_PORTS][NUM_VCS];
  logic [NUM_VCS-1:0] vc_full  [NUM_PORTS];

  genvar p;
  generate
    for (p = 0; p < NUM_PORTS; p++) begin : gen_rx_ports
      async_vc_fifo #(
        .DATA_WIDTH (FLIT_W),
        .NUM_VCS    (NUM_VCS),
        .VC_WIDTH   (VC_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH),
        .SYNC_STAGE (SYNC_STAGE)
      ) u_async_vc_fifo (
        .rx_clk            (rx_clk[p]),
        .rx_rst_n          (rx_rst_n[p]),
        .rx_valid          (rx_valid[p]),
        .rx_data           (rx_data[p]),
        .credit_out        (credit_out[p]),

        .mesh_clk          (clk_mesh),
        .mesh_rst_n        (sync_mesh_rst_n),
        .vc_pop            (vc_pop[p]),
        .vc_valid          (vc_valid[p]),
        .vc_data           (vc_data[p]),
        .vc_full_rx_domain (vc_full[p])
      );
    end
  endgenerate

  //----------------------------------------------------------------------------
  // Credit Synchronization & Flow Control Management
  // Synchronizes incoming credit pulses from downstream receivers into clk_mesh
  //----------------------------------------------------------------------------
  logic [NUM_VCS-1:0] sync_credit_in [NUM_PORTS];
  logic [NUM_VCS-1:0] has_credit     [NUM_PORTS];
  logic [NUM_PORTS-1:0] crossbar_tx_fire;
  logic [$clog2(NUM_VCS)-1:0] crossbar_tx_vc [NUM_PORTS];

  genvar op, ov;
  generate
    for (op = 0; op < NUM_PORTS; op++) begin : gen_credit_sync_port
      for (ov = 0; ov < NUM_VCS; ov++) begin : gen_credit_sync_vc
        cdc_pulse_sync #(
          .STAGES (SYNC_STAGE)
        ) u_credit_rx_sync (
          .src_clk       (credit_in_clk[op]),
          .src_rst_n     (credit_in_rst_n[op]),
          .src_pulse_in  (credit_in[op][ov]),
          .dst_clk       (clk_mesh),
          .dst_rst_n     (sync_mesh_rst_n),
          .dst_pulse_out (sync_credit_in[op][ov])
        );
      end

      credit_manager #(
        .NUM_VCS         (NUM_VCS),
        .INITIAL_CREDITS (FIFO_DEPTH)
      ) u_credit_mgr (
        .clk          (clk_mesh),
        .rst_n        (sync_mesh_rst_n),
        .credit_in    (sync_credit_in[op]),
        .tx_fire      (crossbar_tx_fire[op]),
        .tx_vc_id     (crossbar_tx_vc[op]),
        .has_credit   (has_credit[op]),
        .credit_count ()
      );
    end
  endgenerate

  //----------------------------------------------------------------------------
  // Virtual Channel and Switch Allocation
  //----------------------------------------------------------------------------
  logic [NUM_PORTS-1:0]         crossbar_grant [NUM_PORTS]; // [out_p][in_p]
  logic [$clog2(NUM_PORTS)-1:0] crossbar_sel_port [NUM_PORTS];

  vc_allocator #(
    .NUM_PORTS  (NUM_PORTS),
    .NUM_VCS    (NUM_VCS),
    .ROUTER_X   (ROUTER_X),
    .ROUTER_Y   (ROUTER_Y),
    .X_WIDTH    (X_WIDTH),
    .Y_WIDTH    (Y_WIDTH),
    .FLIT_WIDTH (FLIT_W)
  ) u_vc_allocator (
    .clk            (clk_mesh),
    .rst_n          (sync_mesh_rst_n),
    .in_valid       (vc_valid),
    .in_flit        (vc_data),
    .in_pop         (vc_pop),
    .has_credit     (has_credit),
    .crossbar_grant (crossbar_grant),
    .out_tx_fire    (crossbar_tx_fire),
    .out_tx_vc      (crossbar_tx_vc),
    .out_sel_port   (crossbar_sel_port)
  );

  //----------------------------------------------------------------------------
  // 5x5 Non-blocking Crossbar Switch
  //----------------------------------------------------------------------------
  // Flatten active flit per input port to present to crossbar
  logic [FLIT_W-1:0]    xb_in_data  [NUM_PORTS];
  logic [NUM_PORTS-1:0] xb_in_valid;

  always_comb begin
    for (int ip = 0; ip < NUM_PORTS; ip++) begin
      xb_in_data[ip]  = '0;
      xb_in_valid[ip] = 1'b0;
      for (int iv = 0; iv < NUM_VCS; iv++) begin
        if (vc_valid[ip][iv]) begin
          xb_in_data[ip]  = vc_data[ip][iv];
          xb_in_valid[ip] = 1'b1;
          break;
        end
      end
    end
  end

  crossbar_5x5 #(
    .DATA_WIDTH (FLIT_W),
    .NUM_PORTS  (NUM_PORTS)
  ) u_crossbar (
    .clk          (clk_mesh),
    .rst_n        (sync_mesh_rst_n),
    .in_data      (xb_in_data),
    .in_valid     (xb_in_valid),
    .grant_matrix (crossbar_grant),
    .out_data     (tx_data),
    .out_valid    (tx_valid)
  );

endmodule : noc_router_top

`endif // NOC_ROUTER_TOP_SV
