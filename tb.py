import math
from fpbinary import FpBinary, FpBinarySwitchable, RoundingEnum
import pygame as pg
from pygame import freetype
import cocotb
from cocotb.triggers import RisingEdge


FRAME_WIDTH = 640
FRAME_HEIGHT = 480

MAP_WIDTH = 20
MAP_HEIGHT = 20

W_INT = int(cocotb.packages.fixedpoint.W_INT.value)
W_FRAC = int(cocotb.packages.fixedpoint.W_FRAC.value)
N_ITER = int(cocotb.packages.fixedpoint.N_ITER.value)

FP_MODE = True

W_HEIGHT = int(cocotb.top.W_HEIGHT.value)  # type: ignore

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


def fixp(val, int_bits=W_INT, frac_bits=W_FRAC, signed=False):

    if type(val) is FpBinarySwitchable:
        return val.resize(
            format=(int_bits, frac_bits),
            round_mode=RoundingEnum.direct_neg_inf,
        )
    else:
        fp_value = FpBinary(
            int_bits=int_bits,
            frac_bits=frac_bits,
            signed=signed,
            value=val
        )

        return FpBinarySwitchable(
            fp_mode=FP_MODE,
            fp_value=fp_value,
            float_value=val
        )


def fixp_unsigned(val, int_bits=W_INT, frac_bits=W_FRAC):
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


# Player position
pos_x = fixp(10)
pos_y = fixp(10)

# Camera direction
dir_x = fixp(0.94, signed=True)
dir_y = fixp(-0.33, signed=True)

# Camera plane vector
plane_x = fixp(-0.22, signed=True)
plane_y = fixp(-0.62, signed=True)

step = 2.0 / FRAME_WIDTH * 2**(W_FRAC)

# Mimic rounding of int cast in SystemVerilog
if step < 0.5:
    ray_step = 0
else:
    ray_step = round(step)

time = 0


def float_to_fixp(num_float):
    return int(num_float * (2 ** W_FRAC))


def fixp_to_float(num_fixp):
    return float(num_fixp) / (2 ** W_FRAC)


def inv_model(num_in):
    num = fixp_unsigned(num_in)
    cnt = 0
    approx = fixp(1)
    product = fixp(0)
    sub = fixp(0)
    fixp_2 = fixp(2)

    while num > 1:
        num = fixp(num >> 1)
        cnt += 1

    for _ in range(N_ITER):
        product = fixp(num * approx)
        sub = fixp(fixp_2 - product)
        approx = fixp(approx * sub)

    approx = fixp(approx >> cnt)
    return approx


fixp_frame_height = fixp(FRAME_HEIGHT, int_bits=W_HEIGHT)


def line_height_calc_model(x):
    ray_x = fixp((x * ray_step / 2**W_FRAC - 1), signed=True)

    ray_dir_x = fixp(dir_x + plane_x * ray_x, signed=True)
    ray_dir_y = fixp(dir_y + plane_y * ray_x, signed=True)

    if ray_dir_x == 0:
        delta_dist_x = fixp(2**(W_INT-1)-1)
    else:
        if ray_dir_x > 0:
            delta_dist_x = inv_model(ray_dir_x)
        else:
            delta_dist_x = inv_model(-ray_dir_x)

    if ray_dir_y == 0:
        delta_dist_y = fixp(2**(W_INT-1)-1)
    else:
        if ray_dir_y > 0:
            delta_dist_y = inv_model(ray_dir_y)
        else:
            delta_dist_y = inv_model(-ray_dir_y)

    # Integer numbers, workaround to make side_dist_* unsigned
    map_x = fixp(int(pos_x))
    map_y = fixp(int(pos_y))
    one = fixp(1)

    if ray_dir_x > 0:
        step_x = 1
        side_dist_x = fixp((map_x + one - pos_x) * delta_dist_x)
    else:
        step_x = -1
        side_dist_x = fixp((pos_x - map_x) * delta_dist_x)

    if ray_dir_y > 0:
        step_y = 1
        side_dist_y = fixp((map_y + one - pos_y) * delta_dist_y)
    else:
        step_y = -1
        side_dist_y = fixp((pos_y - map_y) * delta_dist_y)

    hit_side = 0

    map_x = int(pos_x)
    map_y = int(pos_y)

    while True:
        if game_map[map_y][map_x] == 1:
            break

        if (side_dist_x < side_dist_y):
            side_dist_x = fixp(side_dist_x + delta_dist_x)
            map_x += step_x
            hit_side = 0
        else:
            side_dist_y = fixp(side_dist_y + delta_dist_y)
            map_y += step_y
            hit_side = 1

    if hit_side == 0:
        perp_wall_dist = fixp(side_dist_x - delta_dist_x)
        line_color = (255, 255, 255)
    else:
        perp_wall_dist = fixp(side_dist_y - delta_dist_y)
        line_color = (128, 128, 128)

    if perp_wall_dist == 0:
        inv_perp_wall_dist = 2**W_INT
    else:
        inv_perp_wall_dist = inv_model(perp_wall_dist)

    if int(inv_perp_wall_dist) == 0:
        scaled_height = fixp(
            fixp_frame_height * inv_perp_wall_dist, int_bits=W_HEIGHT+1
        )
        return (int(scaled_height), line_color)
    else:
        return (int(fixp_frame_height), line_color)


