//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    xy_router.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm
// Description: Dimension-Order Deterministic XY Routing Engine.
//              Routes first along X-axis (East/West) then Y-axis (North/South)
//              terminating at Local PE. Provably deadlock-free for 2D meshes.
//==============================================================================

`ifndef XY_ROUTER_SV
`define XY_ROUTER_SV


module xy_router #(
  parameter int ROUTER_X = 0,
  parameter int ROUTER_Y = 0,
  parameter int X_WIDTH  = noc_pkg::DEFAULT_X_WIDTH,
  parameter int Y_WIDTH  = noc_pkg::DEFAULT_Y_WIDTH
) (
  input  logic [X_WIDTH-1:0]        dest_x,
  input  logic [Y_WIDTH-1:0]        dest_y,
  output noc_pkg::port_id_t         out_port,
  output logic [noc_pkg::NUM_PORTS-1:0] out_port_onehot
);

  import noc_pkg::*;

  always_comb begin
    // Dimension-Order XY Routing Decision
    if (dest_x > ROUTER_X[X_WIDTH-1:0]) begin
      out_port = PORT_EAST;
    end else if (dest_x < ROUTER_X[X_WIDTH-1:0]) begin
      out_port = PORT_WEST;
    end else begin
      // X coordinate reached; route along Y axis
      if (dest_y > ROUTER_Y[Y_WIDTH-1:0]) begin
        out_port = PORT_NORTH;
      end else if (dest_y < ROUTER_Y[Y_WIDTH-1:0]) begin
        out_port = PORT_SOUTH;
      end else begin
        // Both coordinates match router location: inject to Local PE
        out_port = PORT_LOCAL;
      end
    end

    // Decode to one-hot request vector for crossbar arbitration
    out_port_onehot = '0;
    case (out_port)
      PORT_LOCAL: out_port_onehot[PORT_LOCAL] = 1'b1;
      PORT_NORTH: out_port_onehot[PORT_NORTH] = 1'b1;
      PORT_EAST:  out_port_onehot[PORT_EAST]  = 1'b1;
      PORT_SOUTH: out_port_onehot[PORT_SOUTH] = 1'b1;
      PORT_WEST:  out_port_onehot[PORT_WEST]  = 1'b1;
      default:    out_port_onehot = '0;
    endcase
  end

endmodule : xy_router

`endif // XY_ROUTER_SV
