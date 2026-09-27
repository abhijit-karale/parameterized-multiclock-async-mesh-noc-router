//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_sequencer.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: UVM Sequencer for NoC Packet Transactions.
//==============================================================================

`ifndef NOC_SEQUENCER_SV
`define NOC_SEQUENCER_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
`include "noc_packet_item.sv"

class noc_sequencer extends uvm_sequencer #(noc_packet_item);
  `uvm_component_utils(noc_sequencer)

  function new(string name = "noc_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass : noc_sequencer

`endif // NOC_SEQUENCER_SV
