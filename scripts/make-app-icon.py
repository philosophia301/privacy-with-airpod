#!/usr/bin/env python3
"""원본 아기상어 그림으로 앱 아이콘 Resources/AppIcon.icns를 만듦.

캐릭터는 다시 그리지 않음. 원본을 키워 캐릭터만 오려 단색 배경에 놓고,
앱의 가변 블러처럼 오른쪽으로 갈수록 흐리게 함. 같은 입력이면 같은 결과가 나옴.

사용법:
  scripts/make-app-icon.py [--png PATH]

--png PATH는 1024px 원본 PNG도 함께 저장함(검토용).
필요: Pillow, numpy, macOS iconutil.
"""
import argparse
import pathlib
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs/assets/app-icon/baby-shark-source.png"
OUTPUT = ROOT / "Resources/AppIcon.icns"

# 2026-11-11 사용자가 고른 값. 결정 정본은 docs/spec.md의 앱 아이콘 절임.
BACKGROUND = (0xFF, 0xE0, 0x43)   # 캐릭터 몸과 같은 노랑
BLUR_START, BLUR_END = 0.29, 0.86  # 아이콘 몸통 너비 대비 흐림 시작과 최대 지점
BLUR_MAX_RADIUS = 64               # 작업 해상도(2048) 기준, 1024px에서 32px

SEGMENT_SCALE = 4   # 마스크를 만드는 배율
OUTLINE_PX = 7      # 원본 기준 외곽선과 그 안쪽 흰 띠의 두께
CHAR_SCALE = 8      # 오린 캐릭터의 배율

WORK = 2048         # 작업 해상도. 마지막에 1024로 줄임
BODY = 1648         # macOS 아이콘 템플릿의 둥근 사각형(1024 기준 824)
OFF = (WORK - BODY) // 2
RADIUS = 370


def as_image(mask: np.ndarray) -> Image.Image:
    return Image.fromarray((mask * 255).astype(np.uint8)).copy()


def flood(free: np.ndarray, seeds) -> np.ndarray:
    """free 안에서 seeds와 이어진 곳."""
    image = as_image(free)
    for x, y in seeds:
        if image.getpixel((x, y)) == 255:
            ImageDraw.floodfill(image, (x, y), 128, thresh=0)
    return np.asarray(image) == 128


def grow_round(mask: np.ndarray, steps: int) -> np.ndarray:
    """정사각형과 십자 팽창을 번갈아 원에 가깝게 넓힘."""
    current = mask.copy()
    for step in range(steps):
        if step % 2 == 0:
            current = np.asarray(as_image(current).filter(ImageFilter.MaxFilter(3))) > 0
        else:
            grown = current.copy()
            grown[1:, :] |= current[:-1, :]
            grown[:-1, :] |= current[1:, :]
            grown[:, 1:] |= current[:, :-1]
            grown[:, :-1] |= current[:, 1:]
            current = grown
    return current


