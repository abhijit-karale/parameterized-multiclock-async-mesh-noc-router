//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_monitor.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Multi-Clock Port Monitor. Passively sniffs ingress and egress
//              flits, reassembles flit streams into atomic packet objects,
//              records latency timestamps, and publishes to UVM Scoreboard.
//==============================================================================

`ifndef NOC_MONITOR_SV
`define NOC_MONITOR_SV


class noc_monitor extends uvm_monitor;
  `uvm_component_utils(noc_monitor)

  virtual noc_if vif;
  port_id_t      port_id;

  // Analysis Ports to Scoreboard and Coverage
  uvm_analysis_port #(noc_packet_item) ingress_ap;
  uvm_analysis_port #(noc_packet_item) egress_ap;

  // Internal Reassembly Buffers per VC
  local noc_packet_item ingress_pkt_buf [noc_pkg::DEFAULT_NUM_VCS];
  local noc_packet_item egress_pkt_buf  [noc_pkg::DEFAULT_NUM_VCS];

  function new(string name = "noc_monitor", uvm_component parent = null);
    super.new(name, parent);
    port_id = PORT_LOCAL;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ingress_ap = new("ingress_ap", this);
    egress_ap  = new("egress_ap",  this);

    if (!uvm_config_db#(virtual noc_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("MON_NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    @(posedge vif.rst_n);
    repeat (2) @(vif.mon_cb);

    fork
      monitor_ingress_thread();
      monitor_egress_thread();
    join
  endtask : run_phase

  // Thread 1: Ingress Packet Reassembly
  virtual task monitor_ingress_thread();
    noc_flit_item flit;

    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.rx_valid) begin
        flit = noc_flit_item::type_id::create("rx_flit");
        flit.unpack_from_raw(vif.mon_cb.rx_data);
        flit.ingress_port = port_id;
        flit.timestamp    = $realtime;

        process_ingress_flit(flit);
      end
    end
  endtask : monitor_ingress_thread

  virtual function void process_ingress_flit(noc_flit_item flit);
    int vc = flit.vc_id;

    case (flit.flit_type)
      FLIT_HEAD, FLIT_HEAD_TAIL: begin
        ingress_pkt_buf[vc]                = noc_packet_item::type_id::create($sformatf("ing_pkt_vc%0d", vc));
        ingress_pkt_buf[vc].vc_id          = flit.vc_id;
        ingress_pkt_buf[vc].dest_x         = flit.dest_x;
        ingress_pkt_buf[vc].dest_y         = flit.dest_y;
        ingress_pkt_buf[vc].src_x          = flit.src_x;
        ingress_pkt_buf[vc].src_y          = flit.src_y;
        ingress_pkt_buf[vc].pkt_id         = flit.pkt_id;
        ingress_pkt_buf[vc].ingress_port   = port_id;
        ingress_pkt_buf[vc].injection_time = flit.timestamp;
        ingress_pkt_buf[vc].payloads       = new[1];
        ingress_pkt_buf[vc].payloads[0]    = flit.payload;
        ingress_pkt_buf[vc].num_flits      = 1;

        if (flit.flit_type == FLIT_HEAD_TAIL) begin
          ingress_ap.write(ingress_pkt_buf[vc]);
          ingress_pkt_buf[vc] = null;
        end
      end

      FLIT_BODY: begin
        if (ingress_pkt_buf[vc] != null) begin
          ingress_pkt_buf[vc].payloads = new[ingress_pkt_buf[vc].payloads.size() + 1](ingress_pkt_buf[vc].payloads);
          ingress_pkt_buf[vc].payloads[ingress_pkt_buf[vc].payloads.size() - 1] = flit.payload;
          ingress_pkt_buf[vc].num_flits++;
        end
      end

      FLIT_TAIL: begin
        if (ingress_pkt_buf[vc] != null) begin
          ingress_pkt_buf[vc].payloads = new[ingress_pkt_buf[vc].payloads.size() + 1](ingress_pkt_buf[vc].payloads);
          ingress_pkt_buf[vc].payloads[ingress_pkt_buf[vc].payloads.size() - 1] = flit.payload;
          ingress_pkt_buf[vc].num_flits++;

          ingress_ap.write(ingress_pkt_buf[vc]);
          ingress_pkt_buf[vc] = null;
        end
      end
    endcase
  endfunction : process_ingress_flit

  // Thread 2: Egress Packet Reassembly
  virtual task monitor_egress_thread();
    noc_flit_item flit;

    forever begin
      @(vif.mon_cb);
      if (vif.mon_cb.tx_valid) begin
        flit = noc_flit_item::type_id::create("tx_flit");
        flit.unpack_from_raw(vif.mon_cb.tx_data);
        flit.egress_port = port_id;
        flit.timestamp   = $realtime;

        process_egress_flit(flit);
      end
    end
  endtask : monitor_egress_thread

  virtual function void process_egress_flit(noc_flit_item flit);
    int vc = flit.vc_id;

    case (flit.flit_type)
      FLIT_HEAD, FLIT_HEAD_TAIL: begin
        egress_pkt_buf[vc]             = noc_packet_item::type_id::create($sformatf("egr_pkt_vc%0d", vc));
        egress_pkt_buf[vc].vc_id       = flit.vc_id;
        egress_pkt_buf[vc].dest_x      = flit.dest_x;
        egress_pkt_buf[vc].dest_y      = flit.dest_y;
        egress_pkt_buf[vc].src_x       = flit.src_x;
        egress_pkt_buf[vc].src_y       = flit.src_y;
        egress_pkt_buf[vc].pkt_id      = flit.pkt_id;
        egress_pkt_buf[vc].egress_port = port_id;
        egress_pkt_buf[vc].egress_time = flit.timestamp;
        egress_pkt_buf[vc].payloads    = new[1];
        egress_pkt_buf[vc].payloads[0] = flit.payload;
        egress_pkt_buf[vc].num_flits   = 1;

        if (flit.flit_type == FLIT_HEAD_TAIL) begin
          egress_ap.write(egress_pkt_buf[vc]);
          egress_pkt_buf[vc] = null;
        end
      end

      FLIT_BODY: begin
        if (egress_pkt_buf[vc] != null) begin
          egress_pkt_buf[vc].payloads = new[egress_pkt_buf[vc].payloads.size() + 1](egress_pkt_buf[vc].payloads);
          egress_pkt_buf[vc].payloads[egress_pkt_buf[vc].payloads.size() - 1] = flit.payload;
          egress_pkt_buf[vc].num_flits++;
        end
      end

      FLIT_TAIL: begin
        if (egress_pkt_buf[vc] != null) begin
          egress_pkt_buf[vc].payloads = new[egress_pkt_buf[vc].payloads.size() + 1](egress_pkt_buf[vc].payloads);
          egress_pkt_buf[vc].payloads[egress_pkt_buf[vc].payloads.size() - 1] = flit.payload;
          egress_pkt_buf[vc].num_flits++;
          egress_pkt_buf[vc].egress_time = flit.timestamp;

          egress_ap.write(egress_pkt_buf[vc]);
          egress_pkt_buf[vc] = null;
        end
      end
    endcase
  endfunction : process_egress_flit

endclass : noc_monitor

`endif // NOC_MONITOR_SV
