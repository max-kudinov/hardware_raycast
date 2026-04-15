import pygame as pg
from pygame import freetype
from PIL import Image
import cocotb
from cocotb.types import LogicArray
from cocotb.triggers import RisingEdge
from cocotb.queue import Queue

from models import (
    float_model,
    controls_float,
    convert_state_to_float,
    column_calc_model,
    render_model,
    controls_model,
    get_model_state,
)

FRAME_WIDTH = int(cocotb.packages.dvi_pkg.FRAME_WIDTH.value)
FRAME_HEIGHT = int(cocotb.packages.dvi_pkg.FRAME_HEIGHT.value)

BG_TOP_HEX = int(cocotb.top.raycast_top.render.BG_TOP_COLOR.value)
BG_BOTTOM_HEX = int(cocotb.top.raycast_top.render.BG_BOTTOM_COLOR.value)

BG_TOP_COLOR = (
    (BG_TOP_HEX >> 16),
    (BG_TOP_HEX >> 8) & 255,
    BG_TOP_HEX & 255,
)

BG_BOTTOM_COLOR = (
    (BG_BOTTOM_HEX >> 16),
    (BG_BOTTOM_HEX >> 8) & 255,
    BG_BOTTOM_HEX & 255,
)

tex_pkg = cocotb.packages.tex_pkg

TEX_STEP_W_INT = int(tex_pkg.TEX_STEP_W_INT.value)
TEX_STEP_W_FRAC = int(tex_pkg.TEX_STEP_W_FRAC.value)
W_TEX_SIDE = int(tex_pkg.W_TEX_SIDE.value)
W_NUM_TEX = int(tex_pkg.W_NUM_TEX.value)
W_V_RES = int(cocotb.packages.dvi_pkg.W_V_RES.value)

TEX_STEP_END = TEX_STEP_W_INT + TEX_STEP_W_FRAC + W_V_RES - 2
TEX_X_END = TEX_STEP_END + W_TEX_SIDE
NUM_TEX_END = TEX_X_END + 2 + W_NUM_TEX - 1

tex_images = [
    "wall_vines3.png",
    "volcanic_wall0.png",
    "lair1.png",
    "relief3.png",
    "crystal_wall10.png",
    "brick_gray2.png",
    "lava3.png",
]

textures = list()
for image in tex_images:
    textures.append(Image.open(f"../textures/{image}").convert("RGB"))


async def dut_assert(expected, actual, var_name, x, y):
    try:
        assert expected == actual
    except AssertionError as e:
        print("=" * 80)
        print(f"X {x}")
        print(f"Y {y}")
        print(f"Expected {var_name}: {expected}, got {actual}")
        print("=" * 80)
        breakpoint()
        for _ in range(50):
            await RisingEdge(cocotb.top.px_clk)
        raise e


async def render_monitor(dut):
    render = dut.raycast_top.render

    while True:
        await RisingEdge(dut.px_clk)

        if render.valids.value[0]:
            px_x = int(render.px_x_i.value) - 1
            px_y = int(render.px_y_p0.value)
            texture = int(render.rd_texture.value)
            tex_shade = int(render.rd_tex_shade.value)
            tex_x = int(render.rd_tex_x.value)
            tex_step = int(render.rd_tex_step.value) / 2**TEX_STEP_W_FRAC
            tex_height = int(render.rd_tex_height.value)

            mon_queue.put_nowait(
                (px_x, px_y, texture, tex_shade, tex_x, tex_step, tex_height)
            )


