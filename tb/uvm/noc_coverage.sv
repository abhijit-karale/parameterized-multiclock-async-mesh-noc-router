//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_coverage.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Functional Coverage Collector for NoC Router. Samples cross
//              coverage of Source x Destination, Packet Length, VC Utilization,
//              and Multi-Port Contention Scenarios.
//==============================================================================

`ifndef NOC_COVERAGE_SV
`define NOC_COVERAGE_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
`include "noc_packet_item.sv"
import noc_pkg::*;

class noc_coverage extends uvm_subscriber #(noc_packet_item);
  `uvm_component_utils(noc_coverage)

  noc_packet_item sampled_pkt;

  // Covergroups
  covergroup cg_noc_traffic;
    cp_ingress_port: coverpoint sampled_pkt.ingress_port {
      bins local_port = {PORT_LOCAL};
      bins north_port = {PORT_NORTH};
      bins east_port  = {PORT_EAST};
      bins south_port = {PORT_SOUTH};
      bins west_port  = {PORT_WEST};
    }

    cp_egress_port: coverpoint sampled_pkt.egress_port {
      bins local_port = {PORT_LOCAL};
      bins north_port = {PORT_NORTH};
      bins east_port  = {PORT_EAST};
      bins south_port = {PORT_SOUTH};
      bins west_port  = {PORT_WEST};
    }

    cp_vc_id: coverpoint sampled_pkt.vc_id {
      bins vc0 = {0};
      bins vc1 = {1};
    }

    cp_pkt_len: coverpoint sampled_pkt.num_flits {
      bins single_flit = {1};
      bins short_pkt   = {[2:3]};
      bins medium_pkt  = {[4:6]};
      bins long_pkt    = {[7:8]};
    }

    cp_dest_x: coverpoint sampled_pkt.dest_x {
      bins x_coords[] = {[0:3]};
    }

    cp_dest_y: coverpoint sampled_pkt.dest_y {
      bins y_coords[] = {[0:3]};
    }

    // Cross: Source Port x Destination Port
    cross_src_dst: cross cp_ingress_port, cp_egress_port;

    // Cross: Packet Length x VC ID
    cross_len_vc: cross cp_pkt_len, cp_vc_id;

    // Cross: 2D Mesh Coordinates
    cross_dest_xy: cross cp_dest_x, cp_dest_y;
  endgroup

  function new(string name = "noc_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_noc_traffic = new();
  endfunction

  virtual function void write(noc_packet_item t);
    sampled_pkt = t;
    cg_noc_traffic.sample();
  endfunction

  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info(get_type_name(), $sformatf("Total Functional Coverage: %0.2f %%",
              cg_noc_traffic.get_coverage()), UVM_LOW)
  endfunction

endclass : noc_coverage

`endif // NOC_COVERAGE_SV
