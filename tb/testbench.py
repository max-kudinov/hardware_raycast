import math
import pygame as pg
from pygame import freetype
from PIL import Image
import cocotb
from cocotb.types import LogicArray
from cocotb.triggers import RisingEdge
from cocotb.queue import Queue

from fixedpoint import (
    get_type_spec,
    fixp_init,
    fixp_expr,
    fixp_unsigned,
    fixp_cast,
)

dvi_pkg = cocotb.packages.dvi_pkg
fixp_pkg = cocotb.packages.fixp_pkg
tex_pkg = cocotb.packages.tex_pkg

FRAME_WIDTH = int(dvi_pkg.FRAME_WIDTH.value)
FRAME_HEIGHT = int(dvi_pkg.FRAME_HEIGHT.value)
W_HEIGHT = int(dvi_pkg.W_V_RES.value)
TEX_SIDE = int(tex_pkg.TEX_SIDE.value)
MOVEMENT_SPEED = float(cocotb.top.MOVEMENT_SPEED.value)
ROTATION_SPEED = float(cocotb.top.ROTATION_SPEED.value)
INV_ITER_NUM = int(fixp_pkg.INV_ITER_NUM.value)

# fixp_pkg types
fixp_ray = get_type_spec(fixp_pkg, "RAY")
fixp_pos = get_type_spec(fixp_pkg, "POS")
fixp_ext_pos = get_type_spec(fixp_pkg, "EXT_POS")
fixp_inv_dist = get_type_spec(fixp_pkg, "INV_DIST")
fixp_inv = get_type_spec(fixp_pkg, "INV")

# tex_pkg types
fixp_tex_zoom = get_type_spec(tex_pkg, "TEX_ZOOM")
fixp_tex_step = get_type_spec(tex_pkg, "TEX_STEP")

# Pygame init
pg.init()
font = freetype.Font(None, 20)
surface = pg.display.set_mode((FRAME_WIDTH, FRAME_HEIGHT))

game_map = list()
mon_queue = Queue()
time = 0

PLANE_COEFF = float(cocotb.top.raycast_top.controls.rotation.PLANE_COEFF.value)
FIXP_MULT_COEFF = fixp_init(PLANE_COEFF, fixp_ray, True)

move_speed = fixp_init(MOVEMENT_SPEED, fixp_ray, True)
cos_angle = fixp_init(math.cos(ROTATION_SPEED), fixp_ray, True)
sin_angle = fixp_init(math.sin(ROTATION_SPEED), fixp_ray, True)
cos_neg_angle = fixp_init(math.cos(-ROTATION_SPEED), fixp_ray, True)
sin_neg_angle = fixp_init(math.sin(-ROTATION_SPEED), fixp_ray, True)

max_dist = fixp_init(2 ** fixp_ext_pos[0] - 1, fixp_ext_pos)
pos_max = fixp_init(2 ** fixp_pos[0] - 1, fixp_pos)

step = 2.0 / FRAME_WIDTH * 2**fixp_ray[1]
tex_step_scale = fixp_init(TEX_SIDE / FRAME_HEIGHT, fixp_tex_step)

# Mimic rounding of int cast in SystemVerilog
if step < 0.5:
    ray_step = fixp_init(0, fixp_ray)
else:
    ray_step = fixp_init(round(step), fixp_ray)

controls = cocotb.top.raycast_top.controls

# Player position
pos_x = fixp_init(controls.position.START_POS_X.value, fixp_pos)
pos_y = fixp_init(controls.position.START_POS_Y.value, fixp_pos)
# Camera direction
dir_x = fixp_init(controls.rotation.START_DIR_X.value, fixp_ray, True)
dir_y = fixp_init(controls.rotation.START_DIR_Y.value, fixp_ray, True)
# Camera plane vector
plane_x = fixp_init(controls.rotation.START_PLANE_X.value, fixp_ray, True)
plane_y = fixp_init(controls.rotation.START_PLANE_Y.value, fixp_ray, True)


def inv_model(num_in):
    num = fixp_unsigned(num_in, fixp_inv)
    cnt = 0
    approx = fixp_init(1, fixp_inv)
    product = fixp_init(0, fixp_inv)
    sub = fixp_init(0, fixp_inv)

    while num > 1:
        num = fixp_expr(num >> 1, num)
        cnt += 1

    for _ in range(INV_ITER_NUM):
        product = fixp_expr(num * approx, product)
        sub = fixp_expr(2 - product, sub)
        approx = fixp_expr(approx * sub, approx)

    approx = fixp_expr(approx >> cnt, approx)
    return approx


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