def draw_background():
    pg.draw.rect(
        surface,
        BG_TOP_COLOR,
        (0, 0, FRAME_WIDTH, FRAME_HEIGHT // 2)
    )
    pg.draw.rect(
        surface,
        BG_BOTTOM_COLOR,
        (0, FRAME_HEIGHT // 2, FRAME_WIDTH, FRAME_HEIGHT // 2),
    )


async def render_scoreboard(dut):
    while True:
        await RisingEdge(dut.px_clk)

        if dut.raycast_top.dvi_top.visible_range_del.value:
            px_x, px_y, texture, tex_shade, tex_x, tex_step, tex_height = (
                await mon_queue.get()
            )
            px_color, in_texture = render_model(
                textures, px_y, texture, tex_shade, tex_x, tex_step, tex_height
            )

            if in_texture:
                surface.set_at((px_x, px_y), px_color)
                pg.display.update()

            red, green, blue = px_color
            render = dut.raycast_top.render
            dut_red = int(render.red_o.value)
            dut_green = int(render.green_o.value)
            dut_blue = int(render.blue_o.value)

            await dut_assert(red, dut_red, "red", px_x, px_y)
            await dut_assert(green, dut_green, "green", px_x, px_y)
            await dut_assert(blue, dut_blue, "blue", px_x, px_y)

        if (
            dut.raycast_top.frame_done.value
            and not dut.raycast_top.render.buf_toggle.value
        ):
            break


async def column_calc(dut, buf_toggle, check_dut):
    # Clear screen
    surface.fill((0, 0, 0))
    draw_background()

    if check_dut:
        await RisingEdge(dut.px_clk)
        await RisingEdge(dut.raycast_top.frame_done)
        mem = dut.raycast_top.render.frame_buffer.value
    else:
        mem = list()  # Just to suppress lint

    for x in range(FRAME_WIDTH):
        texture, tex_shade, tex_x, tex_step, tex_height = (
            column_calc_model(x, game_map)
        )

        if check_dut:
            column = (FRAME_WIDTH * buf_toggle) + x
            dut_texture = int(mem[column][NUM_TEX_END:TEX_X_END+2])
            dut_shade = int(mem[column][TEX_X_END+1])
            dut_tex_x = int(mem[column][TEX_X_END:TEX_STEP_END+1])
            dut_tex_step = (
                int(mem[column][TEX_STEP_END:W_V_RES-1]) / 2**TEX_STEP_W_FRAC
            )
            dut_height = int(mem[column][W_V_RES-2:0])

            await dut_assert(texture, dut_texture, "texture", x, 0)
            await dut_assert(tex_height, dut_height, "height", x, 0)
            await dut_assert(tex_shade, dut_shade, "shade", x, 0)
            await dut_assert(tex_x, dut_tex_x, "tex_x", x, 0)
            await dut_assert(tex_step, dut_tex_step, "tex_step", x, 0)

        for y in range(FRAME_HEIGHT):
            px_color, _ = render_model(
                textures, y, texture, tex_shade, tex_x, tex_step, tex_height
            )
            surface.set_at((x, y), px_color)

    print_info()
    pg.display.update()


def print_info():
    global time
    old_time = time
    time = pg.time.get_ticks()
    frame_time = (time - old_time) / 1000.0
    fps = 1 / frame_time

    green = (0, 255, 0)
    state_dict = get_model_state()
    y_position = 20
    font.render_to(surface, (20, y_position), f"FPS: {str(fps)}", green)
    for name, value in state_dict.items():
        y_position += 30
        font.render_to(surface, (20, y_position), f"{name}: {value}", green)


def handle_controls(dut):
    keys = pg.key.get_pressed()
    forward = backward = left = right = rotate_right = rotate_left = 0

    if keys[pg.K_w]:
        forward = 1
    if keys[pg.K_s]:
        backward = 1
    if keys[pg.K_a]:
        left = 1
    if keys[pg.K_d]:
        right = 1

    if keys[pg.K_RIGHT] and not keys[pg.K_LEFT]:
        rotate_right = 1

    if keys[pg.K_LEFT] and not keys[pg.K_RIGHT]:
        rotate_left = 1

    # Cocotb doesn't allow indexing of packed arrays, so yikes
    key_str = f"{rotate_right}{rotate_left}{right}{left}{backward}{forward}"
    dut.keys_inv_i.value = ~LogicArray(key_str)

    return (forward, backward, left, right, rotate_right, rotate_left)


def check_for_quit():
    quit_sim = False

    for event in pg.event.get():
        if event.type == pg.QUIT:
            quit_sim = True

        elif event.type == pg.KEYDOWN:
            if event.key == pg.K_q:
                quit_sim = True

    if quit_sim:
        pg.quit()
        cocotb.pass_test("Quit action")


async def dut_reset(dut):
    dut.rst_n.value = 0
    await RisingEdge(dut.px_clk)
    dut.rst_n.value = 1


async def setup(dut):
    global game_map, font, surface, mon_queue, time
    cocotb.start_soon(dut_reset(dut))

    # Pygame init
    pg.init()
    font = freetype.Font(None, 20)
    surface = pg.display.set_mode((FRAME_WIDTH, FRAME_HEIGHT))

    mon_queue = Queue()
    time = 0

    await RisingEdge(dut.px_clk)
    game_map = cocotb.top.raycast_top.map.value


@cocotb.test()
async def float_raycast(dut):
    await setup(dut)
    convert_state_to_float()

    while True:
        draw_background()
        check_for_quit()
        controls_float(*handle_controls(dut), game_map)
        float_model(game_map, textures, surface)
        print_info()
        pg.display.update()


@cocotb.test()
async def fixp_model(dut):
    await setup(dut)

    buf_toggle = 1
    while True:
        check_for_quit()
        controls_model(*handle_controls(dut), game_map)
        await column_calc(dut, buf_toggle, False)
        buf_toggle = buf_toggle ^ 1


@cocotb.test()
async def check_column_calc(dut):
    await setup(dut)

    buf_toggle = 1
    while True:
        check_for_quit()
        controls_model(*handle_controls(dut), game_map)
        await column_calc(dut, buf_toggle, True)
        buf_toggle = buf_toggle ^ 1


@cocotb.test()
async def check_render(dut):
    await setup(dut)
    draw_background()

    cocotb.start_soon(render_monitor(dut))
    await render_scoreboard(dut)
    pg.quit()
