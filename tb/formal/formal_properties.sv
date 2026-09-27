//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    formal_properties.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Comprehensive SystemVerilog Assertions (SVA) and Formal Properties
//              suite for JasperGold and SymbiYosys. Enforces CDC safety, Gray-code
//              Hamming distance, credit conservation, deadlock-freedom, and
//              deterministic XY wormhole routing invariants.
//==============================================================================

`ifndef FORMAL_PROPERTIES_SV
`define FORMAL_PROPERTIES_SV

import noc_pkg::*;

module formal_properties #(
  parameter int ROUTER_X   = 0,
  parameter int ROUTER_Y   = 0,
  parameter int NUM_PORTS  = noc_pkg::NUM_PORTS,
  parameter int NUM_VCS    = noc_pkg::DEFAULT_NUM_VCS,
  parameter int VC_WIDTH   = noc_pkg::DEFAULT_VC_WIDTH,
  parameter int X_WIDTH    = noc_pkg::DEFAULT_X_WIDTH,
  parameter int Y_WIDTH    = noc_pkg::DEFAULT_Y_WIDTH,
  parameter int FIFO_DEPTH = noc_pkg::DEFAULT_FIFO_DEP,
  parameter int FLIT_WIDTH = noc_pkg::FLIT_WIDTH
) (
  // Router Clock and Reset
  input  logic                      clk_mesh,
  input  logic                      rst_n_mesh,

  // Port RX Interfaces
  input  logic [NUM_PORTS-1:0]      rx_clk,
  input  logic [NUM_PORTS-1:0]      rx_rst_n,
  input  logic [NUM_PORTS-1:0]      rx_valid,
  input  logic [FLIT_WIDTH-1:0]     rx_data [NUM_PORTS],
  input  logic [NUM_VCS-1:0]        credit_out [NUM_PORTS],

  // Port TX Interfaces
  input  logic                      tx_clk,
  input  logic                      tx_rst_n,
  input  logic [NUM_PORTS-1:0]      tx_valid,
  input  logic [FLIT_WIDTH-1:0]     tx_data [NUM_PORTS],
  input  logic [NUM_VCS-1:0]        credit_in [NUM_PORTS],

  // Internal Router Monitoring Probes
  input  logic [NUM_VCS-1:0]        vc_valid [NUM_PORTS],
  input  logic [NUM_VCS-1:0]        vc_pop   [NUM_PORTS],
  input  logic [NUM_VCS-1:0]        has_credit [NUM_PORTS],
  input  logic [NUM_PORTS-1:0]      crossbar_grant [NUM_PORTS]
);

  //----------------------------------------------------------------------------
  // PROPERTY 1: Gray Code Single-Bit Transition (Hamming Distance <= 1)
  // Guarantees zero multi-bit CDC race conditions during pointer transfers.
  //----------------------------------------------------------------------------
  genvar p_idx, v_idx;
  generate
    for (p_idx = 0; p_idx < NUM_PORTS; p_idx++) begin : gen_gray_checks
      for (v_idx = 0; v_idx < NUM_VCS; v_idx++) begin : gen_vc_gray_checks

        // Bound to async_fifo write pointer inside DUT
        property p_gray_wptr_hamming;
          @(posedge rx_clk[p_idx]) disable iff (!rx_rst_n[p_idx])
          $countones(noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.wptr_gray ^
                     $past(noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.wptr_gray)) <= 1;
        endproperty
        assert_gray_wptr_hamming: assert property (p_gray_wptr_hamming)
          else $error("[SVA-CDC-01] Gray write pointer Hamming distance > 1 at port %0d VC %0d!", p_idx, v_idx);

        // Bound to async_fifo read pointer inside DUT
        property p_gray_rptr_hamming;
          @(posedge clk_mesh) disable iff (!rst_n_mesh)
          $countones(noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.rptr_gray ^
                     $past(noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.rptr_gray)) <= 1;
        endproperty
        assert_gray_rptr_hamming: assert property (p_gray_rptr_hamming)
          else $error("[SVA-CDC-02] Gray read pointer Hamming distance > 1 at port %0d VC %0d!", p_idx, v_idx);

      end
    end
  endgenerate

  //----------------------------------------------------------------------------
  // PROPERTY 2: Dual-Clock FIFO Safety (No Overflow, No Underflow)
  //----------------------------------------------------------------------------
  generate
    for (p_idx = 0; p_idx < NUM_PORTS; p_idx++) begin : gen_fifo_safety
      for (v_idx = 0; v_idx < NUM_VCS; v_idx++) begin : gen_vc_fifo_safety

        // Never write to a full FIFO (Enforces credit backpressure upstream)
        property p_no_fifo_overflow;
          @(posedge rx_clk[p_idx]) disable iff (!rx_rst_n[p_idx])
          noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.wr_full |->
            !noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.wr_en;
        endproperty
        assert_no_fifo_overflow: assert property (p_no_fifo_overflow)
          else $error("[SVA-BUF-01] FIFO Overflow detected on input port %0d VC %0d!", p_idx, v_idx);

        // Never pop an empty FIFO
        property p_no_fifo_underflow;
          @(posedge clk_mesh) disable iff (!rst_n_mesh)
          noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.rd_empty |->
            !noc_router_top.gen_rx_ports[p_idx].u_async_vc_fifo.gen_vc_fifos[v_idx].u_fifo.rd_en;
        endproperty
        assert_no_fifo_underflow: assert property (p_no_fifo_underflow)
          else $error("[SVA-BUF-02] FIFO Underflow detected on port %0d VC %0d!", p_idx, v_idx);

      end
    end
  endgenerate

  //----------------------------------------------------------------------------
  // PROPERTY 3: Credit Conservation Invariant
  // Downstream credits must never exceed initial buffer depth or fall below zero.
  // When credits == 0, transmission is strictly inhibited.
  //----------------------------------------------------------------------------
  generate
    for (p_idx = 0; p_idx < NUM_PORTS; p_idx++) begin : gen_credit_invariants
      for (v_idx = 0; v_idx < NUM_VCS; v_idx++) begin : gen_vc_credit_invariants

        property p_credit_bounds;
          @(posedge clk_mesh) disable iff (!rst_n_mesh)
          noc_router_top.gen_credit_sync_port[p_idx].u_credit_mgr.credits[v_idx] <= FIFO_DEPTH;
        endproperty
        assert_credit_bounds: assert property (p_credit_bounds)
          else $error("[SVA-CRD-01] Credit overflow (> FIFO_DEPTH) at port %0d VC %0d!", p_idx, v_idx);

        // No transmission when credit count is zero
        property p_no_tx_without_credit;
          @(posedge clk_mesh) disable iff (!rst_n_mesh)
          (!has_credit[p_idx][v_idx]) |->
            !(tx_valid[p_idx] && (tx_data[p_idx][FLIT_WIDTH-3 -: VC_WIDTH] == v_idx[VC_WIDTH-1:0]));
        endproperty
        assert_no_tx_without_credit: assert property (p_no_tx_without_credit)
          else $error("[SVA-CRD-02] Flit transmitted with zero downstream credit at port %0d VC %0d!", p_idx, v_idx);

      end
    end
  endgenerate

  //----------------------------------------------------------------------------
  // PROPERTY 4: Deterministic XY Routing Correctness
  // Verifies that flits departing an output port strictly conform to XY logic.
  //----------------------------------------------------------------------------
  generate
    for (p_idx = 0; p_idx < NUM_PORTS; p_idx++) begin : gen_xy_correctness
      property p_xy_routing;
        @(posedge clk_mesh) disable iff (!rst_n_mesh)
        tx_valid[p_idx] |->
          (p_idx == PORT_EAST  ? (tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH -: X_WIDTH] > ROUTER_X[X_WIDTH-1:0]) :
           p_idx == PORT_WEST  ? (tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH -: X_WIDTH] < ROUTER_X[X_WIDTH-1:0]) :
           p_idx == PORT_NORTH ? (tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH -: X_WIDTH] == ROUTER_X[X_WIDTH-1:0] &&
                                  tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH - X_WIDTH -: Y_WIDTH] > ROUTER_Y[Y_WIDTH-1:0]) :
           p_idx == PORT_SOUTH ? (tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH -: X_WIDTH] == ROUTER_X[X_WIDTH-1:0] &&
                                  tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH - X_WIDTH -: Y_WIDTH] < ROUTER_Y[Y_WIDTH-1:0]) :
           p_idx == PORT_LOCAL ? (tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH -: X_WIDTH] == ROUTER_X[X_WIDTH-1:0] &&
                                  tx_data[p_idx][FLIT_WIDTH - 3 - VC_WIDTH - X_WIDTH -: Y_WIDTH] == ROUTER_Y[Y_WIDTH-1:0]) : 1'b0);
      endproperty
      assert_xy_routing: assert property (p_xy_routing)
        else $error("[SVA-RTE-01] XY dimension-order violation detected on output port %0d!", p_idx);
    end
  endgenerate

  //----------------------------------------------------------------------------
  // PROPERTY 5: Wormhole Packet Integrity (Atomic Channel Allocation)
  // No packet flit interleaving: HEAD must be followed by BODY/TAIL on same VC.
  //----------------------------------------------------------------------------
  generate
    for (p_idx = 0; p_idx < NUM_PORTS; p_idx++) begin : gen_wormhole_integrity
      logic in_packet;
      always_ff @(posedge clk_mesh or negedge rst_n_mesh) begin
        if (!rst_n_mesh) begin
          in_packet <= 1'b0;
        end else if (tx_valid[p_idx]) begin
          case (tx_data[p_idx][FLIT_WIDTH-1 -: 2])
            FLIT_HEAD:      in_packet <= 1'b1;
            FLIT_TAIL:      in_packet <= 1'b0;
            FLIT_HEAD_TAIL: in_packet <= 1'b0;
            FLIT_BODY:      in_packet <= in_packet;
            default: ;
          endcase
        end
      end

      property p_no_head_interleave;
        @(posedge clk_mesh) disable iff (!rst_n_mesh)
        (tx_valid[p_idx] && (tx_data[p_idx][FLIT_WIDTH-1 -: 2] == FLIT_HEAD)) |-> (!in_packet);
      endproperty
      assert_no_head_interleave: assert property (p_no_head_interleave)
        else $error("[SVA-WRM-01] New HEAD flit interleaved before previous TAIL flit at port %0d!", p_idx);

      property p_body_must_follow_head;
        @(posedge clk_mesh) disable iff (!rst_n_mesh)
        (tx_valid[p_idx] && (tx_data[p_idx][FLIT_WIDTH-1 -: 2] == FLIT_BODY)) |-> (in_packet);
      endproperty
      assert_body_must_follow_head: assert property (p_body_must_follow_head)
        else $error("[SVA-WRM-02] Orphan BODY flit transmitted without preceding HEAD at port %0d!", p_idx);
    end
  endgenerate

  //----------------------------------------------------------------------------
  // PROPERTY 6: Deadlock Freedom (Liveness / Forward Progress)
  // If downstream continues to return credits, any valid input flit must eventually pop.
  //----------------------------------------------------------------------------
  generate
    for (p_idx = 0; p_idx < NUM_PORTS; p_idx++) begin : gen_liveness
      for (v_idx = 0; v_idx < NUM_VCS; v_idx++) begin : gen_vc_liveness

        property p_forward_progress;
          @(posedge clk_mesh) disable iff (!rst_n_mesh)
          (vc_valid[p_idx][v_idx] && has_credit[p_idx][v_idx]) |->
            ##[1:32] (vc_pop[p_idx][v_idx]);
        endproperty
        assert_forward_progress: assert property (p_forward_progress)
          else $error("[SVA-LIV-01] Starvation / Deadlock: input port %0d VC %0d not granted within 32 cycles!", p_idx, v_idx);

      end
    end
  endgenerate

endmodule : formal_properties

`endif // FORMAL_PROPERTIES_SV
