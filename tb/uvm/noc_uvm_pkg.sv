//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_uvm_pkg.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Master UVM Package aggregating all testbench components,
//              transactions, sequences, drivers, monitors, and scoreboards.
//==============================================================================

`ifndef NOC_UVM_PKG_SV
`define NOC_UVM_PKG_SV

`include "uvm_macros.sv"

package noc_uvm_pkg;
  import uvm_pkg::*;
  import noc_pkg::*;

  `include "noc_flit_item.sv"
  `include "noc_packet_item.sv"
  `include "noc_sequencer.sv"
  `include "noc_driver.sv"
  `include "noc_monitor.sv"
  `include "noc_agent.sv"
  `include "noc_scoreboard.sv"
  `include "noc_coverage.sv"
  `include "noc_seq_lib.sv"
  `include "noc_env.sv"
  `include "noc_test_lib.sv"

endpackage : noc_uvm_pkg

`endif // NOC_UVM_PKG_SV
