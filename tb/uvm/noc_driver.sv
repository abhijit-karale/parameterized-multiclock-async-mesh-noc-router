//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_driver.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Credit-Aware Multi-Clock Asynchronous NoC Port Driver.
//              Tracks upstream FIFO credits, drives serialized flits, and
//              returns downstream credit pulses to keep the network circulating.
//==============================================================================

`ifndef NOC_DRIVER_SV
`define NOC_DRIVER_SV


class noc_driver extends uvm_driver #(noc_packet_item);
  `uvm_component_utils(noc_driver)

  virtual noc_if vif;
  port_id_t      port_id;
  int            fifo_depth;

  // Upstream Credit Counter per VC
  int unsigned credits[noc_pkg::DEFAULT_NUM_VCS];

  function new(string name = "noc_driver", uvm_component parent = null);
    super.new(name, parent);
    fifo_depth = noc_pkg::DEFAULT_FIFO_DEP;
    port_id    = PORT_LOCAL;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual noc_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("DRV_NO_VIF", {"Virtual interface must be set for: ", get_full_name(), ".vif"});
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Initialize credits to downstream FIFO buffer capacity
    for (int v = 0; v < noc_pkg::DEFAULT_NUM_VCS; v++) begin
      credits[v] = fifo_depth;
    end

    // Initialize interface signals
    vif.drv_cb.rx_valid  <= 1'b0;
    vif.drv_cb.rx_data   <= '0;
    vif.drv_cb.credit_in <= '0;

    // Wait for reset release
    @(posedge vif.rst_n);
    repeat (5) @(vif.drv_cb);

    // Fork concurrent threads: Ingress injection, Credit Return receiver, Downstream credit sink
    fork
      packet_sender_thread();
      credit_listener_thread();
      downstream_credit_return_thread();
    join
  endtask : run_phase

  // Thread 1: Ingress packet transmission
  virtual task packet_sender_thread();
    noc_packet_item pkt;
    noc_flit_item   flits[];
    logic [noc_pkg::FLIT_WIDTH-1:0] raw_flit;

    forever begin
      seq_item_port.get_next_item(pkt);
      pkt.ingress_port   = port_id;
      pkt.injection_time = $realtime;
      pkt.get_flits(flits);

      `uvm_info(get_type_name(), $sformatf("Driving Packet ID=0x%02h with %0d flits to port %s",
                pkt.pkt_id, pkt.num_flits, port2string(port_id)), UVM_HIGH)

      for (int i = 0; i < flits.size(); i++) begin
        // Wait until credit is available for target VC
        wait (credits[flits[i].vc_id] > 0);

        @(vif.drv_cb);
        flits[i].pack_to_raw(raw_flit);
        vif.drv_cb.rx_valid <= 1'b1;
        vif.drv_cb.rx_data  <= raw_flit;
        credits[flits[i].vc_id]--;

        `uvm_info(get_type_name(), $sformatf("Injected Flit [%s] on Port %s VC=%0d, Remaining Credits=%0d",
                  flits[i].flit_type.name(), port2string(port_id), flits[i].vc_id, credits[flits[i].vc_id]), UVM_DEBUG)
      end

      @(vif.drv_cb);
      vif.drv_cb.rx_valid <= 1'b0;
      vif.drv_cb.rx_data  <= '0;

      seq_item_port.item_done();
    end
  endtask : packet_sender_thread

  // Thread 2: Ingress credit replenishment listener
  virtual task credit_listener_thread();
    forever begin
      @(vif.drv_cb);
      for (int v = 0; v < noc_pkg::DEFAULT_NUM_VCS; v++) begin
        if (vif.drv_cb.credit_out[v]) begin
          credits[v]++;
          `uvm_info(get_type_name(), $sformatf("Replenished Credit on Port %s VC=%0d, Current Credits=%0d",
                    port2string(port_id), v, credits[v]), UVM_DEBUG)
        end
      end
    end
  endtask : credit_listener_thread

  // Thread 3: Return credits for egress flits leaving router to keep pipeline flowing
  virtual task downstream_credit_return_thread();
    forever begin
      @(vif.drv_cb);
      vif.drv_cb.credit_in <= '0;
      if (vif.tx_valid) begin
        // Extract egress VC ID
        bit [noc_pkg::DEFAULT_VC_WIDTH-1:0] egress_vc;
        egress_vc = vif.tx_data[noc_pkg::FLIT_WIDTH - 3 -: noc_pkg::DEFAULT_VC_WIDTH];

        // Return credit pulse to router
        vif.drv_cb.credit_in[egress_vc] <= 1'b1;
      end
    end
  endtask : downstream_credit_return_thread

endclass : noc_driver

`endif // NOC_DRIVER_SV
