//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_env.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: UVM Environment instantiating 5 Port Agents (Local, North, East,
//              South, West), Scoreboard, and Functional Coverage collector.
//==============================================================================

`ifndef NOC_ENV_SV
`define NOC_ENV_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
`include "noc_agent.sv"
`include "noc_scoreboard.sv"
`include "noc_coverage.sv"
import noc_pkg::*;

class noc_env extends uvm_env;
  `uvm_component_utils(noc_env)

  noc_agent      agents [noc_pkg::NUM_PORTS];
  noc_scoreboard scoreboard;
  noc_coverage   coverage;

  function new(string name = "noc_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    // Build Agents for all 5 ports
    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      string agent_name;
      agent_name = $sformatf("agent_%s", port2string(port_id_t'(p)));
      agents[p]  = noc_agent::type_id::create(agent_name, this);
      agents[p].port_id = port_id_t'(p);
    end

    scoreboard = noc_scoreboard::type_id::create("scoreboard", this);
    coverage   = noc_coverage::type_id::create("coverage", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    // Connect Agent Monitors to Scoreboard and Coverage
    agents[PORT_LOCAL].monitor.ingress_ap.connect(scoreboard.ing_imp_port0);
    agents[PORT_NORTH].monitor.ingress_ap.connect(scoreboard.ing_imp_port1);
    agents[PORT_EAST].monitor.ingress_ap.connect(scoreboard.ing_imp_port2);
    agents[PORT_SOUTH].monitor.ingress_ap.connect(scoreboard.ing_imp_port3);
    agents[PORT_WEST].monitor.ingress_ap.connect(scoreboard.ing_imp_port4);

    agents[PORT_LOCAL].monitor.egress_ap.connect(scoreboard.egr_imp_port0);
    agents[PORT_NORTH].monitor.egress_ap.connect(scoreboard.egr_imp_port1);
    agents[PORT_EAST].monitor.egress_ap.connect(scoreboard.egr_imp_port2);
    agents[PORT_SOUTH].monitor.egress_ap.connect(scoreboard.egr_imp_port3);
    agents[PORT_WEST].monitor.egress_ap.connect(scoreboard.egr_imp_port4);

    // Connect Egress to Coverage
    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      agents[p].monitor.egress_ap.connect(coverage.analysis_export);
    end
  endfunction

endclass : noc_env

`endif // NOC_ENV_SV
