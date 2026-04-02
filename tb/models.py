import math
import cocotb
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

# fixp_pkg types
fixp_ray = get_type_spec(fixp_pkg, "RAY")
fixp_pos = get_type_spec(fixp_pkg, "POS")
fixp_ext_pos = get_type_spec(fixp_pkg, "EXT_POS")
fixp_inv_dist = get_type_spec(fixp_pkg, "INV_DIST")
fixp_inv = get_type_spec(fixp_pkg, "INV")

# tex_pkg types
fixp_tex_zoom = get_type_spec(tex_pkg, "TEX_ZOOM")
fixp_tex_step = get_type_spec(tex_pkg, "TEX_STEP")

FRAME_WIDTH = int(dvi_pkg.FRAME_WIDTH.value)
FRAME_HEIGHT = int(dvi_pkg.FRAME_HEIGHT.value)
W_HEIGHT = int(dvi_pkg.W_V_RES.value)
MOVEMENT_SPEED = float(cocotb.top.MOVEMENT_SPEED.value)
ROTATION_SPEED = float(cocotb.top.ROTATION_SPEED.value)
INV_ITER_NUM = int(fixp_pkg.INV_ITER_NUM.value)
PLANE_COEFF = float(cocotb.top.raycast_top.controls.rotation.PLANE_COEFF.value)
FIXP_MULT_COEFF = fixp_init(PLANE_COEFF, fixp_ray, True)
TEX_SIDE = int(tex_pkg.TEX_SIDE.value)

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


def get_model_state():
    state_dict = dict()
    state_dict["pos_x"] = pos_x
    state_dict["pos_y"] = pos_y
    state_dict["dir_x"] = dir_x
    state_dict["dir_y"] = dir_y
    state_dict["plane_x"] = plane_x
    state_dict["plane_y"] = plane_y
    return state_dict


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


