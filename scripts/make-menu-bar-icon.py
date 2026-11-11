#!/usr/bin/env python3
"""메뉴 막대 아이콘 프레임 25장 Resources/MenuBarIcon/blur-00.png..blur-24.png를 만듦.

원본 아기상어 그림의 캐릭터를 앱 아이콘과 같은 방식으로 오리고, 흐림 정도 u=NN/24에 따라
오른쪽부터 흐려진 프레임을 만듦. blur-00은 흐림 없는 꺼짐 아이콘이고 blur-24는 최대 흐림임.
각 파일은 44x36px RGBA이며 메뉴 막대 22x18pt의 2배 해상도임.

앱은 정지 구간에는 프레임을 바꾸지 않고, 전환 구간 2초에서만 10fps로 프레임을 바꿈.
결정값 출처는 docs/spec.md의 메뉴 막대 아이콘 절임.

사용법:
  python3 scripts/make-menu-bar-icon.py

같은 입력이면 같은 파일이 나옴. 캐릭터 마스크와 원본 경로는 scripts/make-app-icon.py를
importlib로 불러 재사용하며 그 파일은 수정하지 않음. 필요: Pillow, numpy.
"""
import importlib.util
import pathlib

import numpy as np
from PIL import Image, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUTPUT_DIR = ROOT / "Resources/MenuBarIcon"

LEVEL_COUNT = 25     # blur-00..blur-24
STEPS = 24           # 흐림 정도 u = 단계 / STEPS
HEIGHT = 36          # 44x36px
WORK_SCALE = 3       # 1/3 해상도에서 계산함. 36px 결과에는 충분함
MASK_PAD = 60        # 캐릭터 마스크 바깥 여백(원본 확대 기준)
CANVAS_TOP_BOTTOM = 40
CANVAS_RIGHT = 80

# 2026-11-12 사용자가 고른 4안 컬러 흐림의 값. 작업 해상도(1/3) 기준 픽셀 값임.
BLUR_START = 0.16      # 흐림이 시작되는 가로 위치
BLUR_WIDTH = 0.56      # 흐림 전환 폭
COLOR_RADIUS = 180 / WORK_SCALE   # 색 흐림 최대 반경
ENVELOPE_RADIUS = 42 / WORK_SCALE  # 투명도 흐림 최대 반경
ENVELOPE_FADE = 0.50   # 최대 흐림에서 남는 투명도 감소량
RADIUS_FLOOR = 0.4     # 반경은 0.4 + 0.6u배로 커짐
RADIUS_SLOPE = 0.6
RAMP_START = 1.05      # 흐림 경계가 들어오는 시작 위치 바깥
BLEND_LEVELS = 8       # 미리 흐린 단계 수. 사이 값은 선형으로 섞음


def load_app_icon_module():
    path = ROOT / "scripts/make-app-icon.py"
    spec = importlib.util.spec_from_file_location("make_app_icon", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def character_layer(app_icon) -> np.ndarray:
    """캐릭터만 남긴 RGBA 배열(0..1)을 만듦. 흐림 계산 전의 기준 그림임."""
    source = Image.open(app_icon.SOURCE).convert("RGB")
    mask = app_icon.character_mask(source)
    box = mask.getbbox()
    rgba = source.resize(mask.size, Image.LANCZOS).crop(box).convert("RGBA")
    silhouette = mask.crop(box).point(lambda v: 255 if v > 127 else 0)
    rgba.putalpha(silhouette.filter(ImageFilter.GaussianBlur(1.5)))
    array = np.asarray(rgba).astype(float) / 255
    array = np.pad(array, ((MASK_PAD, MASK_PAD), (MASK_PAD, MASK_PAD), (0, 0)))
    array = np.pad(array, ((CANVAS_TOP_BOTTOM, CANVAS_TOP_BOTTOM), (0, CANVAS_RIGHT), (0, 0)))
    image = Image.fromarray((array * 255).astype(np.uint8))
    image = image.resize((image.width // WORK_SCALE, image.height // WORK_SCALE), Image.LANCZOS)
    return np.asarray(image).astype(float) / 255


def ramp(width: int, height: int, start: float, end: float) -> np.ndarray:
    """가로 위치를 0..1 smoothstep으로 바꾼 격자."""
    x = np.clip((np.arange(width) - width * start) / (width * (end - start)), 0, 1)
    return np.tile(x * x * (3 - 2 * x), (height, 1))


def blur_right(alpha: np.ndarray, start: float, end: float, max_radius: float) -> np.ndarray:
    """오른쪽으로 갈수록 커지는 흐림. 미리 흐린 단계 사이를 섞음."""
    height, width = alpha.shape
    t = ramp(width, height, start, end)
    base = Image.fromarray((alpha * 255).astype(np.uint8))
    radii = np.linspace(0, max_radius, BLEND_LEVELS)
    stack = np.stack([
        np.asarray(base if radius == 0 else base.filter(ImageFilter.GaussianBlur(radius))).astype(float) / 255
        for radius in radii
    ])
    position = t * (BLEND_LEVELS - 1)
    low = np.floor(position).astype(int).clip(0, BLEND_LEVELS - 2)
    fraction = position - low
    rows, cols = np.indices(t.shape)
    return stack[low, rows, cols] * (1 - fraction) + stack[low + 1, rows, cols] * fraction


def blur_rgba(layer: np.ndarray, start: float, end: float, max_radius: float) -> np.ndarray:
    """색을 미리 곱한 채널별 흐림 뒤 투명도로 나눔. 가장자리 색 번짐을 막음."""
    result = np.zeros_like(layer)
    premultiplied = layer[..., :3] * layer[..., 3:4]
    alpha = blur_right(layer[..., 3], start, end, max_radius)
    for channel in range(3):
        result[..., channel] = blur_right(premultiplied[..., channel], start, end, max_radius)
    result[..., 3] = alpha
    safe = np.maximum(alpha, 1e-4)
    result[..., :3] = np.clip(result[..., :3] / safe[..., None], 0, 1)
    return result


def frame(layer: np.ndarray, level: int) -> np.ndarray:
    """흐림 단계 level의 프레임. 0은 흐림 없는 그림임."""
    u = level / STEPS
    if u <= 0.001:
        return layer
    height, width = layer.shape[:2]
    front = RAMP_START - u * (RAMP_START - BLUR_START)
    start, end = front, front + BLUR_WIDTH
    radius_scale = RADIUS_FLOOR + RADIUS_SLOPE * u
    colored = blur_rgba(layer, start, end, COLOR_RADIUS * radius_scale)
    envelope = blur_right(layer[..., 3], start, end, ENVELOPE_RADIUS * radius_scale)
    t = ramp(width, height, start, end)
    result = colored.copy()
    result[..., 3] = np.clip(envelope, 0, 1) * (1 - ENVELOPE_FADE * u * t)
    return result


def to_image(array: np.ndarray) -> Image.Image:
    image = Image.fromarray((np.clip(array, 0, 1) * 255).astype(np.uint8))
    width = round(image.width * HEIGHT / image.height)
    return image.resize((width, HEIGHT), Image.LANCZOS)


def main() -> None:
    layer = character_layer(load_app_icon_module())
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for level in range(LEVEL_COUNT):
        to_image(frame(layer, level)).save(OUTPUT_DIR / f"blur-{level:02d}.png")
    print(f"{LEVEL_COUNT} frames -> {OUTPUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
