//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    credit_manager.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Credit-Based Flow Control Manager per Output Port.
//              Tracks downstream buffer availability across Virtual Channels.
//              Guarantees zero packet drops by enforcing hardware backpressure.
//==============================================================================

`ifndef CREDIT_MANAGER_SV
`define CREDIT_MANAGER_SV


module credit_manager #(
  parameter int NUM_VCS         = noc_pkg::DEFAULT_NUM_VCS,
  parameter int INITIAL_CREDITS = noc_pkg::DEFAULT_FIFO_DEP,
  parameter int CREDIT_WIDTH    = $clog2(INITIAL_CREDITS + 1)
) (
  input  logic                    clk,
  input  logic                    rst_n,

  // Credit inputs from downstream router/PE (synchronized into clk domain)
  input  logic [NUM_VCS-1:0]      credit_in,

  // Transmission events from router crossbar
  input  logic                    tx_fire,
  input  logic [$clog2(NUM_VCS)-1:0] tx_vc_id,

  // Credit status to switch allocator
  output logic [NUM_VCS-1:0]      has_credit,
  output logic [CREDIT_WIDTH-1:0] credit_count [NUM_VCS]
);

  logic [CREDIT_WIDTH-1:0] credits [NUM_VCS];

  genvar v;
  generate
    for (v = 0; v < NUM_VCS; v++) begin : gen_vc_credits
      assign has_credit[v]   = (credits[v] > '0);
      assign credit_count[v] = credits[v];

      logic flit_consumed;
      assign flit_consumed = tx_fire && (tx_vc_id == v[$clog2(NUM_VCS)-1:0]);

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          credits[v] <= INITIAL_CREDITS[CREDIT_WIDTH-1:0];
        end else begin
          case ({credit_in[v], flit_consumed})
            2'b10: begin
              // Credit returned, no flit transmitted -> increment credit
              if (credits[v] < INITIAL_CREDITS[CREDIT_WIDTH-1:0]) begin
                credits[v] <= credits[v] + 1'b1;
              end
            end
            2'b01: begin
              // Flit transmitted, no credit returned -> decrement credit
              if (credits[v] > '0) begin
                credits[v] <= credits[v] - 1'b1;
              end
            end
            2'b11: begin
              // Simultaneous transmit and credit return -> credit count unchanged
              credits[v] <= credits[v];
            end
            default: begin
              credits[v] <= credits[v];
            end
          endcase
        end
      end

    end
  endgenerate

endmodule : credit_manager

`endif // CREDIT_MANAGER_SV
