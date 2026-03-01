import math
from fpbinary import FpBinary, FpBinarySwitchable, RoundingEnum
import pygame as pg
from pygame import freetype
import cocotb
from cocotb.types import LogicArray
from cocotb.triggers import RisingEdge, Timer


FRAME_WIDTH = 640
FRAME_HEIGHT = 480

MAP_WIDTH = 20
MAP_HEIGHT = 20

INV_ITER_NUM = int(cocotb.packages.fixp_pkg.INV_ITER_NUM.value)  # type: ignore
W_HEIGHT = int(cocotb.top.W_Y_POS.value)  # type: ignore
MOVEMENT_SPEED = float(cocotb.top.MOVEMENT_SPEED.value)  # type: ignore
ROTATION_SPEED = float(cocotb.top.ROTATION_SPEED.value)  # type: ignore

FP_MODE = True

fixp_ray = (2, 10)
fixp_pos = (5, 8)
fixp_inv = (8, 10)
fixp_ext_pos = (8, 8)
fixp_pos_ext_frac = (1, 10)

pg.init()
font = freetype.Font(None, 24)
surface = pg.display.set_mode((FRAME_WIDTH, FRAME_HEIGHT))

game_map = [
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 0, 1],
    [1, 0, 0, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
    [1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
]


def fixp_init(val, type, signed=False):

    int_bits, frac_bits = type

    fp_value = FpBinary(
        int_bits=int_bits, frac_bits=frac_bits, signed=signed, value=val
    )

    return FpBinarySwitchable(
        fp_mode=FP_MODE, fp_value=fp_value, float_value=val
    )


def fixp_expr(expr, num):
    int_bits, frac_bits = num.format

    fp_value = FpBinary(
        int_bits=int_bits,
        frac_bits=frac_bits,
        signed=num.value.is_signed,
        value=expr,
    )

    return FpBinarySwitchable(
        fp_mode=FP_MODE, fp_value=fp_value, float_value=expr
    )


def fixp_unsigned(val, type):
    int_bits, frac_bits = type

    fp_value = FpBinary(
        int_bits=int_bits,
        frac_bits=frac_bits,
        signed=False,
        value=val
    )

    return FpBinarySwitchable(
        fp_mode=FP_MODE,
        fp_value=fp_value,
        float_value=val
    )


def fixp_cast(num, fixp_type):
    int_bits, frac_bits = fixp_type
    return num.resize(
        format=(int_bits, frac_bits),
        round_mode=RoundingEnum.direct_neg_inf,
    )


time = 0

PLANE_COEFF = float(
    cocotb.top.raycast_top.controls.rotation.PLANE_COEFF.value  # type: ignore
)
FIXP_MULT_COEFF = fixp_init(PLANE_COEFF, fixp_ray, True)
move_speed = fixp_init(MOVEMENT_SPEED, fixp_ray, True)

cos_angle = fixp_init(math.cos(ROTATION_SPEED), fixp_ray, True)
sin_angle = fixp_init(math.sin(ROTATION_SPEED), fixp_ray, True)
cos_neg_angle = fixp_init(math.cos(-ROTATION_SPEED), fixp_ray, True)
sin_neg_angle = fixp_init(math.sin(-ROTATION_SPEED), fixp_ray, True)

max_dist = fixp_init(2 ** fixp_ext_pos[0] - 1, fixp_ext_pos)
pos_max = fixp_init(2 ** fixp_pos[0] - 1, fixp_pos)

step = 2.0 / FRAME_WIDTH * 2**fixp_ray[1]

# Mimic rounding of int cast in SystemVerilog
if step < 0.5:
    ray_step = fixp_init(0, fixp_ray)
else:
    ray_step = fixp_init(round(step), fixp_ray)

controls = cocotb.top.raycast_top.controls  # type: ignore

# Player position
pos_x = fixp_init(
    controls.position.START_POS_X.value,  # type: ignore
    fixp_pos,
)
pos_y = fixp_init(
    controls.position.START_POS_Y.value,  # type: ignore
    fixp_pos,
)


# Camera direction
dir_x = fixp_init(
    controls.rotation.START_DIR_X.value,  # type: ignore
    fixp_ray,
    True,
)
dir_y = fixp_init(
    controls.rotation.START_DIR_Y.value,  # type: ignore
    fixp_ray,
    True,
)

# Camera plane vector
plane_x = fixp_init(
    controls.rotation.START_PLANE_X.value,  # type: ignore
    fixp_ray,
    True,
)
plane_y = fixp_init(
    controls.rotation.START_PLANE_Y.value,  # type: ignore
    fixp_ray,
    True,
)


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


ray_x = 0
ray_dir_x = 0
ray_dir_y = 0
delta_dist_x = 0
delta_dist_y = 0
init_side_dist_x = 0
init_side_dist_y = 0
hit_side = 0
map_x = 0
map_y = 0
wall_dist = 0
inv_wall_dist = 0
scaled_height = 0
init_side_dist_x = 0
init_side_dist_y = 0
dda_dist_x = 0
dda_dist_y = 0


def line_height_calc_model(x):
    global ray_x, ray_dir_x, ray_dir_y
    global delta_dist_x, delta_dist_y, init_side_dist_x, init_side_dist_y
    global hit_side, map_x, map_y
    global wall_dist, inv_wall_dist, scaled_height
    global dda_dist_x, dda_dist_y

    ray_x = fixp_init(0, fixp_ray, True)
    ray_dir_x = fixp_init(0, fixp_ray, True)
    ray_dir_y = fixp_init(0, fixp_ray, True)

    # from -1 to 1
    ray_x = fixp_expr((x * ray_step / 2**fixp_ray[1] - 1), ray_x)

    # from -2 to 2
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
        init_side_dist_x = fixp_expr((pos_x - map_x) * delta_dist_x, init_side_dist_x)

    if ray_dir_y > 0:
        step_y = 1
        init_side_dist_y = fixp_expr(
            (map_y + 1 - pos_y) * delta_dist_y, init_side_dist_y
        )
    else:
        step_y = -1
        init_side_dist_y = fixp_expr((pos_y - map_y) * delta_dist_y, init_side_dist_y)

    hit_side = 0

    map_x = int(pos_x)
    map_y = int(pos_y)

    # from 0 to ext_pos_max
    dda_dist_x = fixp_init(init_side_dist_x, fixp_ext_pos)
    dda_dist_y = fixp_init(init_side_dist_y, fixp_ext_pos)

    while True:
        if game_map[map_y][map_x] == 1:
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

    # from 0 to 1
    inv_wall_dist = fixp_init(0, fixp_pos_ext_frac)

    if hit_side == 0:
        wall_dist = fixp_expr(dda_dist_x - delta_dist_x, wall_dist)
        line_color = 0
    else:
        wall_dist = fixp_expr(dda_dist_y - delta_dist_y, wall_dist)
        line_color = 1

    gte_one = False

    if wall_dist <= 1:
        gte_one = True
    else:
        inv_wall_dist = fixp_cast(
            inv_model(wall_dist), fixp_pos_ext_frac
        )

    if gte_one:
        return (FRAME_HEIGHT, line_color)
    else:
        scaled_height = fixp_init(
            FRAME_HEIGHT * inv_wall_dist, (W_HEIGHT, 0)
        )
        # breakpoint()
        return (int(scaled_height), line_color)


async def render(dut):
    # Clear screen
    surface.fill((0, 0, 0))

    await RisingEdge(dut.px_clk)

    await RisingEdge(dut.raycast_top.frame_done)
    mem = dut.raycast_top.render.frame_buffer.value

    for x in range(FRAME_WIDTH):
        line_height, line_color = line_height_calc_model(x)

        dut_color = int(mem[x][8])
        dut_height = int(mem[x][7:0])

        height_div2 = line_height // 2

        try:
            assert dut_height == height_div2
        except AssertionError as e:
            top = dut.raycast_top
            print("=" * 80)
            print(f"Pixel {x}")
            print(f"Expected height: {height_div2}, got {dut_height}")

            print(f"Expected dir_x: {dir_x}")
            print(
                f"Got dir_x: {top.dir_x.value.to_signed() / 2**fixp_ray[1]}"
            )
            print(f"Expected dir_y: {dir_y}")
            print(
                f"Got dir_y: {top.dir_y.value.to_signed() / 2**fixp_ray[1]}\n"
            )

            print(f"Expected plane_x: {plane_x}")
            print(
                f"Got plane_x: {top.plane_x.value.to_signed()/2**fixp_ray[1]}"
            )
            print(f"Expected plane_y: {plane_y}")
            print(
                f"Got plane_y: {top.plane_y.value.to_signed()/2**fixp_ray[1]}"
            )

            print(f"Expected pos_x: {pos_x}")
            print(
                f"Got pos_x: {top.pos_x.value.to_unsigned() / 2**fixp_pos[1]}"
            )
            print(f"Expected pos_y: {pos_y}")
            print(
                f"Got pos_y: {top.pos_y.value.to_unsigned() / 2**fixp_pos[1]}"
            )

            print(f"ray_x {ray_x}")
            print(f"ray_dir_x {ray_dir_x}")
            print(f"ray_dir_y {ray_dir_y}")
            print(f"delta_dist_x {delta_dist_x}")
            print(f"delta_dist_y {delta_dist_y}")
            print(f"init_side_dist_x {init_side_dist_x}")
            print(f"init_side_dist_y {init_side_dist_y}")
            print(f"dda_side_dist_x {dda_dist_x}")
            print(f"dda_side_dist_y {dda_dist_y}")
            print(f"hit_side {hit_side}")
            print(f"wall_dist {wall_dist}")
            print(f"inv_wall_dist {inv_wall_dist}")
            print(f"scaled_height {scaled_height}")
            print(f"map_x {map_x}")
            print(f"map_y {map_y}")
            print(f"init_side_dist_x {init_side_dist_x}")
            print(f"init_side_dist_y {init_side_dist_y}")
            print(f"line_height {line_height}")
            print("=" * 80)
            raise e

        try:
            assert dut_color == line_color
        except AssertionError as e:
            print("=" * 80)
            print(f"Pixel {x}")
            print(f"Expected color: {line_color}, got {dut_color}")
            print("=" * 80)
            raise e

        start_pos = FRAME_HEIGHT // 2 - line_height // 2

        if start_pos < 0:
            start_pos = 0
        end_pos = FRAME_HEIGHT // 2 + line_height // 2

        if end_pos > FRAME_HEIGHT - 1:
            end_pos = FRAME_HEIGHT - 1

        if (x == 300):
            white = (255, 0, 0)
            grey = (0, 0, 255)
        else:
            white = (255, 255, 255)
            grey = (127, 127, 127)
        pg_color = grey if line_color else white
        pg.draw.line(surface, pg_color, (x, start_pos), (x, end_pos))

    print_info()
    pg.display.update()
    # cocotb.pass_test("Quit action")


def print_info():
    global time
    old_time = time
    time = pg.time.get_ticks()
    frame_time = (time - old_time) / 1000.0
    fps = 1 / frame_time

    font.render_to(surface, (20, 20), f"FPS: {str(fps)}", (0, 255, 0))
    font.render_to(surface, (20, 50), f"pos_x: {pos_x}", (0, 255, 0))
    font.render_to(surface, (20, 80), f"pos_y: {pos_y}", (0, 255, 0))
    font.render_to(surface, (20, 110), f"plane_x: {plane_x}", (0, 255, 0))
    font.render_to(surface, (20, 140), f"plane_y: {plane_y}", (0, 255, 0))
    font.render_to(surface, (20, 170), f"dir_x: {dir_x}", (0, 255, 0))
    font.render_to(surface, (20, 200), f"dir_y: {dir_y}", (0, 255, 0))


def controls(dut):
    global pos_x
    global pos_y
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

    new_pos = fixp_init(0, fixp_pos)
    step_next = fixp_init(0, fixp_ray, True)

    # Update x axis
    # Forward
    if keys[pg.K_w]:
        forward = 1
        step_next = fixp_expr(dir_x * move_speed, dir_x)
        new_pos = fixp_expr(
            pos_x + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Backward
    if keys[pg.K_s]:
        backward = 1
        step_next = fixp_expr(-dir_x * move_speed, dir_x)
        new_pos = fixp_expr(
            pos_x + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Left
    if keys[pg.K_a]:
        left = 1
        step_next = fixp_expr(-dir_y * move_speed, dir_y)
        new_pos = fixp_expr(
            pos_x + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Right
    if keys[pg.K_d]:
        right = 1
        step_next = fixp_expr(dir_y * move_speed, dir_y)
        new_pos = fixp_expr(
            pos_x + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Update y axis
    # Forward
    if keys[pg.K_w]:
        step_next = fixp_expr(dir_y * move_speed, dir_y)
        new_pos = fixp_expr(
            pos_y + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

    # Backward
    if keys[pg.K_s]:
        step_next = fixp_expr(-dir_y * move_speed, dir_y)
        new_pos = fixp_expr(
            pos_y + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

    # Left
    if keys[pg.K_a]:
        step_next = fixp_expr(dir_x * move_speed, dir_x)
        new_pos = fixp_expr(
            pos_y + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

    # Right
    if keys[pg.K_d]:
        step_next = fixp_expr(-dir_x * move_speed, dir_x)
        new_pos = fixp_expr(
            pos_y + fixp_cast(step_next, fixp_pos), new_pos
        )
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

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


@cocotb.test()
async def run_raycast(dut):
    cocotb.start_soon(dut_reset(dut))

    while True:
        controls(dut)
        await render(dut)
