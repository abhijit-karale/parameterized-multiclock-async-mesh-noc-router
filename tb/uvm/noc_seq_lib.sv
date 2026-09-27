//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_seq_lib.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Comprehensive UVM Sequence Library including concurrent random
//              mesh traffic, hotspot stress, and corner-case packet sequences.
//==============================================================================

`ifndef NOC_SEQ_LIB_SV
`define NOC_SEQ_LIB_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
`include "noc_packet_item.sv"
import noc_pkg::*;

//------------------------------------------------------------------------------
// Base Sequence
//------------------------------------------------------------------------------
class noc_base_seq extends uvm_sequence #(noc_packet_item);
  `uvm_object_utils(noc_base_seq)

  int unsigned num_packets = 10;
  port_id_t    src_port    = PORT_LOCAL;

  function new(string name = "noc_base_seq");
    super.new(name);
  endfunction

  virtual task body();
    noc_packet_item pkt;
    for (int i = 0; i < num_packets; i++) begin
      `uvm_create(pkt)
      if (!pkt.randomize() with {
        pkt_id == (i + 1);
      }) begin
        `uvm_fatal("RND_FAIL", "Packet randomization failed!")
      end
      `uvm_send(pkt)
    end
  endtask : body

endclass : noc_base_seq

//------------------------------------------------------------------------------
// Random Mesh Traffic Sequence (Uniform Random Distribution)
//------------------------------------------------------------------------------
class noc_random_mesh_seq extends uvm_sequence #(noc_packet_item);
  `uvm_object_utils(noc_random_mesh_seq)

  int unsigned num_packets = 25;
  bit [noc_pkg::DEFAULT_X_WIDTH-1:0] my_x = 0;
  bit [noc_pkg::DEFAULT_Y_WIDTH-1:0] my_y = 0;

  function new(string name = "noc_random_mesh_seq");
    super.new(name);
  endfunction

  virtual task body();
    noc_packet_item pkt;
    for (int i = 0; i < num_packets; i++) begin
      `uvm_create(pkt)
      if (!pkt.randomize() with {
        src_x  == my_x;
        src_y  == my_y;
        pkt_id == (i + 1);
        num_flits inside {[1:6]};
      }) begin
        `uvm_fatal("RND_FAIL", "Packet randomization failed!")
      end
      `uvm_send(pkt)
    end
  endtask : body

endclass : noc_random_mesh_seq

//------------------------------------------------------------------------------
// Hotspot Contention Sequence (Stresses single output port & credit backpressure)
//------------------------------------------------------------------------------
class noc_hotspot_seq extends uvm_sequence #(noc_packet_item);
  `uvm_object_utils(noc_hotspot_seq)

  int unsigned num_packets = 30;
  bit [noc_pkg::DEFAULT_X_WIDTH-1:0] hotspot_x = 0;
  bit [noc_pkg::DEFAULT_Y_WIDTH-1:0] hotspot_y = 0;

  function new(string name = "noc_hotspot_seq");
    super.new(name);
  endfunction

  virtual task body();
    noc_packet_item pkt;
    for (int i = 0; i < num_packets; i++) begin
      `uvm_create(pkt)
      if (!pkt.randomize() with {
        dest_x == hotspot_x;
        dest_y == hotspot_y;
        pkt_id == (i + 1);
        num_flits inside {[2:8]};
      }) begin
        `uvm_fatal("RND_FAIL", "Hotspot packet randomization failed!")
      end
      `uvm_send(pkt)
    end
  endtask : body

endclass : noc_hotspot_seq

//------------------------------------------------------------------------------
// Corner Cases Sequence (Single-flit, max-length, alternating VCs)
//------------------------------------------------------------------------------
class noc_corner_cases_seq extends uvm_sequence #(noc_packet_item);
  `uvm_object_utils(noc_corner_cases_seq)

  function new(string name = "noc_corner_cases_seq");
    super.new(name);
  endfunction

  virtual task body();
    noc_packet_item pkt;

    // 1. Single-Flit Atomic Packets (HEAD_TAIL)
    for (int i = 0; i < 5; i++) begin
      `uvm_create(pkt)
      if (!pkt.randomize() with {
        num_flits == 1;
        pkt_id    == (100 + i);
        vc_id     == (i % 2);
      }) begin
        `uvm_fatal("RND_FAIL", "Single flit randomization failed!")
      end
      `uvm_send(pkt)
    end

    // 2. Maximum Length Packets (8 flits)
    for (int i = 0; i < 4; i++) begin
      `uvm_create(pkt)
      if (!pkt.randomize() with {
        num_flits == 8;
        pkt_id    == (150 + i);
        vc_id     == (i % 2);
      }) begin
        `uvm_fatal("RND_FAIL", "Max length packet randomization failed!")
      end
      `uvm_send(pkt)
    end

    // 3. Boundary Mesh Coordinates
    begin
      `uvm_create(pkt)
      if (!pkt.randomize() with {
        dest_x    == 3;
        dest_y    == 3;
        num_flits == 4;
        pkt_id    == 201;
      }) `uvm_fatal("RND_FAIL", "Boundary randomization failed!")
      `uvm_send(pkt)

      `uvm_create(pkt)
      if (!pkt.randomize() with {
        dest_x    == 0;
        dest_y    == 3;
        num_flits == 4;
        pkt_id    == 202;
      }) `uvm_fatal("RND_FAIL", "Boundary randomization failed!")
      `uvm_send(pkt)
    end

  endtask : body

endclass : noc_corner_cases_seq

`endif // NOC_SEQ_LIB_SV
