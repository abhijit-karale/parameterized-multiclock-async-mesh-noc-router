//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    round_robin_arbiter.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Fair, Starvation-Free Parameterized Round-Robin Arbiter.
//              Uses rotating priority mask with dual-vector single-cycle grant
//              logic to eliminate Head-of-Line blocking and guarantee bounded delay.
//==============================================================================

`ifndef ROUND_ROBIN_ARBITER_SV
`define ROUND_ROBIN_ARBITER_SV

module round_robin_arbiter #(
  parameter int NUM_REQS = 5
) (
  input  logic                    clk,
  input  logic                    rst_n,
  input  logic [NUM_REQS-1:0]     req,
  input  logic                    en,
  output logic [NUM_REQS-1:0]     grant,
  output logic                    grant_valid,
  output logic [$clog2(NUM_REQS)-1:0] grant_id
);

  localparam int ID_W = $clog2(NUM_REQS);

  // Rotating Priority Pointer
  logic [NUM_REQS-1:0] priority_mask;
  logic [NUM_REQS-1:0] masked_req;
  logic [NUM_REQS-1:0] raw_grant;
  logic [NUM_REQS-1:0] masked_grant;

  // Unmasked fixed priority (lower index has priority)
  assign raw_grant[0] = req[0];
  genvar i;
  generate
    for (i = 1; i < NUM_REQS; i++) begin : gen_raw_grant
      assign raw_grant[i] = req[i] & ~(|req[i-1:0]);
    end
  endgenerate

  // Masked request vector
  assign masked_req = req & priority_mask;

  // Masked fixed priority
  assign masked_grant[0] = masked_req[0];
  generate
    for (i = 1; i < NUM_REQS; i++) begin : gen_masked_grant
      assign masked_grant[i] = masked_req[i] & ~(|masked_req[i-1:0]);
    end
  endgenerate

  // If any masked request is granted, use masked_grant; otherwise wrap around to raw_grant
  always_comb begin
    if (|masked_req) begin
      grant = en ? masked_grant : '0;
    end else begin
      grant = en ? raw_grant : '0;
    end
  end

  assign grant_valid = |grant;

  // Binary Grant ID Encoder
  always_comb begin
    grant_id = '0;
    for (int j = 0; j < NUM_REQS; j++) begin
      if (grant[j]) begin
        grant_id = j[ID_W-1:0];
      end
    end
  end

  // Priority Mask Update: masks out requesters <= grant_id to favor requesters > grant_id
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // Default: request 0 has highest priority, so mask requests <= 0
      priority_mask <= ~NUM_REQS'(1);
    end else if (grant_valid) begin
      // Mask out all requesters <= grant_id
      priority_mask <= ~((NUM_REQS'(1) << (grant_id + 1'b1)) - 1'b1);
    end
  end

endmodule : round_robin_arbiter

`endif // ROUND_ROBIN_ARBITER_SV
