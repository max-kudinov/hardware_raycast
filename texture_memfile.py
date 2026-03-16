from PIL import Image

texture = Image.open("textures/wall_vines3.png", mode="r").convert("RGB")

colors = list()
color_lut = dict()
texture_recoded = list()

for y in range(32):
    for x in range(32):
        color = texture.getpixel((x, y))

        if color not in colors:
            colors.append(color)

for addr, col in enumerate(colors):
    r, g, b = col
    print(f"Address: {addr}, color: 8'd{r}, 8'd{g}, 8'd{b}")
    color_lut[col] = addr

print()

for y in range(32):
    recoded_row = list()
    for x in range(32):
        color = texture.getpixel((x, y))
        recoded_row.append(color_lut[color])

    texture_recoded.append(recoded_row)


for y in range(32):
    print("{ ", end="")
    for x in range(31, -1, -1):
        print(f"4'd{texture_recoded[y][x]}", end="")
        if x != 0:
            print(", ", end="")

    print(" }", end="")
    print()
