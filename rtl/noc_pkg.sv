//==============================================================================
// Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
// File:    noc_pkg.sv
// Author:  Abhijit Karale
// Tech:    SkyWater 130nm (Independent Core @ 150MHz, Mesh @ 250MHz)
// Description: Global NoC package defining architectural parameters, types,
//              flit formats, port encodings, and utility functions.
//==============================================================================

`ifndef NOC_PKG_SV
`define NOC_PKG_SV

package noc_pkg;

  //----------------------------------------------------------------------------
  // Architectural Parameters
  //----------------------------------------------------------------------------
  localparam int NUM_PORTS        = 5;   // Local, North, East, South, West
  localparam int DEFAULT_NUM_VCS  = 2;   // Virtual Channels per physical port
  localparam int DEFAULT_VC_WIDTH = 1;   // $clog2(DEFAULT_NUM_VCS)
  localparam int DEFAULT_X_WIDTH  = 3;   // Supports up to 8x8 Mesh
  localparam int DEFAULT_Y_WIDTH  = 3;
  localparam int DEFAULT_PKT_ID_W = 8;
  localparam int DEFAULT_DATA_W   = 32;  // Flit payload data width
  localparam int DEFAULT_FIFO_DEP = 8;   // Depth of each VC FIFO (credits)

  //----------------------------------------------------------------------------
  // Physical Port Enumeration
  //----------------------------------------------------------------------------
  typedef enum logic [2:0] {
    PORT_LOCAL = 3'd0,
    PORT_NORTH = 3'd1,
    PORT_EAST  = 3'd2,
    PORT_SOUTH = 3'd3,
    PORT_WEST  = 3'd4,
    PORT_NONE  = 3'd7
  } port_id_t;

  //----------------------------------------------------------------------------
  // Flit Type Classification
  //----------------------------------------------------------------------------
  typedef enum logic [1:0] {
    FLIT_BODY      = 2'b00,  // Intermediate payload flit
    FLIT_HEAD      = 2'b01,  // Routing and setup flit
    FLIT_TAIL      = 2'b10,  // Final payload flit, releases VC
    FLIT_HEAD_TAIL = 2'b11   // Single-flit atomic packet
  } flit_type_t;

  //----------------------------------------------------------------------------
  // Virtual Channel Allocator States
  //----------------------------------------------------------------------------
  typedef enum logic [2:0] {
    VC_STATE_IDLE       = 3'd0,
    VC_STATE_ROUTING    = 3'd1,
    VC_STATE_WAIT_ALLOC = 3'd2,
    VC_STATE_ACTIVE     = 3'd3,
    VC_STATE_DRAIN_TAIL = 3'd4
  } vc_state_t;

  //----------------------------------------------------------------------------
  // Standard Flit Structure
  // Parameterized for X_WIDTH=3, Y_WIDTH=3, VC_WIDTH=1, PKT_ID_W=8, DATA_W=32
  // Total Width = 2 + 1 + 3 + 3 + 3 + 3 + 8 + 32 = 55 bits
  //----------------------------------------------------------------------------
  localparam int FLIT_WIDTH = 2 + DEFAULT_VC_WIDTH + (2 * DEFAULT_X_WIDTH) + 
                              (2 * DEFAULT_Y_WIDTH) + DEFAULT_PKT_ID_W + DEFAULT_DATA_W;

  typedef struct packed {
    logic [1:0]                        flit_type; // flit_type_t
    logic [DEFAULT_VC_WIDTH-1:0]       vc_id;
    logic [DEFAULT_X_WIDTH-1:0]        dest_x;
    logic [DEFAULT_Y_WIDTH-1:0]        dest_y;
    logic [DEFAULT_X_WIDTH-1:0]        src_x;
    logic [DEFAULT_Y_WIDTH-1:0]        src_y;
    logic [DEFAULT_PKT_ID_W-1:0]       pkt_id;
    logic [DEFAULT_DATA_W-1:0]         payload;
  } flit_t;

  //----------------------------------------------------------------------------
  // Gray Code Conversion Utility Functions
  //----------------------------------------------------------------------------
  function automatic logic [7:0] bin2gray(input logic [7:0] bin);
    return bin ^ (bin >> 1);
  endfunction

  function automatic logic [7:0] gray2bin(input logic [7:0] gray);
    logic [7:0] bin;
    bin[7] = gray[7];
    for (int i = 6; i >= 0; i--) begin
      bin[i] = bin[i+1] ^ gray[i];
    end
    return bin;
  endfunction

  //----------------------------------------------------------------------------
  // Helper: Port Name String Representation
  //----------------------------------------------------------------------------
  function automatic string port2string(input port_id_t port);
    case (port)
      PORT_LOCAL: return "LOCAL";
      PORT_NORTH: return "NORTH";
      PORT_EAST:  return "EAST";
      PORT_SOUTH: return "SOUTH";
      PORT_WEST:  return "WEST";
      default:    return "UNKNOWN";
    endcase
  endfunction

  //----------------------------------------------------------------------------
  // Helper: Flit Type String Representation
  //----------------------------------------------------------------------------
  function automatic string flit_type2string(input logic [1:0] ftype);
    case (ftype)
      FLIT_BODY:      return "BODY";
      FLIT_HEAD:      return "HEAD";
      FLIT_TAIL:      return "TAIL";
      FLIT_HEAD_TAIL: return "HEAD_TAIL";
      default:        return "INVALID";
    endcase
  endfunction

endpackage : noc_pkg

`endif // NOC_PKG_SV
