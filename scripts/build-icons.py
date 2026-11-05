"""assets-src/iconsの原画から、アプリアイコンとグリフを生成する。

実行: uv run --no-project --with pillow python scripts/build-icons.py
"""

import subprocess
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "assets-src" / "icons"
RESOURCES_DIR = ROOT / "Resources"
GLYPHS_DIR = RESOURCES_DIR / "glyphs"

# macOS 26は全面不透明のアイコンをOSの形に切り抜く。透明な余白や角丸を付けると、灰色のタイルの中に縮小して表示する。
ICON_SIZE = 1024
ICONSET_ENTRIES = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

GLYPH_SIZE = 18
# 原画の白地には255に届かない画素が散っている。インクの有無はこの輝度で判定する。
INK_LUMINANCE = 128
# これ未満のアルファは原画のノイズとして0にする。縮小後に薄い汚れとして残らないようにする。
NOISE_ALPHA = 16
# 隙間は中央付近を探す。外側の余白を区切りと取り違えないようにする。
GAP_SEARCH_RANGE = (0.25, 0.75)
# 原画の並びは左上、右上、左下、右下。
GLYPH_NAMES = ["menubar", "tab-resources", "tab-processes", "tab-apps"]


def build_app_icon() -> None:
    raw = Image.open(SOURCE_DIR / "app_raw.png").convert("RGB")
    canvas = raw.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS)

    with tempfile.TemporaryDirectory() as temp:
        iconset = Path(temp) / "AppIcon.iconset"
        iconset.mkdir()
        for name, size in ICONSET_ENTRIES:
            canvas.resize((size, size), Image.LANCZOS).save(iconset / name)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(RESOURCES_DIR / "AppIcon.icns")],
            check=True,
        )


def find_gap_center(has_ink: list[bool]) -> int:
    """インクのない連続区間のうち、探索範囲で最も長いものの中央を返す。"""
    start = int(len(has_ink) * GAP_SEARCH_RANGE[0])
    end = int(len(has_ink) * GAP_SEARCH_RANGE[1])
    best_start, best_length = None, 0
    run_start = None
    for index in range(start, end + 1):
        if index < end and not has_ink[index]:
            if run_start is None:
                run_start = index
            continue
        if run_start is not None and index - run_start > best_length:
            best_start, best_length = run_start, index - run_start
        run_start = None
    if best_start is None:
        raise ValueError("グリフの間に白い隙間が見つかりません")
    return best_start + best_length // 2


def build_glyphs() -> None:
    gray = Image.open(SOURCE_DIR / "glyphs_raw.png").convert("L")
    ink = gray.point(lambda value: 255 if value < INK_LUMINANCE else 0)
    pixels = ink.load()
    width, height = ink.size

    columns = [any(pixels[x, y] for y in range(height)) for x in range(width)]
    rows = [any(pixels[x, y] for x in range(width)) for y in range(height)]
    split_x = find_gap_center(columns)
    split_y = find_gap_center(rows)

    boxes = [
        (0, 0, split_x, split_y),
        (split_x, 0, width, split_y),
        (0, split_y, split_x, height),
        (split_x, split_y, width, height),
    ]

    GLYPHS_DIR.mkdir(exist_ok=True)
    for name, box in zip(GLYPH_NAMES, boxes):
        alpha = gray.crop(box).point(lambda value: 255 - value if 255 - value >= NOISE_ALPHA else 0)
        # 余白の判定はインクだけで行う。インクの周りのにじみまで含めると、余白が残る。
        tight = alpha.crop(ink.crop(box).getbbox())

        side = max(tight.size)
        square = Image.new("L", (side, side), 0)
        square.paste(tight, ((side - tight.width) // 2, (side - tight.height) // 2))

        for scale, suffix in [(1, ""), (2, "@2x")]:
            size = GLYPH_SIZE * scale
            resized_alpha = square.resize((size, size), Image.LANCZOS)
            glyph = Image.new("RGBA", (size, size), (0, 0, 0, 255))
            glyph.putalpha(resized_alpha)
            glyph.save(GLYPHS_DIR / f"{name}{suffix}.png")


def main() -> None:
    build_app_icon()
    build_glyphs()


if __name__ == "__main__":
    main()
