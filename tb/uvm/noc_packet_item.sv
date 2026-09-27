//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_packet_item.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: High-level NoC Packet Transaction. Assembles flit streams into
//              packets, tracks injection and egress timestamps, and computes
//              end-to-end multi-clock packet latencies.
//==============================================================================

`ifndef NOC_PACKET_ITEM_SV
`define NOC_PACKET_ITEM_SV


class noc_packet_item extends uvm_sequence_item;

  // Packet Header Fields
  rand bit [noc_pkg::DEFAULT_VC_WIDTH-1:0] vc_id;
  rand bit [noc_pkg::DEFAULT_X_WIDTH-1:0]  dest_x;
  rand bit [noc_pkg::DEFAULT_Y_WIDTH-1:0]  dest_y;
  rand bit [noc_pkg::DEFAULT_X_WIDTH-1:0]  src_x;
  rand bit [noc_pkg::DEFAULT_Y_WIDTH-1:0]  src_y;
  rand bit [noc_pkg::DEFAULT_PKT_ID_W-1:0] pkt_id;

  // Packet Payload Structure
  rand int unsigned                        num_flits;
  rand bit [noc_pkg::DEFAULT_DATA_W-1:0]   payloads[];

  // Timing and Latency Profiling
  realtime injection_time;
  realtime egress_time;
  realtime packet_latency;
  port_id_t ingress_port;
  port_id_t egress_port;

  // Constraints
  constraint c_num_flits {
    num_flits inside {[1:8]};
  }

  constraint c_payload_size {
    payloads.size() == num_flits;
  }

  constraint c_coords {
    dest_x inside {[0:3]};
    dest_y inside {[0:3]};
    src_x  inside {[0:3]};
    src_y  inside {[0:3]};
  }

  `uvm_object_utils_begin(noc_packet_item)
    `uvm_field_int(vc_id,          UVM_ALL_ON)
    `uvm_field_int(dest_x,         UVM_ALL_ON)
    `uvm_field_int(dest_y,         UVM_ALL_ON)
    `uvm_field_int(src_x,          UVM_ALL_ON)
    `uvm_field_int(src_y,          UVM_ALL_ON)
    `uvm_field_int(pkt_id,         UVM_ALL_ON)
    `uvm_field_int(num_flits,      UVM_ALL_ON)
    `uvm_field_array_int(payloads, UVM_ALL_ON)
    `uvm_field_real(injection_time,UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_real(egress_time,   UVM_ALL_ON | UVM_NOCOMPARE)
    `uvm_field_real(packet_latency,UVM_ALL_ON | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "noc_packet_item");
    super.new(name);
    injection_time = 0.0;
    egress_time    = 0.0;
    packet_latency = 0.0;
    ingress_port   = PORT_LOCAL;
    egress_port    = PORT_NONE;
  endfunction

  // Convert Packet into stream of noc_flit_item objects
  function void get_flits(output noc_flit_item flits[]);
    flits = new[num_flits];
    for (int i = 0; i < num_flits; i++) begin
      flits[i] = noc_flit_item::type_id::create($sformatf("flit_%0d", i));
      flits[i].vc_id   = vc_id;
      flits[i].dest_x  = dest_x;
      flits[i].dest_y  = dest_y;
      flits[i].src_x   = src_x;
      flits[i].src_y   = src_y;
      flits[i].pkt_id  = pkt_id;
      flits[i].payload = payloads[i];
      flits[i].ingress_port = ingress_port;

      if (num_flits == 1) begin
        flits[i].flit_type = FLIT_HEAD_TAIL;
      end else if (i == 0) begin
        flits[i].flit_type = FLIT_HEAD;
      end else if (i == num_flits - 1) begin
        flits[i].flit_type = FLIT_TAIL;
      end else begin
        flits[i].flit_type = FLIT_BODY;
      end
    end
  endfunction

  virtual function string convert2string();
    return $sformatf("Packet ID=0x%02h VC=%0d Flits=%0d Src=(%0d,%0d) Dest=(%0d,%0d) InPort=%s OutPort=%s Latency=%0.2fns",
                     pkt_id, vc_id, num_flits, src_x, src_y, dest_x, dest_y,
                     port2string(ingress_port), port2string(egress_port), packet_latency);
  endfunction

endclass : noc_packet_item

`endif // NOC_PACKET_ITEM_SV
