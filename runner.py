import sys
from pathlib import Path

from cocotb_tools.runner import get_runner


def run_tb():
    sim = "verilator"
    waves = True
    hdl_toplevel = "primer20k_top"

    parameters = {
        "MOVEMENT_SPEED": 0.8,
        "ROTATION_SPEED": 0.4
    }

    proj_path = Path(__file__).resolve().parent
    tb_path = str(proj_path) + "/tb"
    sys.path.append(tb_path)

    sources = [proj_path / "rtl/newton_inv.sv"]
    sources += [proj_path / "rtl/dda.sv"]
    sources += [proj_path / "rtl/column_calc.sv"]
    sources += [proj_path / "rtl/raycast_top.sv"]
    sources += [proj_path / "rtl/render.sv"]
    sources += [proj_path / "rtl/dvi/dvi_top.sv"]
    sources += [proj_path / "rtl/dvi/delay.sv"]
    sources += [proj_path / "rtl/dvi/ds_buf.sv"]
    sources += [proj_path / "rtl/dvi/dvi_sync.sv"]
    sources += [proj_path / "rtl/dvi/serializer.sv"]
    sources += [proj_path / "rtl/dvi/tmds_encoder.sv"]
    sources += [proj_path / "rtl/controls.sv"]
    sources += [proj_path / "rtl/position.sv"]
    sources += [proj_path / "rtl/rotation.sv"]
    sources += [proj_path / "rtl/primer20k_top.sv"]
    includes = [proj_path / "rtl/include"]
    includes += [proj_path / "rtl/open_dvi/rtl/include"]

    runner = get_runner(sim)

    runner.build(
        sources=sources,
        includes=includes,
        hdl_toplevel=hdl_toplevel,
        parameters=parameters,
        waves=waves,
        build_args=[
            "-DSIMULATION",
            "-Wno-CASEINCOMPLETE",
            "--timing",
            "--trace",
            "--trace-fst",
            "--trace-structs"
        ]
    )

    runner.test(
        hdl_toplevel=hdl_toplevel,
        test_module="tb.testbench",
        parameters=parameters,
        waves=waves,
        test_filter="check_column_calc"
    )


if __name__ == "__main__":
    run_tb()
