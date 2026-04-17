#!/bin/bash


if ! yosys -m ~/build/yosys-slang/build/slang.so -p "read_slang                      \
                            --single-unit               \
                            --libraries-inherit-macros  \
                            -DPRIMER20K                 \
                            -DGOWIN                     \
                            -DVGA                       \
                            -Irtl/include               \
                            rtl/*                       \
                            rtl/dvi/*                   \
                            rtl/blackboxes/*;           \
                       script coarse.ys;                \
                       synth_gowin -run map_ram:        \
                            -family gw5a                \
                            -top primer20k_top          \
                            -json netlist.json; write_verilog netlist.v"
then
    exit 1
fi

# source ~/Downloads/oss-cad-suite/environment
#
# if ! nextpnr-himbaechel --json netlist.json           \
#                         --write pnr.json              \
#                         --device GW2A-LV18PG256C8/I7  \
#                         --vopt family=GW2A-18         \
#                         --vopt cst=primer20k/pins.cst \
#                         --timing-allow-fail           \
#                         --sdc primer20k/constraints.sdc
# then
#     exit 1
# fi
#
# if ! gowin_pack -d GW2A-18 -o bitstream.fs pnr.json
# then
#     exit 1
# fi
#
# if ! openFPGALoader -b tangprimer20k bitstream.fs
# then
#     exit 1
# fi
