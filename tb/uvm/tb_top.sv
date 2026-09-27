//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    tb_top.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Master UVM Testbench Top with Multi-Clock Generation:
//              - Core Clock @ 150 MHz (Local PE)
//              - Router Mesh Clock @ 250 MHz
//              - Neighbor Link Clocks with Phase Skew & Jitter Injection
//              - Live SVA Formal Assertions Binding & UVM Config DB
//==============================================================================

`timescale 1ns/1ps

`include "uvm_macros.sv"
`include "noc_pkg.sv"
`include "noc_if.sv"
`include "noc_uvm_pkg.sv"

module tb_top;

  import uvm_pkg::*;
  import noc_pkg::*;
  import noc_uvm_pkg::*;

  // Parameters
  localparam int NUM_PORTS  = noc_pkg::NUM_PORTS;
  localparam int NUM_VCS    = noc_pkg::DEFAULT_NUM_VCS;
  localparam int FLIT_WIDTH = noc_pkg::FLIT_WIDTH;

  //----------------------------------------------------------------------------
  // Clock Generation
  // Core Domain: 150 MHz (Period: 6.667 ns, Half-period: 3.333 ns)
  // Mesh Domain: 250 MHz (Period: 4.000 ns, Half-period: 2.000 ns)
  //----------------------------------------------------------------------------
  logic clk_core;
  logic clk_mesh;
  logic rst_n_core;
  logic rst_n_mesh;

  initial begin
    clk_core = 1'b0;
    forever #3.333ns clk_core = ~clk_core;
  end

  initial begin
    clk_mesh = 1'b0;
    forever #2.000ns clk_mesh = ~clk_mesh;
  end

  // Link RX Clocks with Phase Offsets (Plesiochronous / Mesochronous CDC)
  logic [NUM_PORTS-1:0] rx_clks;
  logic [NUM_PORTS-1:0] rx_rsts;

  assign rx_clks[PORT_LOCAL] = clk_core; // Local PE @ 150 MHz
  assign rx_rsts[PORT_LOCAL] = rst_n_core;

  // North Link @ 250 MHz (0.0 ns offset)
  assign rx_clks[PORT_NORTH] = clk_mesh;
  assign rx_rsts[PORT_NORTH] = rst_n_mesh;

  // East Link @ 250 MHz with 0.5 ns phase shift
  logic clk_east;
  initial begin
    clk_east = 1'b0;
    #0.5ns;
    forever #2.000ns clk_east = ~clk_east;
  end
  assign rx_clks[PORT_EAST] = clk_east;
  assign rx_rsts[PORT_EAST] = rst_n_mesh;

  // South Link @ 250 MHz with 1.0 ns phase shift
  logic clk_south;
  initial begin
    clk_south = 1'b0;
    #1.0ns;
    forever #2.000ns clk_south = ~clk_south;
  end
  assign rx_clks[PORT_SOUTH] = clk_south;
  assign rx_rsts[PORT_SOUTH] = rst_n_mesh;

  // West Link @ 250 MHz with 1.5 ns phase shift
  logic clk_west;
  initial begin
    clk_west = 1'b0;
    #1.5ns;
    forever #2.000ns clk_west = ~clk_west;
  end
  assign rx_clks[PORT_WEST] = clk_west;
  assign rx_rsts[PORT_WEST] = rst_n_mesh;

  // Reset Generation
  initial begin
    rst_n_core = 1'b0;
    rst_n_mesh = 1'b0;
    #25ns;
    @(posedge clk_core);
    rst_n_core = 1'b1;
    @(posedge clk_mesh);
    rst_n_mesh = 1'b1;
  end

  //----------------------------------------------------------------------------
  // Physical Port Interfaces
  //----------------------------------------------------------------------------
  noc_if #(
    .FLIT_WIDTH (FLIT_WIDTH),
    .NUM_VCS    (NUM_VCS)
  ) port_if [NUM_PORTS] (
    .clk   (rx_clks),
    .rst_n (rx_rsts)
  );

  // Flattened DUT signals
  logic [NUM_PORTS-1:0]      dut_rx_valid;
  logic [FLIT_WIDTH-1:0]     dut_rx_data [NUM_PORTS];
  logic [NUM_VCS-1:0]        dut_credit_out [NUM_PORTS];
  logic                      dut_tx_clk;
  logic                      dut_tx_rst_n;
  logic [NUM_PORTS-1:0]      dut_tx_valid;
  logic [FLIT_WIDTH-1:0]     dut_tx_data [NUM_PORTS];
  logic [NUM_VCS-1:0]        dut_credit_in [NUM_PORTS];

  genvar p;
  generate
    for (p = 0; p < NUM_PORTS; p++) begin : gen_port_wires
      assign dut_rx_valid[p]      = port_if[p].rx_valid;
      assign dut_rx_data[p]       = port_if[p].rx_data;
      assign port_if[p].credit_out = dut_credit_out[p];

      assign port_if[p].tx_valid  = dut_tx_valid[p];
      assign port_if[p].tx_data   = dut_tx_data[p];
      assign dut_credit_in[p]     = port_if[p].credit_in;
    end
  endgenerate

  //----------------------------------------------------------------------------
  // DUT Instantiation
  //----------------------------------------------------------------------------
  noc_router_top #(
    .ROUTER_X   (0),
    .ROUTER_Y   (0),
    .NUM_PORTS  (NUM_PORTS),
    .NUM_VCS    (NUM_VCS),
    .FIFO_DEPTH (8),
    .SYNC_STAGE (2)
  ) u_dut (
    .clk_mesh        (clk_mesh),
    .rst_n_mesh      (rst_n_mesh),
    .rx_clk          (rx_clks),
    .rx_rst_n        (rx_rsts),
    .rx_valid        (dut_rx_valid),
    .rx_data         (dut_rx_data),
    .credit_out      (dut_credit_out),
    .tx_clk          (dut_tx_clk),
    .tx_rst_n        (dut_tx_rst_n),
    .tx_valid        (dut_tx_valid),
    .tx_data         (dut_tx_data),
    .credit_in_clk   (rx_clks),
    .credit_in_rst_n (rx_rsts),
    .credit_in       (dut_credit_in)
  );

  //----------------------------------------------------------------------------
  // Bind SVA Formal Assertion Checkers at Runtime
  //----------------------------------------------------------------------------
  bind u_dut formal_properties #(
    .ROUTER_X   (0),
    .ROUTER_Y   (0),
    .NUM_PORTS  (5),
    .NUM_VCS    (2),
    .FIFO_DEPTH (8)
  ) u_sva_checker (
    .clk_mesh       (clk_mesh),
    .rst_n_mesh     (rst_n_mesh),
    .rx_clk         (rx_clk),
    .rx_rst_n       (rx_rst_n),
    .rx_valid       (rx_valid),
    .rx_data        (rx_data),
    .credit_out     (credit_out),
    .tx_clk         (tx_clk),
    .tx_rst_n       (tx_rst_n),
    .tx_valid       (tx_valid),
    .tx_data        (tx_data),
    .credit_in      (credit_in),
    .vc_valid       (u_vc_allocator.in_valid),
    .vc_pop         (u_vc_allocator.in_pop),
    .has_credit     (u_vc_allocator.has_credit),
    .crossbar_grant (u_vc_allocator.crossbar_grant)
  );

  //----------------------------------------------------------------------------
  // UVM Configuration & Test Execution
  //----------------------------------------------------------------------------
  initial begin
    // Waveform Dump Setup
    if ($test$plusargs("DUMP_VCD")) begin
      $dumpfile("sim_trace.vcd");
      $dumpvars(0, tb_top);
    end

    // Configure Virtual Interfaces for each Port Agent
    uvm_config_db#(virtual noc_if)::set(null, "*agent_LOCAL*", "vif", port_if[PORT_LOCAL]);
    uvm_config_db#(virtual noc_if)::set(null, "*agent_NORTH*", "vif", port_if[PORT_NORTH]);
    uvm_config_db#(virtual noc_if)::set(null, "*agent_EAST*",  "vif", port_if[PORT_EAST]);
    uvm_config_db#(virtual noc_if)::set(null, "*agent_SOUTH*", "vif", port_if[PORT_SOUTH]);
    uvm_config_db#(virtual noc_if)::set(null, "*agent_WEST*",  "vif", port_if[PORT_WEST]);

    // Start UVM Test
    run_test();
  end

endmodule : tb_top
