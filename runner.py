from pathlib import Path

from cocotb_tools.runner import get_runner


def run_tb():
    sim = "verilator"
    waves = True

    parameters = {
    }

    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "rtl/newton_inv.sv"]
    sources += [proj_path / "rtl/dda.sv"]
    sources += [proj_path / "rtl/line_height_calc.sv"]
    sources += [proj_path / "rtl/raycast_top.sv"]
    includes = [proj_path / "rtl/include"]

    runner = get_runner(sim)

    runner.build(
        sources=sources,
        includes=includes,
        hdl_toplevel="raycast_top",
        parameters=parameters,
        waves=waves,
        build_args=["--timing", "--trace", "--trace-fst", "--trace-structs"]
        # build_args=["--timing"]
    )

    runner.test(
        hdl_toplevel="raycast_top",
        test_module="tb",
        parameters=parameters,
        waves=waves
    )


if __name__ == "__main__":
    run_tb()
