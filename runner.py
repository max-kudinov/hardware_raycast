from pathlib import Path

from cocotb_tools.runner import get_runner


def run_tb():
    sim = "verilator"

    parameters = {
    }

    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "rtl/newton_inv.sv"]
    includes = [proj_path / "rtl/include"]

    runner = get_runner(sim)

    runner.build(
        sources=sources,
        includes=includes,
        hdl_toplevel="newton_inv",
        parameters=parameters
    )

    runner.test(
        hdl_toplevel="newton_inv",
        test_module="tb",
        parameters=parameters
    )


if __name__ == "__main__":
    run_tb()
