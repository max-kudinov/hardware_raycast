create_clock -name clk -period 37 [get_ports {clk_i}]
create_clock -name pixel_clk -period 39 [get_nets {pixel_clk}]
create_clock -name serial_clk -period 3.9 [get_nets {serial_clk}]
