//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_test_lib.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: UVM Test Library for Multi-Clock NoC Router. Includes Base Test,
//              Simultaneous Multi-Port Stress Test, Hotspot Contention Test,
//              and Corner-Cases Verification.
//==============================================================================

`ifndef NOC_TEST_LIB_SV
`define NOC_TEST_LIB_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
`include "noc_env.sv"
`include "noc_seq_lib.sv"
import noc_pkg::*;

//------------------------------------------------------------------------------
// Base Test
//------------------------------------------------------------------------------
class noc_base_test extends uvm_test;
  `uvm_component_utils(noc_base_test)

  noc_env env;

  function new(string name = "noc_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = noc_env::type_id::create("env", this);
  endfunction

  virtual function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.phase_done.set_drain_time(this, 100ns);
  endtask : run_phase

endclass : noc_base_test

//------------------------------------------------------------------------------
// Simultaneous Multi-Port Stress Test (All 5 ports injecting concurrently)
//------------------------------------------------------------------------------
class noc_multiport_stress_test extends noc_base_test;
  `uvm_component_utils(noc_multiport_stress_test)

  function new(string name = "noc_multiport_stress_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    noc_random_mesh_seq seq[noc_pkg::NUM_PORTS];

    phase.raise_objection(this, "Starting multi-port concurrent stress test");
    `uvm_info(get_type_name(), ">>> STARTING CONCURRENT 5-PORT NoC STRESS TEST <<<", UVM_LOW)

    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      seq[p] = noc_random_mesh_seq::type_id::create($sformatf("seq_port_%0d", p));
      seq[p].num_packets = 20; // 20 packets per port = 100 total packets
      seq[p].my_x        = (p % 2);
      seq[p].my_y        = (p / 2);
    end

    // Fork concurrent injection from all 5 ports
    fork
      seq[PORT_LOCAL].start(env.agents[PORT_LOCAL].sequencer);
      seq[PORT_NORTH].start(env.agents[PORT_NORTH].sequencer);
      seq[PORT_EAST].start(env.agents[PORT_EAST].sequencer);
      seq[PORT_SOUTH].start(env.agents[PORT_SOUTH].sequencer);
      seq[PORT_WEST].start(env.agents[PORT_WEST].sequencer);
    join

    // Drain time for all in-flight flits and credit returns to settle
    #250ns;
    `uvm_info(get_type_name(), ">>> FINISHED CONCURRENT 5-PORT NoC STRESS TEST <<<", UVM_LOW)
    phase.drop_objection(this, "Completed multi-port stress test");
  endtask : run_phase

endclass : noc_multiport_stress_test

//------------------------------------------------------------------------------
// Hotspot Contention Test (All ports sending to Local PE @ 150MHz)
//------------------------------------------------------------------------------
class noc_hotspot_test extends noc_base_test;
  `uvm_component_utils(noc_hotspot_test)

  function new(string name = "noc_hotspot_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    noc_hotspot_seq seq[noc_pkg::NUM_PORTS];

    phase.raise_objection(this, "Starting hotspot contention test");
    `uvm_info(get_type_name(), ">>> STARTING HOTSPOT CONTENTION TEST (TARGET: LOCAL PE) <<<", UVM_LOW)

    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      seq[p] = noc_hotspot_seq::type_id::create($sformatf("hotspot_seq_%0d", p));
      seq[p].num_packets = 15;
      seq[p].hotspot_x   = 0;
      seq[p].hotspot_y   = 0; // Targets Local PE (0,0)
    end

    fork
      seq[PORT_NORTH].start(env.agents[PORT_NORTH].sequencer);
      seq[PORT_EAST].start(env.agents[PORT_EAST].sequencer);
      seq[PORT_SOUTH].start(env.agents[PORT_SOUTH].sequencer);
      seq[PORT_WEST].start(env.agents[PORT_WEST].sequencer);
    join

    #300ns;
    `uvm_info(get_type_name(), ">>> FINISHED HOTSPOT CONTENTION TEST <<<", UVM_LOW)
    phase.drop_objection(this, "Completed hotspot test");
  endtask : run_phase

endclass : noc_hotspot_test

//------------------------------------------------------------------------------
// Corner Cases Test (Single-flit, max MTU, alternate VCs)
//------------------------------------------------------------------------------
class noc_corner_cases_test extends noc_base_test;
  `uvm_component_utils(noc_corner_cases_test)

  function new(string name = "noc_corner_cases_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    noc_corner_cases_seq seq[noc_pkg::NUM_PORTS];

    phase.raise_objection(this, "Starting corner cases test");
    `uvm_info(get_type_name(), ">>> STARTING CORNER-CASES TEST <<<", UVM_LOW)

    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      seq[p] = noc_corner_cases_seq::type_id::create($sformatf("corner_seq_%0d", p));
    end

    fork
      seq[PORT_LOCAL].start(env.agents[PORT_LOCAL].sequencer);
      seq[PORT_EAST].start(env.agents[PORT_EAST].sequencer);
    join

    #200ns;
    phase.drop_objection(this, "Completed corner cases test");
  endtask : run_phase

endclass : noc_corner_cases_test

`endif // NOC_TEST_LIB_SV
