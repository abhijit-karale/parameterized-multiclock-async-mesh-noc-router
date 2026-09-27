//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    async_vc_fifo.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Multi-Virtual-Channel Asynchronous Input Buffer. Demultiplexes
//              incoming flits into independent Dual-Clock Async FIFOs per VC,
//              and returns credit pulses over CDC to the upstream transmitter.
//==============================================================================

`ifndef ASYNC_VC_FIFO_SV
`define ASYNC_VC_FIFO_SV


module async_vc_fifo #(
  parameter int DATA_WIDTH = noc_pkg::FLIT_WIDTH,
  parameter int NUM_VCS    = noc_pkg::DEFAULT_NUM_VCS,
  parameter int VC_WIDTH   = noc_pkg::DEFAULT_VC_WIDTH,
  parameter int FIFO_DEPTH = noc_pkg::DEFAULT_FIFO_DEP,
  parameter int SYNC_STAGE = 2
) (
  // Upstream Transmitter Clock Domain (RX)
  input  logic                      rx_clk,
  input  logic                      rx_rst_n,
  input  logic                      rx_valid,
  input  logic [DATA_WIDTH-1:0]     rx_data,
  output logic [NUM_VCS-1:0]        credit_out,      // 1-cycle credit pulse in rx_clk

  // Router Mesh Clock Domain (Internal)
  input  logic                      mesh_clk,
  input  logic                      mesh_rst_n,
  input  logic [NUM_VCS-1:0]        vc_pop,          // Pop from router crossbar
  output logic [NUM_VCS-1:0]        vc_valid,        // Flit available per VC
  output logic [DATA_WIDTH-1:0]     vc_data [NUM_VCS],// FWFT flit per VC
  output logic [NUM_VCS-1:0]        vc_full_rx_domain // Status in rx domain
);

  import noc_pkg::*;

  // Extract VC ID from incoming flit in rx_clk domain
  // Bit slice corresponds to VC field in flit_t
  logic [VC_WIDTH-1:0] rx_vc_id;
  assign rx_vc_id = rx_data[DATA_WIDTH - 3 -: VC_WIDTH];

  genvar v;
  generate
    for (v = 0; v < NUM_VCS; v++) begin : gen_vc_fifos
      logic wr_en_vc;
      logic fifo_full;
      logic fifo_empty;
      logic rd_en_vc;
      logic credit_pulse_mesh;

      // Only write to this VC FIFO if valid and VC matches
      assign wr_en_vc = rx_valid && (rx_vc_id == v[VC_WIDTH-1:0]);
      assign vc_full_rx_domain[v] = fifo_full;

      // Read enable from router core
      assign rd_en_vc = vc_pop[v];
      assign vc_valid[v] = !fifo_empty;

      // Asynchronous FIFO per Virtual Channel
      async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (FIFO_DEPTH),
        .SYNC_STAGE (SYNC_STAGE)
      ) u_fifo (
        .wr_clk         (rx_clk),
        .wr_rst_n       (rx_rst_n),
        .wr_en          (wr_en_vc),
        .wr_data        (rx_data),
        .wr_full        (fifo_full),
        .wr_almost_full (),
        .wr_free_slots  (),

        .rd_clk         (mesh_clk),
        .rd_rst_n       (mesh_rst_n),
        .rd_en          (rd_en_vc),
        .rd_data        (vc_data[v]),
        .rd_empty       (fifo_empty),
        .rd_valid       (),
        .rd_occupancy   ()
      );

      // Whenever a flit is popped in mesh_clk, send credit pulse back to rx_clk
      assign credit_pulse_mesh = rd_en_vc && !fifo_empty;

      cdc_pulse_sync #(
        .STAGES (SYNC_STAGE)
      ) u_credit_sync (
        .src_clk        (mesh_clk),
        .src_rst_n      (mesh_rst_n),
        .src_pulse_in   (credit_pulse_mesh),
        .dst_clk        (rx_clk),
        .dst_rst_n      (rx_rst_n),
        .dst_pulse_out  (credit_out[v])
      );

    end
  endgenerate

endmodule : async_vc_fifo

`endif // ASYNC_VC_FIFO_SV