def column_calc_model(x):
    ray_x = fixp_init(0, fixp_ray, True)
    ray_dir_x = fixp_init(0, fixp_ray, True)
    ray_dir_y = fixp_init(0, fixp_ray, True)

    # from -1 to 1
    ray_x = fixp_expr((x * ray_step / 2**fixp_ray[1] - 1), ray_x)
    ray_dir_x = fixp_expr(dir_x + plane_x * ray_x, ray_dir_x)
    ray_dir_y = fixp_expr(dir_y + plane_y * ray_x, ray_dir_y)

    # from 0 to ext_pos_max
    if abs(ray_dir_x) <= 1 / max_dist:
        delta_dist_x = max_dist
    else:
        if ray_dir_x > 0:
            delta_dist_x = fixp_cast(inv_model(ray_dir_x), fixp_ext_pos)
        else:
            delta_dist_x = fixp_cast(inv_model(-ray_dir_x), fixp_ext_pos)

    # from 0 to ext_pos_max
    if abs(ray_dir_y) <= 1 / max_dist:
        delta_dist_y = max_dist
    else:
        if ray_dir_y > 0:
            delta_dist_y = fixp_cast(inv_model(ray_dir_y), fixp_ext_pos)
        else:
            delta_dist_y = fixp_cast(inv_model(-ray_dir_y), fixp_ext_pos)

    # Integer numbers, workaround to make side_dist_* unsigned
    # from 0 to 31
    map_x = fixp_init(int(pos_x), fixp_pos)
    map_y = fixp_init(int(pos_y), fixp_pos)

    # from 0 to ext_pos_max
    init_side_dist_x = fixp_init(0, fixp_ext_pos)
    init_side_dist_y = fixp_init(0, fixp_ext_pos)

    if ray_dir_x > 0:
        step_x = 1
        init_side_dist_x = fixp_expr(
            (map_x + 1 - pos_x) * delta_dist_x, init_side_dist_x
        )
    else:
        step_x = -1
        init_side_dist_x = fixp_expr(
            (pos_x - map_x) * delta_dist_x, init_side_dist_x
        )

    if ray_dir_y > 0:
        step_y = 1
        init_side_dist_y = fixp_expr(
            (map_y + 1 - pos_y) * delta_dist_y, init_side_dist_y
        )
    else:
        step_y = -1
        init_side_dist_y = fixp_expr(
            (pos_y - map_y) * delta_dist_y, init_side_dist_y
        )

    hit_side = 0
    map_x = int(pos_x)
    map_y = int(pos_y)

    # from 0 to ext_pos_max
    dda_dist_x = fixp_init(init_side_dist_x, fixp_ext_pos)
    dda_dist_y = fixp_init(init_side_dist_y, fixp_ext_pos)

    while True:
        if int(game_map[map_y][map_x]):
            break

        if (dda_dist_x < dda_dist_y):
            if (dda_dist_x + delta_dist_x) >= max_dist + 1:
                dda_dist_x = max_dist
            else:
                dda_dist_x = fixp_expr(
                    dda_dist_x + delta_dist_x, dda_dist_x
                )
                hit_side = 0
                map_x += step_x
        else:
            if (dda_dist_y + delta_dist_y) >= max_dist + 1:
                dda_dist_y = max_dist
            else:
                dda_dist_y = fixp_expr(
                    dda_dist_y + delta_dist_y, dda_dist_y
                )
                hit_side = 1
                map_y += step_y

    # from 0 to 31
    wall_dist = fixp_init(0, fixp_pos)
    texture = int(game_map[map_y][map_x])

    # from 0 to 1
    inv_wall_dist = fixp_init(0, fixp_inv_dist)
    tex_step = fixp_init(0, fixp_tex_step)

    if hit_side == 0:
        wall_dist = fixp_expr(dda_dist_x - delta_dist_x, wall_dist)
        tex_shade = 0
    else:
        wall_dist = fixp_expr(dda_dist_y - delta_dist_y, wall_dist)
        tex_shade = 1

    gte_one = False

    if wall_dist <= 1:
        gte_one = True
    else:
        inv_wall_dist = fixp_cast(
            inv_model(wall_dist), fixp_inv_dist
        )

    tex_step = fixp_expr(wall_dist * tex_step_scale, tex_step)

    coord_x = fixp_init(0, fixp_pos)
    proj_dist = fixp_init(0, (6, 10), True)

    if hit_side == 0:
        proj_dist = fixp_expr(wall_dist * ray_dir_y, proj_dist)
        fixp_cast(proj_dist, (6, 8))
        coord_x = fixp_expr(pos_y + proj_dist, coord_x)
    else:
        proj_dist = fixp_expr(wall_dist * ray_dir_x, proj_dist)
        fixp_cast(proj_dist, (6, 8))
        coord_x = fixp_expr(pos_x + proj_dist, coord_x)

    coord_x = fixp_expr(coord_x - math.floor(coord_x), coord_x)
    tex_x = int(coord_x << math.ceil(math.log2(TEX_SIDE)))

    if hit_side == 0 and ray_dir_x > 0:
        tex_x = TEX_SIDE - 1 - tex_x

    if hit_side == 1 and ray_dir_y < 0:
        tex_x = TEX_SIDE - 1 - tex_x

    if gte_one:
        return (texture, tex_shade, tex_x, tex_step, FRAME_HEIGHT)
    else:
        scaled_height = fixp_init(
            FRAME_HEIGHT * inv_wall_dist, (W_HEIGHT, 0)
        )
        return (texture, tex_shade, tex_x, tex_step, int(scaled_height))


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
            tex_step = int(render.rd_tex_step.value) / 2**12
            tex_height = int(render.rd_tex_height.value)

            mon_queue.put_nowait(
                (px_x, px_y, texture, tex_shade, tex_x, tex_step, tex_height)
            )


