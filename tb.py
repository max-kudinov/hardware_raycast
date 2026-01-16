import math
from fpbinary import FpBinary, FpBinarySwitchable, RoundingEnum
import pygame as pg
from pygame import freetype
import cocotb
from cocotb.types import LogicArray
from cocotb.triggers import FallingEdge, RisingEdge, Timer


FRAME_WIDTH = 640
FRAME_HEIGHT = 480

MAP_WIDTH = 20
MAP_HEIGHT = 20

W_INT = int(cocotb.packages.fixedpoint.W_INT.value)
W_FRAC = int(cocotb.packages.fixedpoint.W_FRAC.value)
N_ITER = int(cocotb.packages.fixedpoint.N_ITER.value)
MOVEMENT_SPEED = float(cocotb.top.MOVEMENT_SPEED.value)  # type: ignore
ROTATION_SPEED = float(cocotb.top.ROTATION_SPEED.value)  # type: ignore

FP_MODE = True

W_HEIGHT = int(cocotb.top.W_Y_POS.value)  # type: ignore

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


move_speed = fixp(MOVEMENT_SPEED, signed=True)
cos_angle = fixp(math.cos(ROTATION_SPEED), signed=True)
sin_angle = fixp(math.sin(ROTATION_SPEED), signed=True)
cos_neg_angle = fixp(math.cos(-ROTATION_SPEED), signed=True)
sin_neg_angle = fixp(math.sin(-ROTATION_SPEED), signed=True)

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
        line_color = 0
    else:
        perp_wall_dist = fixp(side_dist_y - delta_dist_y)
        line_color = 1

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

    await RisingEdge(dut.px_clk)
    # cocotb.start_soon(timeout())

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
            print("=" * 80)
            print(f"Pixel {x}")
            print(f"Expected height: {height_div2}, got {dut_height}")

            print(f"Expected dir_x: {dir_x}")
            print(f"Got dir_x: {dut.raycast_top.dir_x.value.to_signed() / 2**W_FRAC}")
            print(f"Expected dir_y: {dir_y}")
            print(f"Got dir_y: {dut.raycast_top.dir_y.value.to_signed() / 2**W_FRAC}\n")

            print(f"Expected plane_x: {plane_x}")
            print(f"Got plane_x: {dut.raycast_top.plane_x.value.to_signed() / 2**W_FRAC}")
            print(f"Expected plane_y: {plane_y}")
            print(f"Got plane_y: {dut.raycast_top.plane_y.value.to_signed() / 2**W_FRAC}\n")

            print(f"Expected pos_x: {pos_x}")
            print(f"Got pos_x: {dut.raycast_top.pos_x.value.to_unsigned() / 2**W_FRAC}")
            print(f"Expected pos_y: {pos_y}")
            print(f"Got pos_y: {dut.raycast_top.pos_y.value.to_unsigned() / 2**W_FRAC}")
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

        start_pos = FRAME_HEIGHT // 2 - dut_height // 2

        if start_pos < 0:
            start_pos = 0
        end_pos = FRAME_HEIGHT // 2 + dut_height // 2

        if end_pos > FRAME_HEIGHT - 1:
            end_pos = FRAME_HEIGHT - 1

        pg_color = (127, 127, 127) if dut_color else (255, 255, 255)
        pg.draw.line(surface, pg_color, (x, start_pos), (x, end_pos))

    print_info()
    pg.display.update()
    # cocotb.pass_test("Quit action")


async def timeout():
    await Timer(10_000, "ns")
    assert False


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

    # Update x axis
    # Forward
    if keys[pg.K_w]:
        forward = 1
        new_pos = fixp_unsigned(pos_x + fixp(dir_x * move_speed))
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Backward
    if keys[pg.K_s]:
        backward = 1
        new_pos = fixp_unsigned(pos_x + fixp(-dir_x * move_speed))
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Left
    if keys[pg.K_a]:
        left = 1
        new_pos = fixp_unsigned(pos_x + fixp(-dir_y * move_speed))
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Right
    if keys[pg.K_d]:
        right = 1
        new_pos = fixp_unsigned(pos_x + fixp(dir_y * move_speed))
        if game_map[int(pos_y)][int(new_pos)] != 1:
            pos_x = new_pos

    # Update y axis
    # Forward
    if keys[pg.K_w]:
        new_pos = fixp_unsigned(pos_y + fixp(dir_y * move_speed))
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

    # Backward
    if keys[pg.K_s]:
        new_pos = fixp_unsigned(pos_y + fixp(-dir_y * move_speed))
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

    # Left
    if keys[pg.K_a]:
        new_pos = fixp_unsigned(pos_y + fixp(dir_x * move_speed))
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

    # Right
    if keys[pg.K_d]:
        new_pos = fixp_unsigned(pos_y + fixp(-dir_x * move_speed))
        if game_map[int(new_pos)][int(pos_x)] != 1:
            pos_y = new_pos

    # Rotate right
    if keys[pg.K_RIGHT] and not keys[pg.K_LEFT]:
        rot_right = 1

        old_dir_x = fixp(dir_x)
        dir_x = fixp(
            fixp(dir_x * cos_neg_angle) - fixp(dir_y * sin_neg_angle),
        )
        dir_y = fixp(
            fixp(old_dir_x * sin_neg_angle) + fixp(dir_y * cos_neg_angle),
        )

        old_plane_x = fixp(plane_x)
        plane_x = fixp(
            fixp(plane_x * cos_neg_angle) - fixp(plane_y * sin_neg_angle),
        )
        plane_y = fixp(
            fixp(old_plane_x * sin_neg_angle) + fixp(plane_y * cos_neg_angle),
        )

    # Rotate left
    if keys[pg.K_LEFT] and not keys[pg.K_RIGHT]:
        rot_left = 1

        old_dir_x = fixp(dir_x)
        dir_x = fixp(
            fixp(dir_x * cos_angle) - fixp(dir_y * sin_angle),
        )
        dir_y = fixp(
            fixp(old_dir_x * sin_angle) + fixp(dir_y * cos_angle),
        )

        old_plane_x = fixp(plane_x)
        plane_x = fixp(
            fixp(plane_x * cos_angle) - fixp(plane_y * sin_angle),
        )
        plane_y = fixp(
            fixp(old_plane_x * sin_angle) + fixp(plane_y * cos_angle),
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
