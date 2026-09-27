//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    vc_allocator.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Combined Virtual Channel and Switch Allocator (VA/SA).
//              Enforces wormhole atomic packet locking, round-robin output
//              arbitration, credit awareness, and route holding across flits.
//==============================================================================

`ifndef VC_ALLOCATOR_SV
`define VC_ALLOCATOR_SV


module vc_allocator #(
  parameter int NUM_PORTS  = noc_pkg::NUM_PORTS,
  parameter int NUM_VCS    = noc_pkg::DEFAULT_NUM_VCS,
  parameter int ROUTER_X   = 0,
  parameter int ROUTER_Y   = 0,
  parameter int X_WIDTH    = noc_pkg::DEFAULT_X_WIDTH,
  parameter int Y_WIDTH    = noc_pkg::DEFAULT_Y_WIDTH,
  parameter int FLIT_WIDTH = noc_pkg::FLIT_WIDTH
) (
  input  logic                                  clk,
  input  logic                                  rst_n,

  // Input Ports Flit Status (from input async VC FIFOs)
  input  logic [NUM_VCS-1:0]                    in_valid   [NUM_PORTS],
  input  logic [FLIT_WIDTH-1:0]                 in_flit    [NUM_PORTS][NUM_VCS],
  output logic [NUM_VCS-1:0]                    in_pop     [NUM_PORTS],

  // Downstream Credit Availability per Output Port and VC
  input  logic [NUM_VCS-1:0]                    has_credit [NUM_PORTS],

  // Crossbar Control
  output logic [NUM_PORTS-1:0]                  crossbar_grant [NUM_PORTS], // [out_p][in_p]
  output logic [NUM_PORTS-1:0]                  out_tx_fire,
  output logic [$clog2(NUM_VCS)-1:0]            out_tx_vc      [NUM_PORTS],
  output logic [$clog2(NUM_PORTS)-1:0]          out_sel_port   [NUM_PORTS]
);

  import noc_pkg::*;

  localparam int VC_W   = $clog2(NUM_VCS);
  localparam int PORT_W = $clog2(NUM_PORTS);

  // Per Input Port and VC Tracking State
  typedef enum logic [1:0] {
    ST_IDLE   = 2'b00,
    ST_ACTIVE = 2'b01  // Channel locked by active packet
  } ch_state_t;

  ch_state_t                   state       [NUM_PORTS][NUM_VCS];
  port_id_t                    locked_port [NUM_PORTS][NUM_VCS];

  // Route Computation instances for each input port and VC
  port_id_t                    computed_port [NUM_PORTS][NUM_VCS];

  genvar p, v;
  generate
    for (p = 0; p < NUM_PORTS; p++) begin : gen_rc_p
      for (v = 0; v < NUM_VCS; v++) begin : gen_rc_v
        flit_t f;
        assign f = in_flit[p][v];

        xy_router #(
          .ROUTER_X (ROUTER_X),
          .ROUTER_Y (ROUTER_Y),
          .X_WIDTH  (X_WIDTH),
          .Y_WIDTH  (Y_WIDTH)
        ) u_xy_router (
          .dest_x          (f.dest_x),
          .dest_y          (f.dest_y),
          .out_port        (computed_port[p][v]),
          .out_port_onehot ()
        );
      end
    end
  endgenerate

  // Effective Target Output Port for each Input Channel
  port_id_t target_port [NUM_PORTS][NUM_VCS];
  always_comb begin
    for (int ip = 0; ip < NUM_PORTS; ip++) begin
      for (int iv = 0; iv < NUM_VCS; iv++) begin
        if (state[ip][iv] == ST_ACTIVE) begin
          target_port[ip][iv] = locked_port[ip][iv];
        end else begin
          target_port[ip][iv] = computed_port[ip][iv];
        end
      end
    end
  end

  // Switch Allocation Request Matrix: [out_port][in_port]
  // An input port requests an output port if any of its VCs requests it and has downstream credit
  logic [NUM_PORTS-1:0] sa_req [NUM_PORTS]; // [out_p][in_p]
  logic [VC_W-1:0]      sa_req_vc [NUM_PORTS][NUM_PORTS]; // VC making request

  always_comb begin
    for (int op = 0; op < NUM_PORTS; op++) begin
      for (int ip = 0; ip < NUM_PORTS; ip++) begin
        sa_req[op][ip]    = 1'b0;
        sa_req_vc[op][ip] = '0;
        for (int iv = 0; iv < NUM_VCS; iv++) begin
          if (in_valid[ip][iv] && (target_port[ip][iv] == port_id_t'(op))) begin
            // Check if target downstream VC has credit
            if (has_credit[op][iv]) begin
              sa_req[op][ip]    = 1'b1;
              sa_req_vc[op][ip] = iv[VC_W-1:0];
              break; // VC priority within port
            end
          end
        end
      end
    end
  end

  // 5 Independent Round-Robin Arbiters, one for each output port
  logic [NUM_PORTS-1:0] arb_grant       [NUM_PORTS]; // [out_p][in_p]
  logic                 arb_grant_valid [NUM_PORTS];
  logic [PORT_W-1:0]    arb_grant_id    [NUM_PORTS];

  generate
    for (p = 0; p < NUM_PORTS; p++) begin : gen_arb
      round_robin_arbiter #(
        .NUM_REQS (NUM_PORTS)
      ) u_arbiter (
        .clk         (clk),
        .rst_n       (rst_n),
        .req         (sa_req[p]),
        .en          (1'b1),
        .grant       (arb_grant[p]),
        .grant_valid (arb_grant_valid[p]),
        .grant_id    (arb_grant_id[p])
      );
    end
  endgenerate

  // Assign crossbar grants and outputs
  always_comb begin
    for (int op = 0; op < NUM_PORTS; op++) begin
      crossbar_grant[op] = arb_grant[op];
      out_tx_fire[op]    = arb_grant_valid[op];
      out_sel_port[op]   = arb_grant_id[op];
      if (arb_grant_valid[op]) begin
        out_tx_vc[op]    = sa_req_vc[op][arb_grant_id[op]];
      end else begin
        out_tx_vc[op]    = '0;
      end
    end
  end

  // Generate FIFO pop signals for winning input channels
  always_comb begin
    for (int ip = 0; ip < NUM_PORTS; ip++) begin
      for (int iv = 0; iv < NUM_VCS; iv++) begin
        in_pop[ip][iv] = 1'b0;
        for (int op = 0; op < NUM_PORTS; op++) begin
          if (arb_grant[op][ip] && (sa_req_vc[op][ip] == iv[VC_W-1:0])) begin
            in_pop[ip][iv] = 1'b1;
          end
        end
      end
    end
  end

  // Channel State FSM (Wormhole atomic lock management)
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int ip = 0; ip < NUM_PORTS; ip++) begin
        for (int iv = 0; iv < NUM_VCS; iv++) begin
          state[ip][iv]       <= ST_IDLE;
          locked_port[ip][iv] <= PORT_LOCAL;
        end
      end
    end else begin
      for (int ip = 0; ip < NUM_PORTS; ip++) begin
        for (int iv = 0; iv < NUM_VCS; iv++) begin
          if (in_pop[ip][iv]) begin
            flit_t f;
            f = in_flit[ip][iv];
            case (f.flit_type)
              FLIT_HEAD: begin
                // Lock the output port for this packet
                state[ip][iv]       <= ST_ACTIVE;
                locked_port[ip][iv] <= target_port[ip][iv];
              end
              FLIT_TAIL, FLIT_HEAD_TAIL: begin
                // Packet finished, release channel lock
                state[ip][iv]       <= ST_IDLE;
              end
              FLIT_BODY: begin
                // Continue active transfer
                state[ip][iv]       <= ST_ACTIVE;
              end
              default: ;
            endcase
          end
        end
      end
    end
  end

endmodule : vc_allocator

`endif // VC_ALLOCATOR_SV
