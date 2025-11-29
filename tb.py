import math
import pygame as pg
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge

FRAME_WIDTH = 640
FRAME_HEIGHT = 480

MAP_WIDTH = 20
MAP_HEIGHT = 20

pg.init()
font = pg.freetype.Font("/usr/share/fonts/TTF/JetBrainsMonoNLNerdFont-Regular.ttf", 24)
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

# Player position
pos_x = 10
pos_y = 10

# Camera direction
dir_x = -1
dir_y = 0

# Camera plane vector
plane_x = 0
plane_y = 0.66

time = 0
old_time = 0


def float_to_fixp(num_float):
    frac_bits = int(cocotb.packages.fixedpoint.W_FRAC.value)

    return int(num_float * (2 ** frac_bits))


def fixp_to_float(num_fixp):
    frac_bits = int(cocotb.packages.fixedpoint.W_FRAC.value)

    return float(num_fixp) / (2 ** frac_bits)


async def newton_inv(dut, recip):
    await RisingEdge(dut.clk)
    dut.start_i.value = 1
    dut.num_i.value = float_to_fixp(recip)

    await RisingEdge(dut.clk)
    dut.start_i.value = 0

    while not dut.done_o.value:
        await RisingEdge(dut.clk)

    return fixp_to_float(int(dut.num_o.value))


async def line_height_calc(dut, x):
    ray_step = float_to_fixp(2 / FRAME_WIDTH)
    ray = x * ray_step - 1
    ray_x = fixp_to_float(ray)
    ray_dir_x = dir_x + plane_x * ray_x
    ray_dir_y = dir_y + plane_y * ray_x

    delta_dist_x = 1e30 if float_to_fixp(ray_dir_x) == 0 else await newton_inv(dut, abs(ray_dir_x))
    delta_dist_y = 1e30 if float_to_fixp(ray_dir_y) == 0 else await newton_inv(dut, abs(ray_dir_y))

    perp_wall_dist = 0
    map_x = int(pos_x)
    map_y = int(pos_y)

    if ray_dir_x > 0:
        step_x = 1
        side_dist_x = (map_x + 1 - pos_x) * delta_dist_x
    else:
        step_x = -1
        side_dist_x = (pos_x - map_x) * delta_dist_x

    if ray_dir_y > 0:
        step_y = 1
        side_dist_y = (map_y + 1 - pos_y) * delta_dist_y
    else:
        step_y = -1
        side_dist_y = (pos_y - map_y) * delta_dist_y

    hit_side = 0

    while True:
        if (side_dist_x < side_dist_y):
            side_dist_x += delta_dist_x
            map_x += step_x
            hit_side = 0
        else:
            side_dist_y += delta_dist_y
            map_y += step_y
            hit_side = 1

        if game_map[map_x][map_y] == 1:
            break

    if hit_side == 0:
        perp_wall_dist = side_dist_x - delta_dist_x
        line_color = (255, 255, 255)
    else:
        perp_wall_dist = side_dist_y - delta_dist_y
        line_color = (128, 128, 128)

    if float_to_fixp(perp_wall_dist) == 0:
        return (FRAME_HEIGHT, line_color)
    else:
        return (int(FRAME_HEIGHT * await newton_inv(dut, perp_wall_dist)), line_color)


async def game(dut):
    """Game loop"""

    for x in range(FRAME_WIDTH):
        line_height, line_color = await line_height_calc(dut, x)
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
    font.render_to(surface, (20, 20), str(fps), (255, 255, 255))

    font.render_to(surface, (20, 110), f"pos_x: {pos_x}", (255, 255, 255))
    font.render_to(surface, (20, 140), f"pos_y: {pos_y}", (255, 255, 255))
    font.render_to(surface, (20, 170), f"frame_time: {frame_time}", (255, 255, 255))

    for event in pg.event.get():
        if event.type == pg.KEYDOWN:
            if event.key == pg.K_q:
                quit()

    keys = pg.key.get_pressed()
    # Forward
    if keys[pg.K_w]:
        if game_map[int(pos_x + dir_x * move_speed)][int(pos_y)] != 1:
            pos_x += round(dir_x * move_speed, 2)
        if game_map[int(pos_x)][int(pos_y + dir_y * move_speed)] != 1:
            pos_y += round(dir_y * move_speed, 2)
    # Backwards
    if keys[pg.K_s]:
        if game_map[int(pos_x - dir_x * move_speed)][int(pos_y)] != 1:
            pos_x -= round(dir_x * move_speed, 2)
        if game_map[int(pos_x)][int(pos_y - dir_y * move_speed)] != 1:
            pos_y -= round(dir_y * move_speed, 2)
    # Rotate right
    if keys[pg.K_d]:
        old_dir_x = dir_x
        dir_x = dir_x * math.cos(-rot_speed) - dir_y * math.sin(-rot_speed)
        dir_y = old_dir_x * math.sin(-rot_speed) + dir_y * math.cos(-rot_speed)
        old_plane_x = plane_x
        plane_x = plane_x * math.cos(-rot_speed) - plane_y * math.sin(-rot_speed)
        plane_y = old_plane_x * math.sin(-rot_speed) + plane_y * math.cos(-rot_speed)
    # Rotate left
    if keys[pg.K_a]:
        old_dir_x = dir_x
        dir_x = dir_x * math.cos(rot_speed) - dir_y * math.sin(rot_speed)
        dir_y = old_dir_x * math.sin(rot_speed) + dir_y * math.cos(rot_speed)
        old_plane_x = plane_x
        plane_x = plane_x * math.cos(rot_speed) - plane_y * math.sin(rot_speed)
        plane_y = old_plane_x * math.sin(rot_speed) + plane_y * math.cos(rot_speed)


def quit():
    pg.quit()
    cocotb.pass_test("Quit action")


async def dut_reset(dut):
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    dut.rst.value = 0


@cocotb.test()
async def run_raycast(dut):
    Clock(dut.clk, 1, "ns").start()
    cocotb.start_soon(dut_reset(dut))
    while True:
        await game(dut)
        controls()
        pg.display.update()
        surface.fill((0, 0, 0))