async def render_scoreboard(dut):
    raw_y_pos = fixp_init(0, (6, 12))
    tex_zoom = fixp_init(0, fixp_tex_zoom)

    while True:
        await RisingEdge(dut.px_clk)

        if dut.raycast_top.dvi_top.visible_range_del.value:
            px_x, px_y, texture, tex_shade, tex_x, tex_step, tex_height = (
                await mon_queue.get()
            )

            if px_y < FRAME_HEIGHT // 2:
                px_color = (20, 20, 20)
            else:
                px_color = (48, 48, 48)

            tex_start = FRAME_HEIGHT // 2 - tex_height
            tex_end = FRAME_HEIGHT // 2 + tex_height

            if px_y >= tex_start and px_y < tex_end:

                if tex_step < tex_step_scale:
                    tex_zoom = fixp_expr(
                        TEX_SIDE // 2
                        - fixp_expr(
                            FRAME_HEIGHT // 2 * tex_step, tex_zoom
                        ),
                        tex_zoom,
                    )
                else:
                    tex_zoom = fixp_expr(0, tex_zoom)

                tex_align = px_y - tex_start
                tex_align_ext = fixp_init(tex_align / 2**3, (6, 12))
                tex_align_scaled = fixp_init(0, (6, 12))
                tex_align_scaled = fixp_expr(
                    tex_align_ext * tex_step, tex_align_scaled
                )
                raw_y_pos = fixp_expr(
                    tex_zoom + (tex_align_scaled << 3), raw_y_pos
                )

                tex_y = min(31, int(raw_y_pos))

                px_pos = (tex_x, tex_y)

                px_color = textures[texture].getpixel(px_pos)
                r, g, b = px_color

                if tex_shade:
                    px_color = (r >> 1, g >> 1, b >> 1)
                else:
                    px_color = (r, g, b)

                surface.set_at((px_x, px_y), px_color)
                pg.display.update()

            red, green, blue = px_color

            render = dut.raycast_top.render
            dut_red = int(render.red_o.value)
            dut_green = int(render.green_o.value)
            dut_blue = int(render.blue_o.value)

            try:
                assert dut_red == red
            except AssertionError as e:
                print("=" * 80)
                print(f"X {px_x}")
                print(f"Y {px_y}")
                print(f"Expected red: {red}, got {dut_red}")
                print("=" * 80)
                breakpoint()
                for _ in range(50):
                    await RisingEdge(dut.px_clk)
                raise e

            try:
                assert dut_green == green
            except AssertionError as e:
                print("=" * 80)
                print(f"X {px_x}")
                print(f"Y {px_y}")
                print(f"Expected green: {green}, got {dut_green}")
                print("=" * 80)
                breakpoint()
                for _ in range(50):
                    await RisingEdge(dut.px_clk)
                raise e

            try:
                assert dut_blue == blue
            except AssertionError as e:
                print("=" * 80)
                print(f"X {px_x}")
                print(f"Y {px_y}")
                print(f"Expected blue: {blue}, got {dut_blue}")
                print("=" * 80)
                breakpoint()
                for _ in range(50):
                    await RisingEdge(dut.px_clk)
                raise e


