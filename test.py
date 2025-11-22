import math
import pygame as pg

FRAME_WIDTH = 1280
FRAME_HEIGHT = 720

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

ray_dir_x_max = 0
ray_dir_y_max = 0


def newton_inv(recip):

    cnt = 0
    while (recip > 1.0):
        recip /= 2
        cnt += 1

    guess = 1

    for _ in range(6):
        guess = guess * (2 - recip * guess)

    return guess / 2**cnt


def calc_ray(x):
    global ray_dir_x_max
    global ray_dir_y_max
    ray_x = (x*0.0015) - 1
    ray_dir_x = dir_x + plane_x * ray_x
    ray_dir_y = dir_y + plane_y * ray_x

    if abs(ray_dir_x) > ray_dir_x_max:
        ray_dir_x_max = abs(ray_dir_x)

    if abs(ray_dir_y) > ray_dir_y_max:
        ray_dir_y_max = abs(ray_dir_y)

    delta_dist_x = 1e30 if ray_dir_x == 0 else newton_inv(abs(ray_dir_x))
    delta_dist_y = 1e30 if ray_dir_y == 0 else newton_inv(abs(ray_dir_y))

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

    return (int(FRAME_HEIGHT * newton_inv(perp_wall_dist)), line_color)


def game():
    """Game loop"""
    global pos_x
    global pos_y
    global dir_x
    global dir_y
    global plane_x
    global plane_y
    global time
    global old_time

    for x in range(FRAME_WIDTH):
        line_height, line_color = calc_ray(x)
        start_pos = FRAME_HEIGHT // 2 - line_height // 2

        if start_pos < 0:
            start_pos = 0
        end_pos = FRAME_HEIGHT // 2 + line_height // 2

        if end_pos > FRAME_HEIGHT - 1:
            end_pos = FRAME_HEIGHT - 1

        pg.draw.line(surface, line_color, (x, start_pos), (x, end_pos))

    old_time = time
    time = pg.time.get_ticks()
    frame_time = (time - old_time) / 1000.0
    move_speed = frame_time * 4.0
    rot_speed = frame_time * 2.0
    fps = 1 / frame_time
    font.render_to(surface, (20, 20), str(fps), (255, 255, 255))

    font.render_to(surface, (20, 50), f"ray_dir_x_max: {ray_dir_x_max}", (255, 255, 255))
    font.render_to(surface, (20, 80), f"ray_dir_y_max: {ray_dir_y_max}", (255, 255, 255))
    font.render_to(surface, (20, 110), f"pos_x: {pos_x}", (255, 255, 255))
    font.render_to(surface, (20, 140), f"pos_y: {pos_y}", (255, 255, 255))
    font.render_to(surface, (20, 200), f"line_height: {line_height}", (255, 255, 255))

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


while True:
    game()
    pg.display.update()
    surface.fill((0, 0, 0))


def quit():
    pg.quit()
