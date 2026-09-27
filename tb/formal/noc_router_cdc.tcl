#===============================================================================
# Project: Parameterized Multi-Clock Asynchronous Mesh NoC Router
# File:    noc_router_cdc.tcl
# Author:  Abhijit Karale
# Tech:    SkyWater 130nm
# Tool:    Cadence JasperGold CDC & Formal Property Verification
#===============================================================================

# Clear existing database
clear -all

# 1. Read Design Files
analyze -sv \
  rtl/noc_pkg.sv \
  rtl/cdc_reset_sync.sv \
  rtl/cdc_2ff_sync.sv \
  rtl/cdc_gray_sync.sv \
  rtl/cdc_pulse_sync.sv \
  rtl/async_fifo.sv \
  rtl/async_vc_fifo.sv \
  rtl/xy_router.sv \
  rtl/round_robin_arbiter.sv \
  rtl/crossbar_5x5.sv \
  rtl/credit_manager.sv \
  rtl/vc_allocator.sv \
  rtl/noc_router_top.sv \
  tb/formal/formal_properties.sv

# Elaborate Top Level with Verification Wrapper
elaborate -top noc_router_top

# 2. Clock Domain Crossing (CDC) Setup
# Local PE clock: 150 MHz (period 6.667 ns)
clock rx_clk[0] -period 6.667 -waveform {0.000 3.333} -domain DOMAIN_CORE_150MHZ

# Mesh Router Core Clock: 250 MHz (period 4.000 ns)
clock clk_mesh -period 4.000 -waveform {0.000 2.000} -domain DOMAIN_MESH_250MHZ

# North, East, South, West Link Clocks: 250 MHz (Mesochronous / Asynchronous)
clock rx_clk[1] -period 4.000 -waveform {0.000 2.000} -domain DOMAIN_NORTH
clock rx_clk[2] -period 4.000 -waveform {0.500 2.500} -domain DOMAIN_EAST
clock rx_clk[3] -period 4.000 -waveform {1.000 3.000} -domain DOMAIN_SOUTH
clock rx_clk[4] -period 4.000 -waveform {1.500 3.500} -domain DOMAIN_WEST

clock credit_in_clk[0] -period 6.667 -domain DOMAIN_CORE_150MHZ
clock credit_in_clk[1] -period 4.000 -domain DOMAIN_NORTH
clock credit_in_clk[2] -period 4.000 -domain DOMAIN_EAST
clock credit_in_clk[3] -period 4.000 -domain DOMAIN_SOUTH
clock credit_in_clk[4] -period 4.000 -domain DOMAIN_WEST

# 3. Reset Specifications
reset -expression {!rst_n_mesh}
reset -expression {!rx_rst_n[0]}
reset -expression {!rx_rst_n[1]}
reset -expression {!rx_rst_n[2]}
reset -expression {!rx_rst_n[3]}
reset -expression {!rx_rst_n[4]}

# 4. CDC Protocol and Synchronization Rules
# Recognize 2-FF multi-stage synchronizers
cdc preference -sync_cell cdc_2ff_sync
cdc preference -sync_cell cdc_reset_sync
cdc preference -sync_cell cdc_gray_sync
cdc preference -sync_cell cdc_pulse_sync

# Constrain Gray Code Bus CDC Skew: Max skew must not exceed 0.7 * T_dest
cdc skew -max_delay 2.8 -from {*wptr_gray*} -to {*rq2_wptr_gray*}
cdc skew -max_delay 2.8 -from {*rptr_gray*} -to {*wq2_rptr_gray*}

# Check CDC Structural Rules
cdc run -structural

# 5. Formal Property Verification (SVA)
# Bind formal assertions to top level
bind noc_router_top formal_properties #(
  .ROUTER_X   (0),
  .ROUTER_Y   (0),
  .NUM_PORTS  (5),
  .NUM_VCS    (2),
  .FIFO_DEPTH (8)
) u_formal_props (
  .clk_mesh       (clk_mesh),
  .rst_n_mesh     (rst_n_mesh),
  .rx_clk         (rx_clk),
  .rx_rst_n       (rx_rst_n),
  .rx_valid       (rx_valid),
  .rx_data        (rx_data),
  .credit_out     (credit_out),
  .tx_clk         (tx_clk),
  .tx_rst_n       (tx_rst_n),
  .tx_valid       (tx_valid),
  .tx_data        (tx_data),
  .credit_in      (credit_in),
  .vc_valid       (u_vc_allocator.in_valid),
  .vc_pop         (u_vc_allocator.in_pop),
  .has_credit     (u_vc_allocator.has_credit),
  .crossbar_grant (u_vc_allocator.crossbar_grant)
);

# Prove all assertions (Credit conservation, deadlock freedom, Gray Hamming distance)
assert -all
prove -all -time_limit 600s
report -summary