async def pixel_calc(dut):
    pass
    cocotb.start_soon(render_monitor(dut))
    cocotb.start_soon(render_scoreboard(dut))


async def column_calc_scoreboard(dut, buf_toggle):
    # Clear screen
    surface.fill((0, 0, 0))
    pg.draw.rect(surface, (20, 20, 20), (0, 0, 640, 240))
    pg.draw.rect(surface, (48, 48, 48), (0, 240, 640, 240))

    await RisingEdge(dut.px_clk)
    await RisingEdge(dut.raycast_top.frame_done)
    mem = dut.raycast_top.render.frame_buffer.value

    for x in range(FRAME_WIDTH):
        texture, tex_shade, tex_x, tex_step, tex_height = (
            column_calc_model(x)
        )

        dut_shade = int(mem[(FRAME_WIDTH * buf_toggle) + x][28])
        dut_tex_x = int(mem[(FRAME_WIDTH * buf_toggle) + x][27:23])
        dut_tex_step = int(mem[(FRAME_WIDTH * buf_toggle) + x][22:8]) / 2**12
        dut_height = int(mem[(FRAME_WIDTH * buf_toggle) + x][7:0])

        height_div2 = tex_height // 2

        try:
            assert dut_height == height_div2
        except AssertionError as e:
            print("=" * 80)
            print(f"Pixel {x}")
            print(f"Expected height: {height_div2}, got {dut_height}")
            print("=" * 80)
            breakpoint()
            raise e

        try:
            assert dut_shade == tex_shade
        except AssertionError as e:
            print("=" * 80)
            print(f"Pixel {x}")
            print(f"Expected color: {tex_shade}, got {dut_shade}")
            print("=" * 80)
            breakpoint()
            raise e

        try:
            assert dut_tex_x == tex_x
        except AssertionError as e:
            print("=" * 80)
            print(f"Pixel {x}")
            print(f"Expected tex_x: {tex_x}, got {dut_tex_x}")
            print("=" * 80)
            breakpoint()
            raise e

        try:
            assert dut_tex_step == tex_step
        except AssertionError as e:
            print("=" * 80)
            print(f"Pixel {x}")
            print(f"Expected tex_step: {tex_step}, got {dut_tex_step}")
            print("=" * 80)
            breakpoint()
            raise e

        start_pos = FRAME_HEIGHT // 2 - tex_height // 2
        if start_pos < 0:
            start_pos = 0

        end_pos = FRAME_HEIGHT // 2 + tex_height // 2
        if end_pos > FRAME_HEIGHT - 1:
            end_pos = FRAME_HEIGHT - 1

        y_zoom_offset = fixp_init(0, (4, 4))

        if tex_step < tex_step_scale:
            y_zoom_offset = fixp_expr(
                TEX_SIDE // 2
                - fixp_expr(
                    FRAME_HEIGHT // 2 * tex_step, y_zoom_offset
                ),
                y_zoom_offset,
            )
        else:
            y_zoom_offset = 0

        for y in range(FRAME_HEIGHT):
            if y >= start_pos and y < end_pos:

                tex_align = y - start_pos
                tex_align_ext = fixp_init(tex_align / 2**3, (6, 12))
                raw_y_pos = fixp_init(0, (6, 12))
                tex_align_scaled = fixp_init(0, (6, 12))
                tex_align_scaled = fixp_expr(
                    tex_align_ext * tex_step, tex_align_scaled
                )
                raw_y_pos = fixp_expr(
                    y_zoom_offset + (tex_align_scaled << 3), raw_y_pos
                )

                tex_y = min(31, int(raw_y_pos))

                px_pos = (tex_x, tex_y)
                px_color = textures[texture-1].getpixel(px_pos)
                if tex_shade:
                    r, g, b = px_color
                    px_color = (r >> 1, g >> 1, b >> 1)

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
    font.render_to(surface, (20, 20), f"FPS: {str(fps)}", green)
    font.render_to(surface, (20, 50), f"pos_x: {pos_x}", green)
    font.render_to(surface, (20, 80), f"pos_y: {pos_y}", green)
    font.render_to(surface, (20, 110), f"plane_x: {plane_x}", green)
    font.render_to(surface, (20, 140), f"plane_y: {plane_y}", green)
    font.render_to(surface, (20, 170), f"dir_x: {dir_x}", green)
    font.render_to(surface, (20, 200), f"dir_y: {dir_y}", green)


