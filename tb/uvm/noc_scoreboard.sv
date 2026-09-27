//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_scoreboard.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Multi-Port Scoreboard with Golden XY Dimension-Order Reference
//              Model, End-to-End Latency Tracking, Data Integrity Verification,
//              and Comprehensive Throughput / Jitter Profiling.
//==============================================================================

`ifndef NOC_SCOREBOARD_SV
`define NOC_SCOREBOARD_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
`include "noc_packet_item.sv"
import noc_pkg::*;

`uvm_analysis_imp_decl(_port0_ing)
`uvm_analysis_imp_decl(_port1_ing)
`uvm_analysis_imp_decl(_port2_ing)
`uvm_analysis_imp_decl(_port3_ing)
`uvm_analysis_imp_decl(_port4_ing)

`uvm_analysis_imp_decl(_port0_egr)
`uvm_analysis_imp_decl(_port1_egr)
`uvm_analysis_imp_decl(_port2_egr)
`uvm_analysis_imp_decl(_port3_egr)
`uvm_analysis_imp_decl(_port4_egr)

class noc_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(noc_scoreboard)

  // Router Coordinates
  int router_x = 0;
  int router_y = 0;

  // Analysis Imports for 5 Ingress Ports
  uvm_analysis_imp_port0_ing #(noc_packet_item, noc_scoreboard) ing_imp_port0;
  uvm_analysis_imp_port1_ing #(noc_packet_item, noc_scoreboard) ing_imp_port1;
  uvm_analysis_imp_port2_ing #(noc_packet_item, noc_scoreboard) ing_imp_port2;
  uvm_analysis_imp_port3_ing #(noc_packet_item, noc_scoreboard) ing_imp_port3;
  uvm_analysis_imp_port4_ing #(noc_packet_item, noc_scoreboard) ing_imp_port4;

  // Analysis Imports for 5 Egress Ports
  uvm_analysis_imp_port0_egr #(noc_packet_item, noc_scoreboard) egr_imp_port0;
  uvm_analysis_imp_port1_egr #(noc_packet_item, noc_scoreboard) egr_imp_port1;
  uvm_analysis_imp_port2_egr #(noc_packet_item, noc_scoreboard) egr_imp_port2;
  uvm_analysis_imp_port3_egr #(noc_packet_item, noc_scoreboard) egr_imp_port3;
  uvm_analysis_imp_port4_egr #(noc_packet_item, noc_scoreboard) egr_imp_port4;

  // Expected Packet Queues per Egress Port
  local noc_packet_item expected_pkts [noc_pkg::NUM_PORTS][$];

  // Statistics & Latency Tracking
  int unsigned pkts_injected [noc_pkg::NUM_PORTS];
  int unsigned pkts_received [noc_pkg::NUM_PORTS];
  int unsigned total_injected;
  int unsigned total_received;
  int unsigned total_mismatches;

  realtime min_latency;
  realtime max_latency;
  realtime sum_latency;
  realtime min_lat_per_port [noc_pkg::NUM_PORTS];
  realtime max_lat_per_port [noc_pkg::NUM_PORTS];
  realtime sum_lat_per_port [noc_pkg::NUM_PORTS];

  // Latency Histogram Bins: [<15ns, 15-25ns, 25-35ns, 35-50ns, >50ns]
  int unsigned lat_bins [5];

  function new(string name = "noc_scoreboard", uvm_component parent = null);
    super.new(name, parent);
    total_injected   = 0;
    total_received   = 0;
    total_mismatches = 0;
    min_latency      = 1.0e9;
    max_latency      = 0.0;
    sum_latency      = 0.0;

    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      pkts_injected[p]    = 0;
      pkts_received[p]    = 0;
      min_lat_per_port[p] = 1.0e9;
      max_lat_per_port[p] = 0.0;
      sum_lat_per_port[p] = 0.0;
    end

    for (int b = 0; b < 5; b++) lat_bins[b] = 0;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ing_imp_port0 = new("ing_imp_port0", this);
    ing_imp_port1 = new("ing_imp_port1", this);
    ing_imp_port2 = new("ing_imp_port2", this);
    ing_imp_port3 = new("ing_imp_port3", this);
    ing_imp_port4 = new("ing_imp_port4", this);

    egr_imp_port0 = new("egr_imp_port0", this);
    egr_imp_port1 = new("egr_imp_port1", this);
    egr_imp_port2 = new("egr_imp_port2", this);
    egr_imp_port3 = new("egr_imp_port3", this);
    egr_imp_port4 = new("egr_imp_port4", this);
  endfunction

  // Golden XY Dimension-Order Reference Model
  function port_id_t compute_xy_route(bit [noc_pkg::DEFAULT_X_WIDTH-1:0] dx,
                                      bit [noc_pkg::DEFAULT_Y_WIDTH-1:0] dy);
    if (dx > router_x) begin
      return PORT_EAST;
    end else if (dx < router_x) begin
      return PORT_WEST;
    end else begin
      if (dy > router_y) begin
        return PORT_NORTH;
      end else if (dy < router_y) begin
        return PORT_SOUTH;
      end else begin
        return PORT_LOCAL;
      end
    end
  endfunction

  // Common Ingress Ingestion
  virtual function void process_ingress(port_id_t in_port, noc_packet_item pkt);
    port_id_t exp_egress;
    noc_packet_item clone_pkt;

    $cast(clone_pkt, pkt.clone());
    exp_egress = compute_xy_route(clone_pkt.dest_x, clone_pkt.dest_y);
    clone_pkt.egress_port = exp_egress;

    expected_pkts[exp_egress].push_back(clone_pkt);
    pkts_injected[in_port]++;
    total_injected++;

    `uvm_info(get_type_name(), $sformatf("[INGRESS] Port %s injected PktID=0x%02h -> Expected Egress %s",
              port2string(in_port), clone_pkt.pkt_id, port2string(exp_egress)), UVM_HIGH)
  endfunction

  // Common Egress Ingestion & Verification
  virtual function void process_egress(port_id_t out_port, noc_packet_item actual_pkt);
    noc_packet_item exp_pkt;
    realtime lat;

    pkts_received[out_port]++;
    total_received++;

    if (expected_pkts[out_port].size() == 0) begin
      `uvm_error("SCB_UNEXPECTED", $sformatf("Unexpected packet received at egress port %s: PktID=0x%02h",
                 port2string(out_port), actual_pkt.pkt_id))
      total_mismatches++;
      return;
    end

    exp_pkt = expected_pkts[out_port].pop_front();

    // 1. Check Header Match
    if (actual_pkt.pkt_id !== exp_pkt.pkt_id ||
        actual_pkt.dest_x !== exp_pkt.dest_x ||
        actual_pkt.dest_y !== exp_pkt.dest_y ||
        actual_pkt.src_x  !== exp_pkt.src_x  ||
        actual_pkt.src_y  !== exp_pkt.src_y  ||
        actual_pkt.num_flits !== exp_pkt.num_flits) begin
      `uvm_error("SCB_HDR_MISMATCH", $sformatf("Header Mismatch on Egress Port %s!\nExpected: %s\nActual:   %s",
                 port2string(out_port), exp_pkt.convert2string(), actual_pkt.convert2string()))
      total_mismatches++;
      return;
    end

    // 2. Check Payload Bit Fidelity
    for (int i = 0; i < exp_pkt.payloads.size(); i++) begin
      if (actual_pkt.payloads[i] !== exp_pkt.payloads[i]) begin
        `uvm_error("SCB_DATA_MISMATCH", $sformatf("Data payload mismatch on PktID 0x%02h Flit %0d! Expected=0x%08h, Got=0x%08h",
                   exp_pkt.pkt_id, i, exp_pkt.payloads[i], actual_pkt.payloads[i]))
        total_mismatches++;
        return;
      end
    end

    // 3. Compute and Record End-to-End Latency
    lat = actual_pkt.egress_time - exp_pkt.injection_time;
    if (lat < 0) lat = 0.0;
    actual_pkt.packet_latency = lat;

    sum_latency += lat;
    if (lat < min_latency) min_latency = lat;
    if (lat > max_latency) max_latency = lat;

    sum_lat_per_port[out_port] += lat;
    if (lat < min_lat_per_port[out_port]) min_lat_per_port[out_port] = lat;
    if (lat > max_lat_per_port[out_port]) max_lat_per_port[out_port] = lat;

    // Latency Distribution
    if (lat < 15.0)      lat_bins[0]++;
    else if (lat < 25.0) lat_bins[1]++;
    else if (lat < 35.0) lat_bins[2]++;
    else if (lat < 50.0) lat_bins[3]++;
    else                 lat_bins[4]++;

    `uvm_info(get_type_name(), $sformatf("[EGRESS PASS] PktID=0x%02h matched on Port %s. Latency = %0.2f ns",
              actual_pkt.pkt_id, port2string(out_port), lat), UVM_HIGH)
  endfunction

  // Port Ingress Write Implementations
  virtual function void write_port0_ing(noc_packet_item pkt); process_ingress(PORT_LOCAL, pkt); endfunction
  virtual function void write_port1_ing(noc_packet_item pkt); process_ingress(PORT_NORTH, pkt); endfunction
  virtual function void write_port2_ing(noc_packet_item pkt); process_ingress(PORT_EAST,  pkt); endfunction
  virtual function void write_port3_ing(noc_packet_item pkt); process_ingress(PORT_SOUTH, pkt); endfunction
  virtual function void write_port4_ing(noc_packet_item pkt); process_ingress(PORT_WEST,  pkt); endfunction

  // Port Egress Write Implementations
  virtual function void write_port0_egr(noc_packet_item pkt); process_egress(PORT_LOCAL, pkt); endfunction
  virtual function void write_port1_egr(noc_packet_item pkt); process_egress(PORT_NORTH, pkt); endfunction
  virtual function void write_port2_egr(noc_packet_item pkt); process_egress(PORT_EAST,  pkt); endfunction
  virtual function void write_port3_egr(noc_packet_item pkt); process_egress(PORT_SOUTH, pkt); endfunction
  virtual function void write_port4_egr(noc_packet_item pkt); process_egress(PORT_WEST,  pkt); endfunction

  // Check Phase: Verify Zero Dropped Packets
  virtual function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      if (expected_pkts[p].size() > 0) begin
        `uvm_error("SCB_DROPPED_PKT", $sformatf("Scoreboard port %s has %0d unconsumed expected packets at end of simulation!",
                   port2string(port_id_t'(p)), expected_pkts[p].size()))
        total_mismatches += expected_pkts[p].size();
      end
    end
  endfunction

  // Report Phase: Formatted ASCII Latency & Throughput Summary
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    real avg_lat;
    avg_lat = (total_received > 0) ? (sum_latency / total_received) : 0.0;

    $display("\n================================================================================");
    $display("                     NoC ROUTER LATENCY & VERIFICATION REPORT                    ");
    $display("================================================================================");
    $display("  Total Packets Injected: %0d", total_injected);
    $display("  Total Packets Received: %0d", total_received);
    $display("  Total Mismatches/Drops: %0d", total_mismatches);
    $display("--------------------------------------------------------------------------------");
    $display("  PER-PORT TRAFFIC BREAKDOWN:");
    $display("  Port       | Injected | Received | Min Lat (ns) | Max Lat (ns) | Avg Lat (ns)");
    $display("  -----------+----------+----------+--------------+--------------+-------------");
    for (int p = 0; p < noc_pkg::NUM_PORTS; p++) begin
      real p_avg;
      p_avg = (pkts_received[p] > 0) ? (sum_lat_per_port[p] / pkts_received[p]) : 0.0;
      $display("  %-10s | %8d | %8d | %12.2f | %12.2f | %11.2f",
               port2string(port_id_t'(p)), pkts_injected[p], pkts_received[p],
               (pkts_received[p] > 0 ? min_lat_per_port[p] : 0.0),
               max_lat_per_port[p], p_avg);
    end
    $display("--------------------------------------------------------------------------------");
    $display("  OVERALL LATENCY PROFILING:");
    $display("    Min Latency: %0.2f ns", (total_received > 0 ? min_latency : 0.0));
    $display("    Max Latency: %0.2f ns", max_latency);
    $display("    Avg Latency: %0.2f ns", avg_lat);
    $display("--------------------------------------------------------------------------------");
    $display("  LATENCY DISTRIBUTION HISTOGRAM:");
    $display("    [ 0 - 15 ns ] : %0d pkts", lat_bins[0]);
    $display("    [15 - 25 ns ] : %0d pkts", lat_bins[1]);
    $display("    [25 - 35 ns ] : %0d pkts", lat_bins[2]);
    $display("    [35 - 50 ns ] : %0d pkts", lat_bins[3]);
    $display("    [ > 50   ns ] : %0d pkts", lat_bins[4]);
    $display("================================================================================");
    if (total_mismatches == 0 && total_received > 0 && total_received == total_injected) begin
      $display("  >>> FINAL RESULT: STATUS PASSED (100%% Packet Delivery, Zero Loss) <<<");
    end else begin
      $display("  >>> FINAL RESULT: STATUS FAILED (Mismatches=%0d, Injected=%0d, Received=%0d) <<<",
               total_mismatches, total_injected, total_received);
    end
    $display("================================================================================\n");
  endfunction

endclass : noc_scoreboard

`endif // NOC_SCOREBOARD_SV
