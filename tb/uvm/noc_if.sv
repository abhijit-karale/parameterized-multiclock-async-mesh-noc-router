//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_if.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: SystemVerilog Interface for Asynchronous NoC Router Port.
//              Supports independent clock domains, Gray/credit flow control,
//              and clocking blocks for race-free UVM driving and monitoring.
//==============================================================================

`ifndef NOC_IF_SV
`define NOC_IF_SV

`include "noc_pkg.sv"
import noc_pkg::*;

interface noc_if #(
  parameter int FLIT_WIDTH = noc_pkg::FLIT_WIDTH,
  parameter int NUM_VCS    = noc_pkg::DEFAULT_NUM_VCS
) (
  input logic clk,
  input logic rst_n
);

  // Ingress into Router (Driven by Upstream PE or Neighbor Router)
  logic                  rx_valid;
  logic [FLIT_WIDTH-1:0] rx_data;
  logic [NUM_VCS-1:0]    credit_out; // Pulsed by router back to upstream

  // Egress out of Router (Driven by Router)
  logic                  tx_valid;
  logic [FLIT_WIDTH-1:0] tx_data;
  logic [NUM_VCS-1:0]    credit_in;  // Pulsed by downstream receiver to router

  // Driver Clocking Block (Ingress driving)
  clocking drv_cb @(posedge clk);
    default input #1ns output #1ns;
    output rx_valid;
    output rx_data;
    input  credit_out;
    output credit_in;
  endclocking

  // Monitor Clocking Block (Observes both ingress and egress)
  clocking mon_cb @(posedge clk);
    default input #1ns output #1ns;
    input rx_valid;
    input rx_data;
    input credit_out;
    input tx_valid;
    input tx_data;
    input credit_in;
  endclocking

  modport DRV (clocking drv_cb, input clk, input rst_n);
  modport MON (clocking mon_cb, input clk, input rst_n);

endinterface : noc_if

`endif // NOC_IF_SV