def controls(dut):
    global dir_x
    global dir_y
    global plane_x
    global plane_y

    for event in pg.event.get():
        if event.type == pg.KEYDOWN:
            if event.key == pg.K_q:
                quit()

    keys = pg.key.get_pressed()

    forward = 0
    backward = 0
    left = 0
    right = 0
    rot_left = 0
    rot_right = 0

    def update_pos(dir, is_x):
        global pos_x, pos_y
        step_next = fixp_expr(dir * move_speed, dir)
        if is_x:
            update_axis = pos_x
        else:
            update_axis = pos_y

        new_pos = fixp_init(
            update_axis + fixp_cast(step_next, fixp_pos), fixp_pos
        )
        if is_x and int(game_map[int(pos_y)][int(new_pos)]) == 0:
            pos_x = new_pos
        if not is_x and int(game_map[int(new_pos)][int(pos_x)]) == 0:
            pos_y = new_pos

    # Update x axis
    if keys[pg.K_w]:
        forward = 1
        update_pos(dir_x, 1)
    if keys[pg.K_s]:
        backward = 1
        update_pos(-dir_x, 1)
    if keys[pg.K_a]:
        left = 1
        update_pos(-dir_y, 1)
    if keys[pg.K_d]:
        right = 1
        update_pos(dir_y, 1)

    # Update y axis
    if keys[pg.K_w]:
        update_pos(dir_y, 0)
    if keys[pg.K_s]:
        update_pos(-dir_y, 0)
    if keys[pg.K_a]:
        update_pos(dir_x, 0)
    if keys[pg.K_d]:
        update_pos(-dir_x, 0)

    # Rotate right
    if keys[pg.K_RIGHT] and not keys[pg.K_LEFT]:
        rot_right = 1

        old_dir_x = fixp_init(dir_x, fixp_ray, True)
        dir_x = fixp_cast(
            fixp_cast(dir_x * cos_neg_angle, fixp_ray)
            - fixp_cast(dir_y * sin_neg_angle, fixp_ray),
            fixp_ray,
        )
        dir_y = fixp_cast(
            fixp_cast(old_dir_x * sin_neg_angle, fixp_ray)
            + fixp_cast(dir_y * cos_neg_angle, fixp_ray),
            fixp_ray,
        )

        plane_x = fixp_cast(dir_y * FIXP_MULT_COEFF, fixp_ray)
        plane_y = fixp_cast(
            -fixp_cast(dir_x * FIXP_MULT_COEFF, fixp_ray), fixp_ray
        )

    # Rotate left
    if keys[pg.K_LEFT] and not keys[pg.K_RIGHT]:
        rot_left = 1

        old_dir_x = fixp_init(dir_x, fixp_ray, True)
        dir_x = fixp_cast(
            fixp_cast(dir_x * cos_angle, fixp_ray)
            - fixp_cast(dir_y * sin_angle, fixp_ray),
            fixp_ray,
        )
        dir_y = fixp_cast(
            fixp_cast(old_dir_x * sin_angle, fixp_ray)
            + fixp_cast(dir_y * cos_angle, fixp_ray),
            fixp_ray,
        )

        plane_x = fixp_cast(dir_y * FIXP_MULT_COEFF, fixp_ray)
        plane_y = fixp_cast(
            -fixp_cast(dir_x * FIXP_MULT_COEFF, fixp_ray), fixp_ray
        )

    # Cocotb doesn't allow indexing of packed arrays, so yikes
    key_str = f"{rot_right}{rot_left}{right}{left}{backward}{forward}"
    dut.keys_inv_i.value = ~LogicArray(key_str)


def quit():
    pg.quit()
    cocotb.pass_test("Quit action")


async def dut_reset(dut):
    dut.rst_n.value = 0
    await RisingEdge(dut.px_clk)
    dut.rst_n.value = 1


async def coro_quit(dut):
    while True:
        await RisingEdge(dut.px_clk)
        for event in pg.event.get():
            if event.type == pg.KEYDOWN:
                if event.key == pg.K_q:
                    quit()


async def setup(dut):
    global game_map
    cocotb.start_soon(dut_reset(dut))

    await RisingEdge(dut.px_clk)
    game_map = cocotb.top.raycast_top.temp_map.map.value


@cocotb.test()
async def check_column_calc(dut):
    await setup(dut)

    buf_toggle = 1
    while True:
        controls(dut)
        await column_calc_scoreboard(dut, buf_toggle)
        buf_toggle = buf_toggle ^ 1


@cocotb.test()
async def check_render(dut):
    await setup(dut)

    cocotb.start_soon(pixel_calc(dut))
    while True:
        await RisingEdge(dut.raycast_top.frame_done)
