create_clock -name clk -period 37 [get_ports {clk}]
create_clock -name px_clk -period 39 [get_nets {px_clk}]
create_clock -name serial_clk -period 3.9 [get_nets {serial_clk}]