async def render(dut):
    # Clear screen
    surface.fill((0, 0, 0))

    for x in range(FRAME_WIDTH):
        line_height_model, _ = line_height_calc_model(x)
        line_height, line_color = await line_height_calc(dut, x)

        try:
            assert line_height_model == line_height
        except AssertionError as e:
            print("=" * 80)
            print(f"pixel {x}")
            print(f"Expected {line_height_model}, got: {line_height}")
            print("=" * 80)
            raise e

        start_pos = FRAME_HEIGHT // 2 - line_height // 2

        if start_pos < 0:
            start_pos = 0
        end_pos = FRAME_HEIGHT // 2 + line_height // 2

        if end_pos > FRAME_HEIGHT - 1:
            end_pos = FRAME_HEIGHT - 1

        pg.draw.line(surface, line_color, (x, start_pos), (x, end_pos))
    print_info()
    pg.display.update()


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


def controls():
    global pos_x
    global pos_y
    global dir_x
    global dir_y
    global plane_x
    global plane_y

    move_speed = 0.8
    rot_speed = 0.4

    for event in pg.event.get():
        if event.type == pg.KEYDOWN:
            if event.key == pg.K_q:
                quit()

    keys = pg.key.get_pressed()

    # Forward
    if keys[pg.K_w]:
        if game_map[int(pos_y)][int(pos_x + dir_x * move_speed)] != 1:
            pos_x = fixp_unsigned(pos_x + dir_x * move_speed)
        if game_map[int(pos_y + dir_y * move_speed)][int(pos_x)] != 1:
            pos_y = fixp_unsigned(pos_y + dir_y * move_speed)

    # Backwards
    if keys[pg.K_s]:
        if game_map[int(pos_y)][int(pos_x - dir_x * move_speed)] != 1:
            pos_x = fixp_unsigned(pos_x - dir_x * move_speed)
        if game_map[int(pos_y - dir_y * move_speed)][int(pos_x)] != 1:
            pos_y = fixp_unsigned(pos_y - dir_y * move_speed)

    # Rotate right
    if keys[pg.K_d]:
        old_dir_x = fixp(dir_x, signed=True)
        dir_x = fixp(
            dir_x * math.cos(-rot_speed) - dir_y * math.sin(-rot_speed),
            signed=True,
        )
        dir_y = fixp(
            old_dir_x * math.sin(-rot_speed)
            + dir_y * math.cos(-rot_speed),
            signed=True,
        )
        old_plane_x = fixp(plane_x, signed=True)
        plane_x = fixp(
            plane_x * math.cos(-rot_speed)
            - plane_y * math.sin(-rot_speed),
            signed=True,
        )
        plane_y = fixp(
            old_plane_x * math.sin(-rot_speed)
            + plane_y * math.cos(-rot_speed),
            signed=True,
        )

    # Rotate left
    if keys[pg.K_a]:
        old_dir_x = fixp(dir_x, signed=True)
        dir_x = fixp(
            dir_x * math.cos(rot_speed) - dir_y * math.sin(rot_speed),
            signed=True,
        )
        dir_y = fixp(
            old_dir_x * math.sin(rot_speed) + dir_y * math.cos(rot_speed),
            signed=True,
        )
        old_plane_x = fixp(plane_x, signed=True)
        plane_x = fixp(
            plane_x * math.cos(rot_speed) - plane_y * math.sin(rot_speed),
            signed=True,
        )
        plane_y = fixp(
            old_plane_x * math.sin(rot_speed)
            + plane_y * math.cos(rot_speed),
            signed=True,
        )


def quit():
    pg.quit()
    cocotb.pass_test("Quit action")


async def dut_reset(dut):
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0


@cocotb.test()
async def run_raycast(dut):
    cocotb.start_soon(dut_reset(dut))

    while True:
        controls()
        await render(dut)
