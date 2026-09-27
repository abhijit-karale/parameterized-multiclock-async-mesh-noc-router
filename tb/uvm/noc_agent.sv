//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_agent.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: UVM Agent encapsulating Driver, Monitor, and Sequencer for a
//              single physical port of the NoC Router.
//==============================================================================

`ifndef NOC_AGENT_SV
`define NOC_AGENT_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
`include "noc_packet_item.sv"
`include "noc_sequencer.sv"
`include "noc_driver.sv"
`include "noc_monitor.sv"
import noc_pkg::*;

class noc_agent extends uvm_agent;
  `uvm_component_utils(noc_agent)

  port_id_t     port_id;
  noc_driver    driver;
  noc_sequencer sequencer;
  noc_monitor   monitor;

  function new(string name = "noc_agent", uvm_component parent = null);
    super.new(name, parent);
    port_id = PORT_LOCAL;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    monitor = noc_monitor::type_id::create("monitor", this);
    monitor.port_id = port_id;

    if (get_is_active() == UVM_ACTIVE) begin
      driver    = noc_driver::type_id::create("driver", this);
      sequencer = noc_sequencer::type_id::create("sequencer", this);
      driver.port_id = port_id;
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction

endclass : noc_agent

`endif // NOC_AGENT_SV
