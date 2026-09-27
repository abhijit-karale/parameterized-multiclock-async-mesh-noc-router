//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_flit_item.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: UVM Sequence Item representing an individual NoC Flit.
//              Provides serialization, bit packing, and comparison utilities.
//==============================================================================

`ifndef NOC_FLIT_ITEM_SV
`define NOC_FLIT_ITEM_SV

import uvm_pkg::*;
`include "uvm_macros.sv"
import noc_pkg::*;

class noc_flit_item extends uvm_sequence_item;

  // Flit Content Fields
  rand flit_type_t                     flit_type;
  rand bit [noc_pkg::DEFAULT_VC_WIDTH-1:0] vc_id;
  rand bit [noc_pkg::DEFAULT_X_WIDTH-1:0]  dest_x;
  rand bit [noc_pkg::DEFAULT_Y_WIDTH-1:0]  dest_y;
  rand bit [noc_pkg::DEFAULT_X_WIDTH-1:0]  src_x;
  rand bit [noc_pkg::DEFAULT_Y_WIDTH-1:0]  src_y;
  rand bit [noc_pkg::DEFAULT_PKT_ID_W-1:0] pkt_id;
  rand bit [noc_pkg::DEFAULT_DATA_W-1:0]   payload;

  // Metadata
  realtime timestamp;
  port_id_t ingress_port;
  port_id_t egress_port;

  `uvm_object_utils_begin(noc_flit_item)
    `uvm_field_enum(flit_type_t, flit_type, UVM_ALL_ON)
    `uvm_field_int(vc_id,        UVM_ALL_ON)
    `uvm_field_int(dest_x,       UVM_ALL_ON)
    `uvm_field_int(dest_y,       UVM_ALL_ON)
    `uvm_field_int(src_x,        UVM_ALL_ON)
    `uvm_field_int(src_y,        UVM_ALL_ON)
    `uvm_field_int(pkt_id,       UVM_ALL_ON)
    `uvm_field_int(payload,      UVM_ALL_ON)
    `uvm_field_real(timestamp,   UVM_ALL_ON | UVM_NOCOMPARE)
  `uvm_object_utils_end

  function new(string name = "noc_flit_item");
    super.new(name);
    timestamp = $realtime;
    flit_type = FLIT_BODY;
    vc_id     = '0;
  endfunction

  // Pack into raw bit vector matching flit_t
  function void pack_to_raw(output logic [noc_pkg::FLIT_WIDTH-1:0] raw_flit);
    flit_t f;
    f.flit_type = flit_type;
    f.vc_id     = vc_id;
    f.dest_x    = dest_x;
    f.dest_y    = dest_y;
    f.src_x     = src_x;
    f.src_y     = src_y;
    f.pkt_id    = pkt_id;
    f.payload   = payload;
    raw_flit    = f;
  endfunction

  // Unpack from raw bit vector
  function void unpack_from_raw(input logic [noc_pkg::FLIT_WIDTH-1:0] raw_flit);
    flit_t f;
    f         = raw_flit;
    flit_type = flit_type_t'(f.flit_type);
    vc_id     = f.vc_id;
    dest_x    = f.dest_x;
    dest_y    = f.dest_y;
    src_x     = f.src_x;
    src_y     = f.src_y;
    pkt_id    = f.pkt_id;
    payload   = f.payload;
  endfunction

  virtual function string convert2string();
    return $sformatf("Flit [%s] VC=%0d PktID=0x%02h Src=(%0d,%0d) Dest=(%0d,%0d) Payload=0x%08h @ %0t",
                     flit_type.name(), vc_id, pkt_id, src_x, src_y, dest_x, dest_y, payload, timestamp);
  endfunction

endclass : noc_flit_item

`endif // NOC_FLIT_ITEM_SV
