import math
from fpbinary import FpBinary, FpBinarySwitchable, RoundingEnum
import pygame as pg
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge


FRAME_WIDTH = 640
FRAME_HEIGHT = 480

MAP_WIDTH = 20
MAP_HEIGHT = 20

W_INT = int(cocotb.packages.fixedpoint.W_INT.value)
W_FRAC = int(cocotb.packages.fixedpoint.W_FRAC.value)

FP_MODE = True

W_HEIGHT = int(cocotb.top.W_HEIGHT.value)

pg.init()
font = pg.freetype.Font(
    "/usr/share/fonts/TTF/JetBrainsMonoNLNerdFont-Regular.ttf",
    24
)
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


def fixp(int_bits=W_INT, frac_bits=W_FRAC, val=0, signed=False):

    if type(val) is FpBinarySwitchable:
        return val.resize(
            format=(int_bits, frac_bits), round_mode=RoundingEnum.direct_neg_inf
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


# Player position
pos_x = fixp(val=10)
pos_y = fixp(val=10)

# Camera direction
dir_x = fixp(val=0.94, signed=True)
dir_y = fixp(val=-0.33, signed=True)

# Camera plane vector
plane_x = fixp(val=-0.22, signed=True)
plane_y = fixp(val=-0.62, signed=True)

time = 0
old_time = 0

ray_step = int(2.0 / FRAME_WIDTH * (2**(W_FRAC)))


def float_to_fixp(num_float):
    return int(num_float * (2 ** W_FRAC))


def fixp_to_float(num_fixp):
    return float(num_fixp) / (2 ** W_FRAC)


async def newton_inv(dut, recip):
    await RisingEdge(dut.clk)
    dut.start_i.value = 1
    dut.num_i.value = float_to_fixp(recip)

    await RisingEdge(dut.clk)
    dut.start_i.value = 0

    while not dut.done_o.value:
        await RisingEdge(dut.clk)

    return fixp_to_float(int(dut.num_o.value))


def inv_model(num):
    cnt = 0
    approx = fixp(val=1)
    product = fixp(val=0)
    sub = fixp(val=0)

    while num > 1:
        num = fixp(val=num / 2)
        cnt += 1

    for _ in range(8):
        product = fixp(val=num * approx)
        sub = fixp(val=2 - product)
        approx = fixp(val=approx * sub)

    approx = fixp(val=approx / (2**cnt))
    return approx


fixp_frame_height = fixp(val=FRAME_HEIGHT, int_bits=W_HEIGHT)


async def line_height_calc(dut, x):
    await RisingEdge(dut.clk)
    dut.start_i.value = 1
    dut.px_x_i.value = x
    dut.pos_x_i.value = float_to_fixp(pos_x)
    dut.pos_y_i.value = float_to_fixp(pos_y)
    dut.dir_x_i.value = float_to_fixp(dir_x)
    dut.dir_y_i.value = float_to_fixp(dir_y)
    dut.plane_x_i.value = float_to_fixp(plane_x)
    dut.plane_y_i.value = float_to_fixp(plane_y)

    await RisingEdge(dut.clk)
    dut.start_i.value = 0

    while not dut.done_o.value:
        await RisingEdge(dut.clk)

    if dut.ray_hit_side_o.value:
        line_color = (128, 128, 128)
    else:
        line_color = (255, 255, 255)

    return (int(dut.height_o.value), line_color)


perp_wall_dist = 0
inv_perp_wall_dist = 0
ray_x = 0
ray_dir_x = 0
ray_dir_y = 0
delta_dist_x = 0
delta_dist_y = 0
side_dist_x = 0
side_dist_y = 0
dda_side_dist_x = 0
dda_side_dist_y = 0
map_x = 0
map_y = 0


def line_height_calc_model(x):
    global ray_x
    global ray_dir_x
    global ray_dir_y
    global perp_wall_dist
    global inv_perp_wall_dist
    global delta_dist_x
    global delta_dist_y
    global side_dist_x
    global side_dist_y
    global dda_side_dist_x
    global dda_side_dist_y
    global map_x
    global map_y

    ray_x = fixp(val=(x * ray_step / 2**W_FRAC - 1), signed=True)

    ray_dir_x = fixp(val=dir_x + plane_x * ray_x, signed=True)
    ray_dir_y = fixp(val=dir_y + plane_y * ray_x, signed=True)

    if ray_dir_x == 0:
        delta_dist_x = fixp(val=2**(W_INT-1)-1)
    else:
        if ray_dir_x > 0:
            delta_dist_x = inv_model(ray_dir_x)
        else:
            delta_dist_x = inv_model(-ray_dir_x)

    if ray_dir_y == 0:
        delta_dist_y = fixp(val=2**(W_INT-1)-1)
    else:
        if ray_dir_y > 0:
            delta_dist_y = inv_model(ray_dir_y)
        else:
            delta_dist_y = inv_model(-ray_dir_y)

    map_x = int(pos_x)
    map_y = int(pos_y)

    if ray_dir_x > 0:
        step_x = 1
        side_dist_x = fixp(val=(map_x + 1 - pos_x) * delta_dist_x)
    else:
        step_x = -1
        side_dist_x = fixp(val=(pos_x - map_x) * delta_dist_x)

    if ray_dir_y > 0:
        step_y = 1
        side_dist_y = fixp(val=(map_y + 1 - pos_y) * delta_dist_y)
    else:
        step_y = -1
        side_dist_y = fixp(val=(pos_y - map_y) * delta_dist_y)

    hit_side = 0

    while True:
        if (side_dist_x < side_dist_y):
            side_dist_x = fixp(val=side_dist_x + delta_dist_x)
            map_x += step_x
            hit_side = 0
        else:
            side_dist_y = fixp(val=side_dist_y + delta_dist_y)
            map_y += step_y
            hit_side = 1

        if game_map[map_y][map_x] == 1:
            break

    if hit_side == 0:
        perp_wall_dist = fixp(val=side_dist_x - delta_dist_x)
        line_color = (255, 255, 255)
    else:
        perp_wall_dist = fixp(val=side_dist_y - delta_dist_y)
        line_color = (128, 128, 128)

    if perp_wall_dist == 0:
        inv_perp_wall_dist = 2**W_INT
    else:
        inv_perp_wall_dist = inv_model(perp_wall_dist)

    if int(inv_perp_wall_dist) == 0:
        scaled_height = fixp(
            val=fixp_frame_height * inv_perp_wall_dist, int_bits=W_HEIGHT+1
        )
        return (int(scaled_height), line_color)
    else:
        return (int(fixp_frame_height), line_color)


async def game(dut):
    """Game loop"""

    for x in range(FRAME_WIDTH):
        line_height_model, line_color_model = line_height_calc_model(x)
        line_height, line_color = await line_height_calc(dut, x)

        if abs(line_height - line_height_model) > 10:
            print("=" * 80)
            print(f"pixel {x}")
            print(f"Expected {line_height_model}, got: {line_height}")
            p_wall_dist = fixp_to_float(int(dut.line_height_calc.perp_wall_dist_ff.value))
            inv_p_wall_dist = fixp_to_float(int(dut.line_height_calc.inv_perp_wall_dist_ff.value))
            print(f"Model ray_dir_x: {ray_dir_x}")
            print(f"Model ray_dir_y: {ray_dir_y}\n")
            print(f"Model delta_dist_x: {delta_dist_x}")
            print(f"Model delta_dist_y: {delta_dist_y}\n")
            print(f"DUT perp_wall_dist: {p_wall_dist}")
            print(f"Model perp_wall_dist: {perp_wall_dist}\n")
            print(f"DUT inv_perp_wall_dist: {inv_p_wall_dist}")
            print(f"Model inv_perp_wall_dist: {inv_perp_wall_dist}")
            exit(0)

        start_pos = FRAME_HEIGHT // 2 - line_height // 2

        if start_pos < 0:
            start_pos = 0
        end_pos = FRAME_HEIGHT // 2 + line_height // 2

        if end_pos > FRAME_HEIGHT - 1:
            end_pos = FRAME_HEIGHT - 1

        pg.draw.line(surface, line_color, (x, start_pos), (x, end_pos))


def controls():
    global pos_x
    global pos_y
    global dir_x
    global dir_y
    global plane_x
    global plane_y
    global time
    global old_time

    old_time = time
    time = pg.time.get_ticks()
    frame_time = (time - old_time) / 1000.0
    move_speed = 0.3 * 4.0
    rot_speed = 0.3 * 2.0
    fps = 1 / frame_time
    font.render_to(surface, (20, 20), f"FPS: {str(fps)}", (0, 255, 0))
    font.render_to(surface, (20, 50), f"pos_x: {pos_x}", (0, 255, 0))
    font.render_to(surface, (20, 80), f"pos_y: {pos_y}", (0, 255, 0))
    font.render_to(surface, (20, 110), f"plane_x: {plane_x}", (0, 255, 0))
    font.render_to(surface, (20, 140), f"plane_y: {plane_y}", (0, 255, 0))
    font.render_to(surface, (20, 170), f"dir_x: {dir_x}", (0, 255, 0))
    font.render_to(surface, (20, 200), f"dir_y: {dir_y}", (0, 255, 0))

    for event in pg.event.get():
        if event.type == pg.KEYDOWN:
            if event.key == pg.K_q:
                quit()

    keys = pg.key.get_pressed()
    # Forward
    if keys[pg.K_w]:
        if game_map[int(pos_y)][int(pos_x + dir_x * move_speed)] != 1:
            pos_x = fixp(val=pos_x + dir_x * move_speed)
        if game_map[int(pos_y + dir_y * move_speed)][int(pos_x)] != 1:
            pos_y = fixp(val=pos_y + dir_y * move_speed)
    # Backwards
    if keys[pg.K_s]:
        if game_map[int(pos_y)][int(pos_x - dir_x * move_speed)] != 1:
            pos_x = fixp(val=pos_x - dir_x * move_speed)
        if game_map[int(pos_y - dir_y * move_speed)][int(pos_x)] != 1:
            pos_y = fixp(val=pos_y - dir_y * move_speed)
    # Rotate right
    if keys[pg.K_d]:
        old_dir_x = fixp(val=dir_x, signed=True)
        dir_x = fixp(
            val=dir_x * math.cos(-rot_speed) - dir_y * math.sin(-rot_speed), signed=True
        )
        dir_y = fixp(
            val=old_dir_x * math.sin(-rot_speed) + dir_y * math.cos(-rot_speed), signed=True
        )
        old_plane_x = fixp(val=plane_x, signed=True)
        plane_x = fixp(
            val=plane_x * math.cos(-rot_speed) - plane_y * math.sin(-rot_speed), signed=True
        )
        plane_y = fixp(
            val=old_plane_x * math.sin(-rot_speed) + plane_y * math.cos(-rot_speed),
            signed=True,
        )
    # Rotate left
    if keys[pg.K_a]:
        old_dir_x = fixp(val=dir_x, signed=True)
        dir_x = fixp(val=dir_x * math.cos(rot_speed) - dir_y * math.sin(rot_speed), signed=True)
        dir_y = fixp(val=old_dir_x * math.sin(rot_speed) + dir_y * math.cos(rot_speed), signed=True)
        old_plane_x = fixp(val=plane_x, signed=True)
        plane_x = fixp(val=plane_x * math.cos(rot_speed) - plane_y * math.sin(rot_speed), signed=True)
        plane_y = fixp(val=old_plane_x * math.sin(rot_speed) + plane_y * math.cos(rot_speed), signed=True)


def quit():
    pg.quit()
    cocotb.pass_test("Quit action")


async def dut_reset(dut):
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0


@cocotb.test()
async def run_raycast(dut):
    # Clock(dut.clk, 1, "ns").start()
    cocotb.start_soon(dut_reset(dut))
    while True:
        await game(dut)
        controls()
        pg.display.update()
        surface.fill((0, 0, 0))
