interface vga_if;

    logic       vsync;
    logic       hsync;

    // 4 bits per channel in VGA PMOD
    logic [3:0] red;
    logic [3:0] green;
    logic [3:0] blue;

endinterface : vga_if
