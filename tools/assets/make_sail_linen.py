#!/usr/bin/env python3
"""Cut the sailcloth swatch that SailCanvas stretches over its drawn sail.

    python3 tools/assets/make_sail_linen.py

The sail is drawn rather than blitted, because the only raster sail master in
the project is a side elevation and this game looks at its ships from directly
overhead — see `src/entities/ships/sail_canvas.gd` for the whole story. But a
flat cream polygon sitting on a hull that is a rendered, weathered, softly lit
3D asset reads as two different games on one ship, and no amount of tuning the
*shape* fixes a mismatch of *material*.

What that master does have is a large field of beautifully rendered canvas: real
weave, sun on the folds, the grubby warmth the art bible asks for. That part is
projection-independent — cloth looks like cloth from any angle — so it is the one
piece of the elevation worth keeping. This lifts a clean patch of it out of the
left panel, away from the mast, the rope hanks, the bolt ropes and the reef
points, and box-filters it down to a tile the renderer can stretch over a
bellying polygon.

Deterministic and safe to re-run: same crop, same filter, same bytes out.

Pure stdlib on purpose. Every other asset step in this repo needs Godot or
nothing at all, and adding Pillow to build one 256×256 texture is not a trade
worth making.
"""

import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "assets_src/ships/sloop/v2/sail_med_master.png"
OUT = ROOT / "assets/wave1/ships/sail_linen.png"

# The clean patch, in master pixels. The master is 1254 square; the left canvas
# panel runs roughly x 150..570, and these bounds sit inside it with room to
# spare on every side. Verified by sampling: fully opaque, no rope, no batten,
# no mast shadow.
CROP = (190, 545, 560, 955)

SIZE = 256

# The patch is lit from the upper left in the master, so it carries a gradient of
# its own. Left in deliberately — a sail with even lighting looks like paper —
# but flattened toward the mean so the renderer's own shading is what leads and
# this only supplies the grain.
FLATTEN = 0.55


def read_png(path: Path) -> tuple[int, int, list[bytes]]:
    data = path.read_bytes()
    pos, idat, width, height, colour = 8, b"", 0, 0, 6
    while pos < len(data):
        length = int.from_bytes(data[pos:pos + 4], "big")
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            width = int.from_bytes(body[0:4], "big")
            height = int.from_bytes(body[4:8], "big")
            if body[8] != 8:
                sys.exit("master is not 8 bits per channel")
            colour = body[9]
        elif kind == b"IDAT":
            idat += body
        pos += 12 + length

    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(idat)
    stride = width * channels
    previous = bytearray(stride)
    rows: list[bytes] = []
    at = 0
    for _ in range(height):
        filter_type = raw[at]
        at += 1
        line = bytearray(raw[at:at + stride])
        at += stride
        if filter_type:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                up = previous[x]
                up_left = previous[x - channels] if x >= channels else 0
                if filter_type == 1:
                    line[x] = (line[x] + left) & 255
                elif filter_type == 2:
                    line[x] = (line[x] + up) & 255
                elif filter_type == 3:
                    line[x] = (line[x] + (left + up) // 2) & 255
                elif filter_type == 4:
                    guess = left + up - up_left
                    dl, du, dul = (
                        abs(guess - left), abs(guess - up), abs(guess - up_left)
                    )
                    if dl <= du and dl <= dul:
                        line[x] = (line[x] + left) & 255
                    elif du <= dul:
                        line[x] = (line[x] + up) & 255
                    else:
                        line[x] = (line[x] + up_left) & 255
        rows.append(bytes(line))
        previous = line
    return width, height, rows


def write_png(path: Path, width: int, height: int, rows: list[bytes]) -> None:
    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body)) + kind + body
            + struct.pack(">I", zlib.crc32(kind + body))
        )

    raw = b"".join(b"\x00" + row for row in rows)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main() -> None:
    if not MASTER.exists():
        sys.exit(f"missing master: {MASTER}")

    width, _height, rows = read_png(MASTER)
    x0, y0, x1, y1 = CROP
    span_x, span_y = x1 - x0, y1 - y0

    # Box filter: every output texel averages the whole master rectangle that
    # falls under it, so the weave survives the reduction instead of aliasing
    # into a moire pattern the way point sampling would.
    pixels: list[list[int]] = []
    for oy in range(SIZE):
        sy0 = y0 + (oy * span_y) // SIZE
        sy1 = max(sy0 + 1, y0 + ((oy + 1) * span_y) // SIZE)
        row: list[int] = []
        for ox in range(SIZE):
            sx0 = x0 + (ox * span_x) // SIZE
            sx1 = max(sx0 + 1, x0 + ((ox + 1) * span_x) // SIZE)
            r = g = b = n = 0
            for sy in range(sy0, sy1):
                line = rows[sy]
                for sx in range(sx0, sx1):
                    at = sx * 4
                    if line[at + 3] < 250:
                        continue
                    r += line[at]
                    g += line[at + 1]
                    b += line[at + 2]
                    n += 1
            if n == 0:
                sys.exit(f"crop hit transparent pixels at {ox},{oy} — move CROP")
            row += [r // n, g // n, b // n]
        pixels.append(row)

    totals = [0, 0, 0]
    for row in pixels:
        for i in range(0, len(row), 3):
            totals[0] += row[i]
            totals[1] += row[i + 1]
            totals[2] += row[i + 2]
    count = SIZE * SIZE
    mean = [t / count for t in totals]

    out: list[bytes] = []
    for row in pixels:
        line = bytearray()
        for i in range(0, len(row), 3):
            for c in range(3):
                flat = mean[c] + (row[i + c] - mean[c]) * FLATTEN
                line.append(max(0, min(255, round(flat))))
            line.append(255)
        out.append(bytes(line))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    write_png(OUT, SIZE, SIZE, out)
    print(
        "%s — %d×%d from %s, mean rgb %d,%d,%d"
        % (
            OUT.relative_to(ROOT), SIZE, SIZE, MASTER.name,
            round(mean[0]), round(mean[1]), round(mean[2]),
        )
    )


main()
