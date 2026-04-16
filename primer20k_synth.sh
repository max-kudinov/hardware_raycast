#!/bin/bash


if ! yosys -m /home/mkudinov/contrib/yosys-slang/build/slang.so -p "read_slang                      \
                            --single-unit               \
                            --libraries-inherit-macros  \
                            -DPRIMER20K                 \
                            -DGOWIN                     \
                            -DVGA                       \
                            -Irtl/include               \
                            rtl/*                       \
                            rtl/dvi/*                   \
                            rtl/blackboxes/*;           \
                       synth_gowin                      \
                            -top primer20k_top          \
                            -json netlist.json"
then
    exit 1
fi

source ~/oss-cad-suite/environment

if ! nextpnr-himbaechel --json netlist.json           \
                        --write pnr.json              \
                        --device GW2A-LV18PG256C8/I7  \
                        --vopt family=GW2A-18         \
                        --vopt cst=primer20k/pins.cst \
                        --sdc primer20k/constraints.sdc
then
    exit 1
fi

if ! gowin_pack -d GW2A-18 -o bitstream.fs pnr.json
then
    exit 1
fi

if ! openFPGALoader -b tangprimer20k bitstream.fs
then
    exit 1
fi