def character_mask(source: Image.Image) -> Image.Image:
    """캐릭터만 덮는 마스크.

    캐릭터 외곽선은 뒤의 물결, 체크무늬와 같은 갈색이라 색만으로 나눌 수 없음.
    노란 면과 배의 흰 면에서 외곽선 두께까지만 넓히고, 가장자리와 이어진 바깥과 물결 안쪽 색은 뺌.
    """
    scaled = source.resize((source.width * SEGMENT_SCALE, source.height * SEGMENT_SCALE), Image.LANCZOS)
    pixels = np.asarray(scaled).astype(int)
    r, g, b = pixels[..., 0], pixels[..., 1], pixels[..., 2]
    h, w = r.shape
    yellow = (r > 200) & (g > 140) & (b < 150) & (r - b > 90)
    white = (r > 222) & (g > 222) & (b > 215)
    dark = (r < 170) & (g < 130) & (b < 95)
    wave = (abs(r - 190) < 16) & (abs(g - 144) < 16) & (abs(b - 101) < 16)

    border = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)] + \
             [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    outside = flood(~dark, border)
    belly = flood(white, [(int(0.43 * w), int(0.70 * h)), (int(0.50 * w), int(0.72 * h))])
    # 팽창 한 단계는 평균 약 1.2픽셀을 넓힘.
    near = grow_round(yellow | belly, round(OUTLINE_PX * SEGMENT_SCALE / 1.2))
    mask = flood(near & ~outside & ~wave, [(int(0.40 * w), int(0.45 * h))])
    mask |= ~flood(~mask, border)  # 눈, 입처럼 안쪽 구멍을 채움
    return as_image(mask).filter(ImageFilter.MinFilter(5)).filter(ImageFilter.MaxFilter(5))


def character(source: Image.Image) -> Image.Image:
    size = (source.width * CHAR_SCALE, source.height * CHAR_SCALE)
    # 생성형 업스케일러는 홍채, 볼 띠에 원본에 없는 질감을 더해서 쓰지 않음.
    rgb = source.resize(size, Image.LANCZOS).filter(ImageFilter.UnsharpMask(radius=6, percent=80, threshold=2))
    alpha = character_mask(source).resize(size, Image.BILINEAR)
    alpha = alpha.point(lambda v: 255 if v >= 128 else 0).filter(ImageFilter.GaussianBlur(1.2))
    layer = rgb.convert("RGBA")
    layer.putalpha(alpha)
    return layer.crop(alpha.getbbox())


def scene(char: Image.Image) -> Image.Image:
    scale = BODY * 0.86 / char.width
    placed = char.resize((round(char.width * scale), round(char.height * scale)), Image.LANCZOS)
    body = Image.new("RGBA", (BODY, BODY), BACKGROUND + (255,))
    body.alpha_composite(placed, ((BODY - placed.width) // 2, (BODY - placed.height) // 2 + 40))
    return body


def variable_blur(image: Image.Image, levels: int = 9) -> Image.Image:
    """가로 위치에 따라 반경이 커지는 흐림. 미리 흐린 단계 사이를 섞음."""
    x = np.clip((np.arange(BODY) - BODY * BLUR_START) / (BODY * (BLUR_END - BLUR_START)), 0, 1)
    t = np.tile(x * x * (3 - 2 * x), (BODY, 1))
    radii = np.linspace(0, BLUR_MAX_RADIUS, levels)
    stack = np.stack([np.asarray(image if radius == 0 else image.filter(ImageFilter.GaussianBlur(radius)))
                      .astype(np.float64) for radius in radii])
    position = t * (levels - 1)
    low = np.floor(position).astype(int).clip(0, levels - 2)
    fraction = (position - low)[..., None]
    rows, cols = np.indices(t.shape)
    mixed = stack[low, rows, cols] * (1 - fraction) + stack[low + 1, rows, cols] * fraction
    return Image.fromarray(mixed.astype(np.uint8), "RGBA")


def icon(body: Image.Image) -> Image.Image:
    """macOS 아이콘 템플릿의 둥근 사각형과 그림자를 씌운 1024px 이미지."""
    shape = Image.new("L", (BODY * 2, BODY * 2), 0)
    ImageDraw.Draw(shape).rounded_rectangle((0, 0, BODY * 2 - 1, BODY * 2 - 1), radius=RADIUS * 2, fill=255)
    shape = shape.resize((BODY, BODY), Image.LANCZOS)
    canvas = Image.new("RGBA", (WORK, WORK), (0, 0, 0, 0))
    shadow = Image.new("L", (WORK, WORK), 0)
    shadow.paste(shape, (OFF, OFF + 28))
    canvas.putalpha(shadow.filter(ImageFilter.GaussianBlur(32)).point(lambda v: int(v * 0.30)))
    body = body.copy()
    body.putalpha(Image.fromarray(np.minimum(np.asarray(body)[..., 3], np.asarray(shape))))
    canvas.alpha_composite(body, (OFF, OFF))
    return canvas.resize((1024, 1024), Image.LANCZOS)


def write_icns(master: Image.Image, output: pathlib.Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        iconset = pathlib.Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for points in (16, 32, 128, 256, 512):
            for factor, suffix in ((1, ""), (2, "@2x")):
                pixels = points * factor
                master.resize((pixels, pixels), Image.LANCZOS).save(iconset / f"icon_{points}x{points}{suffix}.png")
        subprocess.run(["iconutil", "--convert", "icns", "--output", str(output), str(iconset)], check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--png", type=pathlib.Path, help="1024px 원본 PNG도 저장할 경로")
    args = parser.parse_args()
    source = Image.open(SOURCE).convert("RGB")
    master = icon(variable_blur(scene(character(source))))
    if args.png:
        master.save(args.png)
    write_icns(master, OUTPUT)
    print(OUTPUT.relative_to(ROOT))


if __name__ == "__main__":
    main()
