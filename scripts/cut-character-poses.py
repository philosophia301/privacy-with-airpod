"""설정 창 상태 카드의 아기상어 포즈 5장을 Cheeky Theme Guide에서 오려 냄.

사용: python3 -I scripts/cut-character-poses.py <PFBS_CheekyThemeGuide_RGB_EX.pdf> [출력 폴더]

가이드 PDF는 저장소에 넣지 않음. 6쪽(CHARACTER)을 300dpi로 그려 회색 바탕(229)을 투명으로 바꾸고,
포즈마다 캐릭터와 그 둘레의 작은 장식만 남김. 가이드 규칙에 따라 뒤집거나 색을 바꾸지 않음.
출력은 높이 320px PNG이며 기본 위치는 Resources/Character/임.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

BG = 229.0
PAGE = 6
DPI = 300
PREVIEW_WIDTH = 1169  # 상자 좌표를 잡은 미리보기 폭(px)

# 상태 이름: 6쪽 미리보기 좌표 상자(x0, y0, x1, y1)
POSES = {
    "lost": (763, 140, 958, 298),    # 화난 얼굴: AirPods 입력 없음
    "think": (577, 140, 762, 298),   # 턱 괴기: 책상 정면 전
    "relax": (378, 140, 567, 298),   # 휘파람: 준비 끝
    "cheer": (242, 512, 411, 740),   # 주먹: 정면 맞춘 직후
    "guard": (911, 512, 1068, 740),  # 팔짱: 보호 중
}


def render_page(pdf: Path, work: Path) -> np.ndarray:
    prefix = work / "page"
    subprocess.run(["pdftoppm", "-r", str(DPI), "-f", str(PAGE), "-l", str(PAGE), "-png", str(pdf), str(prefix)],
                   check=True)
    (png,) = work.glob("page*.png")
    return np.array(Image.open(png).convert("RGB"))


def color_to_alpha(rgb: np.ndarray) -> np.ndarray:
    """회색 바탕을 빼고 남은 색을 알파로 되돌림(GIMP color to alpha와 같은 방식)."""
    p = rgb.astype(np.float64)
    up = np.clip((p - BG) / (255.0 - BG), 0, None)
    down = np.clip((BG - p) / BG, 0, None)
    a = np.clip(np.maximum(up, down).max(axis=2), 0, 1)
    safe = np.where(a > 0, a, 1)[..., None]
    c = np.clip((p - BG) / safe + BG, 0, 255)
    return np.dstack([c, a * 255]).astype(np.uint8)


def keep_main_and_nearby(mask: Image.Image) -> np.ndarray:
    """가장 큰 조각과, 그 상자 안에 든 작은 장식(화남 표시, 반짝이)만 남김."""
    work = mask.copy()
    comps = []
    while True:
        arr = np.array(work)
        idx = np.argmax(arr == 255)
        if arr.flat[idx] != 255:
            break
        y, x = divmod(int(idx), arr.shape[1])
        ImageDraw.floodfill(work, (x, y), 100)
        arr2 = np.array(work)
        comp = arr2 == 100
        work = Image.fromarray(np.where(comp, 0, arr2).astype(np.uint8), "L").copy()
        ys, xs = np.nonzero(comp)
        comps.append((comp, xs.min(), ys.min(), xs.max(), ys.max(), comp.sum()))
    main = max(comps, key=lambda c: c[5])
    _, mx0, my0, mx1, my1, _ = main
    mw, mh = mx1 - mx0, my1 - my0
    lim = (mx0 - 0.06 * mw, my0 - 0.25 * mh, mx1 + 0.06 * mw, my1 + 0.06 * mh)
    keep = np.zeros_like(main[0])
    for comp, x0, y0, x1, y1, _ in comps:
        if x0 >= lim[0] and y0 >= lim[1] and x1 <= lim[2] and y1 <= lim[3]:
            keep |= comp
    return keep


def drop_border_components(rgba: np.ndarray) -> np.ndarray:
    """상자 가장자리에 걸친 이웃 포즈 조각을 지움."""
    alpha = rgba[..., 3]
    # PIL floodfill은 이미지 가장자리의 시작점을 놓치므로 1px 띄움.
    mask = Image.fromarray(np.pad(np.where(alpha > 8, 255, 0).astype(np.uint8), 1), "L").copy()
    h, w = alpha.shape
    seeds = ([(x + 1, 1) for x in range(w)] + [(x + 1, h) for x in range(w)]
             + [(1, y + 1) for y in range(h)] + [(w, y + 1) for y in range(h)])
    for x, y in seeds:
        if mask.getpixel((x, y)) == 255:
            ImageDraw.floodfill(mask, (x, y), 0)
    keep = keep_main_and_nearby(mask)[1:-1, 1:-1]
    # 남긴 조각에 닿은 옅은 경계 픽셀도 살림.
    grown = keep.copy()
    grown[1:, :] |= keep[:-1, :]
    grown[:-1, :] |= keep[1:, :]
    grown[:, 1:] |= keep[:, :-1]
    grown[:, :-1] |= keep[:, 1:]
    out = rgba.copy()
    out[..., 3] = np.where(grown, alpha, 0)
    return out


def main() -> None:
    pdf = Path(sys.argv[1])
    out_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parent.parent / "Resources/Character"
    out_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        page = render_page(pdf, Path(tmp))
    scale = page.shape[1] / PREVIEW_WIDTH
    for name, box in POSES.items():
        x0, y0, x1, y1 = (int(round(v * scale)) for v in box)
        crop = drop_border_components(color_to_alpha(page[y0:y1, x0:x1]))
        ys, xs = np.nonzero(crop[..., 3] > 8)
        crop = crop[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
        im = Image.fromarray(crop, "RGBA")
        im = im.resize((round(im.width * 320 / im.height), 320), Image.LANCZOS)
        im.save(out_dir / f"{name}.png", optimize=True)
        print(name, im.size)


if __name__ == "__main__":
    main()
