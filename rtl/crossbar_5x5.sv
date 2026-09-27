//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    crossbar_5x5.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Non-blocking 5x5 Crossbar Switch Matrix.
//              Routes flits from 5 input ports (Local, North, East, South, West)
//              to 5 output ports based on grant matrix from switch arbiters.
//==============================================================================

`ifndef CROSSBAR_5X5_SV
`define CROSSBAR_5X5_SV


module crossbar_5x5 #(
  parameter int DATA_WIDTH = noc_pkg::FLIT_WIDTH,
  parameter int NUM_PORTS  = noc_pkg::NUM_PORTS
) (
  input  logic                               clk,
  input  logic                               rst_n,

  // Input Ports Data and Valid
  input  logic [DATA_WIDTH-1:0]              in_data  [NUM_PORTS],
  input  logic [NUM_PORTS-1:0]               in_valid,

  // Grant Matrix [out_port][in_port]: 1 indicates in_port is forwarded to out_port
  input  logic [NUM_PORTS-1:0]               grant_matrix [NUM_PORTS],

  // Output Ports Data and Valid (Registered for high-speed timing closure)
  output logic [DATA_WIDTH-1:0]              out_data [NUM_PORTS],
  output logic [NUM_PORTS-1:0]               out_valid
);

  genvar out_p;
  generate
    for (out_p = 0; out_p < NUM_PORTS; out_p++) begin : gen_out_mux
      logic [DATA_WIDTH-1:0] mux_data;
      logic                  mux_valid;

      always_comb begin
        mux_data  = '0;
        mux_valid = 1'b0;
        for (int in_p = 0; in_p < NUM_PORTS; in_p++) begin
          if (grant_matrix[out_p][in_p]) begin
            mux_data  = in_data[in_p];
            mux_valid = in_valid[in_p];
          end
        end
      end

      // Registered Crossbar Output Stage
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          out_data[out_p]  <= '0;
          out_valid[out_p] <= 1'b0;
        end else begin
          out_data[out_p]  <= mux_data;
          out_valid[out_p] <= mux_valid;
        end
      end

    end
  endgenerate

endmodule : crossbar_5x5

`endif // CROSSBAR_5X5_SV