def column_calc_model(x, game_map):
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
    texture = int(game_map[map_y][map_x]) - 1

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
        return (texture, tex_shade, tex_x, tex_step, FRAME_HEIGHT // 2)
    else:
        scaled_height = fixp_init(
            FRAME_HEIGHT * inv_wall_dist, (W_HEIGHT, 0)
        )
        return (texture, tex_shade, tex_x, tex_step, int(scaled_height) // 2)


def render_model(
    textures, px_y, texture, tex_shade, tex_x, tex_step, tex_height
):
    in_texture = False

    if px_y < FRAME_HEIGHT // 2:
        px_color = (20, 20, 20)
    else:
        px_color = (48, 48, 48)

    tex_start = FRAME_HEIGHT // 2 - tex_height
    tex_end = FRAME_HEIGHT // 2 + tex_height

    if px_y >= tex_start and px_y < tex_end:
        in_texture = True

        if tex_step < tex_step_scale:
            tex_zoom = fixp_init(
                TEX_SIDE // 2
                - fixp_init(
                    FRAME_HEIGHT // 2 * tex_step, fixp_tex_zoom
                ),
                fixp_tex_zoom,
            )
        else:
            tex_zoom = fixp_init(0, fixp_tex_zoom)

        tex_align = px_y - tex_start
        tex_align_ext = fixp_init(tex_align / 2**3, (6, 12))
        tex_align_scaled = fixp_init(0, (6, 12))
        tex_align_scaled = fixp_expr(
            tex_align_ext * tex_step, tex_align_scaled
        )
        raw_y_pos = fixp_init(
            tex_zoom + (tex_align_scaled << 3), (6, 12)
        )

        tex_y = min(31, int(raw_y_pos))
        px_color = textures[texture].getpixel((tex_x, tex_y))
        r, g, b = px_color

        if tex_shade:
            px_color = (r >> 1, g >> 1, b >> 1)
        else:
            px_color = (r, g, b)

    return px_color, in_texture


def controls_model(
    forward, backward, left, right, rotate_right, rotate_left, game_map
):
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
    if forward:
        update_pos(dir_x, 1)
    if backward:
        update_pos(-dir_x, 1)
    if left:
        update_pos(-dir_y, 1)
    if right:
        update_pos(dir_y, 1)

    # Update y axis
    if forward:
        update_pos(dir_y, 0)
    if backward:
        update_pos(-dir_y, 0)
    if left:
        update_pos(dir_x, 0)
    if right:
        update_pos(-dir_x, 0)

    def rotate(direction):
        global dir_x
        global dir_y
        global plane_x
        global plane_y

        if direction:
            cos = cos_angle
            sin = sin_angle
        else:
            cos = cos_neg_angle
            sin = sin_neg_angle

        old_dir_x = fixp_init(dir_x, fixp_ray, True)
        dir_x = fixp_cast(
            fixp_cast(dir_x * cos, fixp_ray)
            - fixp_cast(dir_y * sin, fixp_ray),
            fixp_ray,
        )
        dir_y = fixp_cast(
            fixp_cast(old_dir_x * sin, fixp_ray)
            + fixp_cast(dir_y * cos, fixp_ray),
            fixp_ray,
        )

        plane_x = fixp_cast(dir_y * FIXP_MULT_COEFF, fixp_ray)
        plane_y = fixp_cast(
            -fixp_cast(dir_x * FIXP_MULT_COEFF, fixp_ray), fixp_ray
        )

    if rotate_right:
        rotate(0)

    if rotate_left:
        rotate(1)


def convert_state_to_float():
    global pos_x, pos_y, dir_x, dir_y, plane_x, plane_y
    pos_x = float(pos_x)
    pos_y = float(pos_y)
    dir_x = float(dir_x)
    dir_y = float(dir_y)
    plane_x = float(plane_x)
    plane_y = float(plane_y)


def controls_float(
    forward, backward, left, right, rotate_right, rotate_left, game_map
):
    def update_pos(dir, is_x):
        global pos_x, pos_y

        if is_x:
            update_axis = pos_x
        else:
            update_axis = pos_y

        new_pos = update_axis + dir * MOVEMENT_SPEED

        if is_x and int(game_map[int(pos_y)][int(new_pos)] == 0):
            pos_x = new_pos
        if not is_x and int(game_map[int(new_pos)][int(pos_x)] == 0):
            pos_y = new_pos

    # Update x axis
    if forward:
        update_pos(dir_x, 1)
        update_pos(dir_y, 0)
    if backward:
        update_pos(-dir_x, 1)
        update_pos(-dir_y, 0)
    if left:
        update_pos(-dir_y, 1)
        update_pos(dir_x, 0)
    if right:
        update_pos(dir_y, 1)
        update_pos(-dir_x, 0)

    def rotate(angle):
        global dir_x, dir_y, plane_x, plane_y
        old_dir_x = dir_x
        dir_x = dir_x * math.cos(angle) - dir_y * math.sin(angle)
        dir_y = old_dir_x * math.sin(angle) + dir_y * math.cos(angle)
        old_plane_x = plane_x
        plane_x = plane_x * math.cos(angle) - plane_y * math.sin(angle)
        plane_y = old_plane_x * math.sin(angle) + plane_y * math.cos(angle)

    if rotate_right:
        rotate(-ROTATION_SPEED)

    if rotate_left:
        rotate(ROTATION_SPEED)


def float_model(game_map, textures, surface):
    for x in range(0, FRAME_WIDTH):
        ray_x = 2 * x / FRAME_WIDTH - 1
        ray_dir_x = dir_x + plane_x * ray_x
        ray_dir_y = dir_y + plane_y * ray_x

        delta_dist_x = 1e30 if ray_dir_x == 0 else 1 / abs(ray_dir_x)
        delta_dist_y = 1e30 if ray_dir_y == 0 else 1 / abs(ray_dir_y)

        wall_dist = 0
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
            if int(game_map[map_y][map_x]):
                break

            if side_dist_x < side_dist_y:
                hit_side = 0
                side_dist_x += delta_dist_x
                map_x += step_x
            else:
                hit_side = 1
                side_dist_y += delta_dist_y
                map_y += step_y

        texture = int(game_map[map_y][map_x]) - 1

        if hit_side == 0:
            wall_dist = side_dist_x - delta_dist_x
            tex_shade = 0
        else:
            wall_dist = side_dist_y - delta_dist_y
            tex_shade = 1

        if wall_dist == 0:
            tex_height = FRAME_HEIGHT
        else:
            tex_height = FRAME_HEIGHT / wall_dist

        tex_step = wall_dist * TEX_SIDE / FRAME_HEIGHT

        if hit_side == 0:
            coord_x = wall_dist * ray_dir_y + pos_y
        else:
            coord_x = wall_dist * ray_dir_x + pos_x

        tex_x = int((coord_x - math.floor(coord_x)) * TEX_SIDE)

        if hit_side == 0 and ray_dir_x > 0:
            tex_x = TEX_SIDE - 1 - tex_x
        if hit_side == 1 and ray_dir_y < 0:
            tex_x = TEX_SIDE - 1 - tex_x

        tex_start = FRAME_HEIGHT // 2 - tex_height // 2
        tex_end = FRAME_HEIGHT // 2 + tex_height // 2

        for y in range(FRAME_HEIGHT):
            if y >= tex_start and y < tex_end:
                raw_y_pos = (y - tex_start) * tex_step
                tex_y = min(TEX_SIDE - 1, int(raw_y_pos))

                px_color = textures[texture].getpixel((tex_x, tex_y))
                r, g, b = px_color
                if tex_shade:
                    px_color = (r >> 1, g >> 1, b >> 1)
                else:
                    px_color = (r, g, b)

                surface.set_at((x, y), px_color)
