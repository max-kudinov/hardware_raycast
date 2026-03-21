import os
from PIL import Image

TEX_SIDE = 32
RECODE_LUT_LEN = 15

tex_images = [
    "wall_vines3.png",
    "volcanic_wall0.png",
    "lair1.png",
    "relief3.png",
    "crystal_wall10.png",
    "brick_gray2.png",
    "lava3.png",
]

try:
    os.remove("memfiles/recode_lut.mem")
    os.remove("memfiles/textures.mem")
except OSError:
    pass

textures = list()

for image in tex_images:
    textures.append(Image.open(f"textures/{image}").convert("RGB"))

for texture in textures:
    colors = list()
    color_lut = dict()
    texture_recoded = list()

    for y in range(TEX_SIDE):
        for x in range(TEX_SIDE):
            color = texture.getpixel((x, y))

            if color not in colors:
                colors.append(color)

    with open("memfiles/recode_lut.mem", "a") as f:
        for addr, col in enumerate(colors):
            r, g, b = col
            f.write(f"{(r << 16) + (g << 8) + b:x}\n")
            color_lut[col] = addr

        for _ in range(RECODE_LUT_LEN - len(colors)):
            f.write("0\n")

    for y in range(TEX_SIDE):
        recoded_row = list()
        for x in range(TEX_SIDE):
            color = texture.getpixel((x, y))
            recoded_row.append(color_lut[color])

        texture_recoded.append(recoded_row)

    with open("memfiles/textures.mem", "a") as f:
        for y in range(TEX_SIDE):
            for x in range(TEX_SIDE):
                f.write(f"{texture_recoded[y][x]:x}")
                if x != TEX_SIDE-1:
                    f.write(" ")
            f.write("\n")
