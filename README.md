# Hardware raycaster

Raycasting algorithm inspired by Wolfenstein 3D, implemented in SystemVerilog
and optimized for low hardware resource utilization through FSM resource sharing
and optimal fixed point widths.

See [walkthrough](docs/contents.md) for implementation details.

## Features

Supports multiple different wall textures with a script to convert `.png` to
hex ROM file that is read by `$readmemh`.

Map edit through separate file `memfiles/map.mem`.

Double buffering to prevent screen tearing.

Simulation environment with self-checking testbench is provided with graphical
window and keyboard controls in 4 modes:

* Floating point model (no DUT checks)
* Fixed point model (no DUT checks)
* Check column data prior to frame buffer write
* Check pixel value after final rendering pipeline

Fully developed using open-source tools,
[Verilator](https://github.com/verilator/verilator) +
[Cocotb](https://www.cocotb.org/)
for simulation, [Yosys](https://yosyshq.net/yosys/) +
[yosys-slang](https://github.com/povik/yosys-slang) +
[nextpnr](https://github.com/YosysHQ/nextpnr) +
[Apicula](https://github.com/YosysHQ/apicula)
for FPGA synthesis.

## How to run

### Simulation

Requirements: `python3`, `verilator`

To install required python libraries, run from repo root directory:

```Bash
python3 -m venv raycast
source raycast/bin/activate
pip install cocotb pytest pygame fpbinary Pillow
```

To run simulation: `python3 runner.py`. By default, rendering check is executed
on 1 frame (VERY slow!).

Additional options:

* `--float` - floating point model, relatively fast (3-6 FPS)
* `--fixp_model` - fixed point model without checks (slow, but bearable)
* `--fixp_model_check` - fixed point model with column data checks (slow)

### Synthesis

Currently only Gowin tang primer 20k is supported. Just run `primer20k_synth.sh`.
The script assumes that you installed the toolchain through
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build). If that's not
the case, then just delete `source ~/oss-cad-suite/environment` and make sure
the executables are in the `$PATH`. I recommend OSS CAD Suite though, make sure
you place `oss-cad-suite` in your user home directory.

## Texture art

All the graphic tiles used in this program is the public
domain roguelike tileset "RLTiles".

You can find the original tileset at:
[https://opengameart.org/content/dungeon-crawl-32x32-tiles] and
[https://rltiles.sourceforge.net/].

Huge thanks to all the artists for signing off their copyrights on the tiles,
thus making it possible for me to freely use them.

## Similar projects

* [raybox](https://github.com/algofoogle/raybox)
* [verilog-raycaster](https://github.com/dylan-dang/verilog-raycaster)
