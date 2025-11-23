from pathlib import Path

from cocotb_tools.runner import get_runner


def run_tb():
    sim = "verilator"
    proj_path = Path(__file__).resolve().parent
    sources = [proj_path / "rtl/newton_inv.sv"]

    runner = get_runner(sim)

    runner.build(
        sources=sources,
        hdl_toplevel="newton_inv"
    )

    runner.test(
        hdl_toplevel="newton_inv",
        test_module="tb"
    )


if __name__ == "__main__":
    run_tb()
