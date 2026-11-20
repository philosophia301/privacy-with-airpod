# /// script
# requires-python = ">=3.11"
# dependencies = ["numpy", "pillow", "scipy"]
# ///
"""정방향 헤엄 영상과 캐릭터 없는 물 영상(또는 기존 그림 파일의 물)에서 앱용 그림 파일 한 개를 만듦."""

import argparse
import json
import math
import os
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

STEPS = 48
WIDTH, HEIGHT = 1280, 720
COAST, WATER, BODY, ROWS = 192, 896, 384, 448
RADIUS = 0.11
# --clean-water에서 물가를 펴는 줄 수(높이 720 기준). 손그림 포말 덩어리 하나보다 조금 큼.
BROAD_EDGE_ROWS = 61


def sample_frames(movie):
    info = subprocess.check_output(
        [
            "ffprobe",
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-count_frames",
            "-show_entries",
            "stream=width,height,nb_read_frames",
            "-of",
            "json",
            str(movie),
        ]
    )
    video = json.loads(info)["streams"][0]
    count = int(video["nb_read_frames"])
    if count < 2 or abs(video["width"] / video["height"] - WIDTH / HEIGHT) > 0.02:
        raise ValueError(f"16:9 영상에 정방향 프레임이 두 장 이상 필요함: {movie}")
    wanted = np.linspace(0, count - 1, STEPS).round().astype(int)
    command = [
        "ffmpeg",
        "-v",
        "error",
        "-i",
        str(movie),
        "-map",
        "0:v:0",
        "-vf",
        f"scale={WIDTH}:{HEIGHT}",
        "-fps_mode",
        "passthrough",
        "-an",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "rgb24",
        "pipe:1",
    ]
    with subprocess.Popen(command, stdout=subprocess.PIPE) as reader:
        for index in range(count):
            data = reader.stdout.read(WIDTH * HEIGHT * 3)
            if len(data) != WIDTH * HEIGHT * 3:
                raise ValueError(f"프레임이 끊김: {movie}, {index}")
            for _ in range(np.count_nonzero(wanted == index)):
                yield np.frombuffer(data, dtype=np.uint8).reshape(HEIGHT, WIDTH, 3)
        if reader.wait():
            raise ValueError(f"영상 디코딩 실패: {movie}")


def largest(mask):
    labels, count = ndimage.label(mask, structure=np.ones((3, 3)))
    if not count:
        raise ValueError("치키를 찾을 수 없음")
    area = np.bincount(labels.ravel())
    area[0] = 0
    return labels == area.argmax()


def smooth(value):
    value = np.clip(value, 0, 1)
    return value * value * (3 - 2 * value)


def background_key(frame):
    return np.median(frame[:, :8].reshape(-1, 3), axis=0)


def yellow_body(frame):
    r, g, b = frame.astype(np.int16).transpose(2, 0, 1)
    yellow = (r > 130) & (g > 90) & (r > b + 65) & (g > b + 46) & (r > 0.82 * g)
    yellow = largest(ndimage.binary_closing(yellow, iterations=2))
    yy, xx = np.nonzero(yellow)
    width = xx.max() - xx.min() + 1
    if not 0.11 * WIDTH < width < 0.29 * WIDTH:
        raise ValueError("레퍼런스 크기의 노란 캐릭터를 찾지 못함")
    return yellow, (xx.min(), yy.min(), xx.max() + 1, yy.max() + 1)


def character_tile(frame, yellow, bounds, anchor_y=None):
    x1, y1, x2, y2 = bounds
    cx, cy = (x1 + x2 - 1) / 2, (y1 + y2 - 1) / 2
    width = x2 - x1
    # 승인한 Blender 카메라 너비 16에서 캐릭터가 차지하는 정사각형은 4.6임.
    side = round(WIDTH * 4.6 / 16)
    # 세로 기준을 받으면 그 높이로 잘라, 영상 속 위아래 튀어오름을 칸 안에 남김.
    anchor = cy if anchor_y is None else anchor_y
    x0, y0 = round(cx - side / 2), round(anchor - side / 2)
    if y1 < y0 or y2 > y0 + side:
        raise ValueError(
            "치키가 칸 위아래를 벗어남. 튀어오름이 칸보다 크거나 영상의 세로 동선이 굽어 있음"
        )
    # 칸 안에서 몸 중심의 위치. 기준이 없으면 언제나 칸 한가운데임.
    mid_x, mid_y = side / 2, side / 2 + (cy - anchor)
    image = Image.fromarray(frame).crop((x0, y0, x0 + side, y0 + side))
    rgb = np.asarray(image, dtype=np.float32)
    r, g, b = rgb.transpose(2, 0, 1)
    local_yellow = np.asarray(Image.fromarray(yellow).crop((x0, y0, x0 + side, y0 + side)))
    distance = ndimage.distance_transform_edt(~local_yellow)
    warm = (r > b + 12) & (g > b + 3) & (r > 53)
    y, x = np.indices(local_yellow.shape)
    lower_front = (x < mid_x + 0.14 * width) & (y > mid_y + 0.005 * width)
    belly = lower_front & (np.minimum(np.minimum(r, g), b) > 178) & (r > b - 9) & (r > g - 11)
    body = (warm | belly) & (distance < 0.18 * width)
    body = largest(ndimage.binary_closing(body | local_yellow, iterations=2))
    body = ndimage.binary_fill_holes(body)
    # 물이 앞을 지나가면서 가까운 지느러미가 외곽선과 떨어지는 프레임도 있음.
    fin_box = (x > mid_x - 0.13 * width) & (x < mid_x + 0.38 * width) & (y > mid_y + 0.14 * width)
    reflected_fin = fin_box & (distance < 0.22 * width) & (r > b + 3) & (g > b + 20) & (r > 79)
    body |= ndimage.binary_opening(reflected_fin)
    outside = ndimage.distance_transform_edt(~body)
    # 배 아래 물보라는 살리고, 눈과 입과 볼의 별은 흐려지지 않도록 물만 부드럽게 섞음.
    near_belly = smooth((y - mid_y - 0.025 * width) / (0.08 * width))
    under_fin = 1 - smooth((x - mid_x - 0.15 * width) / (0.15 * width))
    contact = near_belly * under_fin * (1 - smooth(outside / (0.115 * width)))
    key = background_key(frame)
    distance_to_key = np.sqrt(np.mean((rgb - key) ** 2, axis=2))
    alpha = np.maximum(ndimage.gaussian_filter(body.astype(np.float32), 0.60), contact)
    alpha *= smooth((distance_to_key - 7) / 32)
    out = np.dstack((rgb, alpha * 255)).round().astype(np.uint8)
    return Image.fromarray(out).resize((BODY, BODY), Image.Resampling.LANCZOS)


def coast_positions(frame):
    rgb = frame.astype(np.float32)
    key = background_key(frame)
    distance = np.sqrt(np.mean((rgb - key) ** 2, axis=2))
    # 그림자진 물은 빈 배경만큼 어두워도 보라색 배경과 달리 초록 성분이 빨강보다 큼.
    purple = (distance < 40) & (rgb[..., 0] > rgb[..., 1] + 4)
    dry = ndimage.uniform_filter1d(purple.astype(np.float32), size=11, axis=1) > 0.72
    if not np.all(dry.any(axis=1)) or dry[:, -5:].mean() > 0.03:
        raise ValueError("왼쪽은 빈 배경, 오른쪽은 물인 프레임이 필요함")
    edge = WIDTH - 1 - np.argmax(dry[:, ::-1], axis=1)
    edge = ndimage.median_filter(edge, size=5)
    return edge, key


def water_pixels(plate, edge, key, y, depth, shore):
    source_edge = np.interp(y, np.arange(HEIGHT), edge)
    # 포말은 원본 크기로 남김. 화면 전체를 덮을 때 모자란 너비는 먼 쪽 물에서 확보함.
    natural = np.minimum(0.085, np.maximum(0, (WIDTH - 1 - source_edge) / WIDTH) * 0.66)[:, None]
    room = ((WIDTH - 1 - source_edge) / WIDTH)[:, None]
    from_edge = np.minimum(depth, natural) + np.maximum(depth - natural, 0) * (room - natural) / (
        1 - shore[:, None] - natural
    )
    sx = np.clip(source_edge[:, None] + WIDTH * from_edge, 0, WIDTH - 1).astype(np.float32)
    sy = np.broadcast_to(y[:, None], sx.shape).astype(np.float32)
    colors = np.stack(
        [
            ndimage.map_coordinates(channel, (sy, sx), order=1, mode="nearest")
            for channel in plate.transpose(2, 0, 1)
        ],
        axis=2,
    ).astype(np.float32)
    difference = np.sqrt(np.mean((colors - key) ** 2, axis=2))
    alpha = smooth((difference - 7) / 41)
    alpha[depth > 0.013] = 1
    premultiplied = np.clip(colors - key * (1 - alpha[..., None]), 0, 255 * alpha[..., None])
    return np.dstack((premultiplied, 255 * alpha)), sx


def tile_rows(phase):
    # 원본의 물가를 먼저 펴서 질감을 얻고 Blender 수정 B의 경계에 다시 맞춤.
    v = (np.arange(ROWS) + 0.5) / ROWS
    y = v * HEIGHT - 0.5
    center_y = 0.5 + (0.07 + 1.55 * math.sin(2 * math.pi * (1.12 * phase - 0.10))) / 9
    wave = (1 - v - center_y) * 2 * math.pi
    shore = -0.22 * (0.39 * np.sin(1.28 * wave) + 0.085 * np.sin(2.12 * wave))
    near = np.linspace(-RADIUS, RADIUS, COAST)
    deep = np.linspace(RADIUS, 1.0, WATER - COAST)
    depth = np.concatenate((near, deep))[None, :] - shore[:, None]
    return y, depth, shore


def finished_tile(rgba):
    rgba[..., :3] *= 255 / np.maximum(rgba[..., 3:], 1)
    # 잘린 물방울이 자산 가장자리에 수직선을 만들지 않게 함.
    rgba[:, :8, 3] *= smooth(np.linspace(0, 1, 8))[None, :]
    rgba = np.clip(rgba, 0, 255).round().astype(np.uint8)
    rgba[rgba[..., 3] == 0] = 0
    return Image.fromarray(rgba)


def water_tile(frame, clean, bounds, phase):
    y, depth, shore = tile_rows(phase)
    clean_edge, clean_key = coast_positions(clean)
    backup, _ = water_pixels(clean, clean_edge, clean_key, y, depth, shore)
    edge, key = coast_positions(frame)
    x1, y1, x2, y2 = bounds
    width = x2 - x1
    rows = np.arange(HEIGHT)
    # 배 아래 물보라를 물가로 잘못 잡으면 같은 높이의 바닷속 질감 전체가 옆으로 튐.
    visible = (rows < y1 - 0.21 * width) | (rows > y2 + 0.42 * width)
    edge = np.interp(rows, rows[visible], edge[visible])
    edge = ndimage.gaussian_filter1d(edge, 2.5)
    wet, sx = water_pixels(frame, edge, key, y, depth, shore)
    # 치키에 가렸던 자리만 빈 물 영상으로 채움. 반대쪽에서 물을 뒤집을 때 얼굴이 두 개 보이지 않게 함.
    dx = np.maximum(x1 - 0.10 * width - sx, sx - x2 - 0.52 * width)
    dy = np.maximum(y1 - 0.095 * width - y, y - y2 - 0.15 * width)[:, None]
    gain = smooth(np.maximum(dx, dy) / (0.24 * width))[..., None]
    rgba = backup * (1 - gain) + wet * gain
    return finished_tile(rgba)


def clean_water_tile(clean, phase):
    # 손그림 바다처럼 포말 윤곽이 또렷하면 줄마다 물가를 맞출 때 포말 덩어리가 가로로 찢어짐.
    # 물가를 여러 줄 단위로 펴서 덩어리 모양을 남김. 최댓값으로 먼저 펴야 펴진 물가 오른쪽에
    # 빈 배경이 남지 않음. 남으면 물 안쪽으로 취급돼 불투명한 보라 얼룩이 됨.
    y, depth, shore = tile_rows(phase)
    edge, key = coast_positions(clean)
    edge = ndimage.maximum_filter1d(edge, size=BROAD_EDGE_ROWS)
    edge = ndimage.gaussian_filter1d(edge.astype(np.float64), BROAD_EDGE_ROWS / 4)
    rgba, _ = water_pixels(clean, edge, key, y, depth, shore)
    return finished_tile(rgba)


def packed_water(path):
    # 기존 그림 파일의 물가와 깊은 물을 그대로 다시 씀. 캐릭터만 바꿔 비교할 때 사용함.
    with Image.open(path) as pack:
        if pack.n_frames != STEPS or pack.size != (WATER + BODY, ROWS):
            raise ValueError(f"{STEPS}쪽, {WATER + BODY}×{ROWS} 그림 파일이 아님: {path}")
        for index in range(STEPS):
            pack.seek(index)
            yield pack.convert("RGBA").crop((0, 0, WATER, ROWS))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("swimmer", type=Path, help="치키가 한 방향으로 헤엄치는 16:9 영상")
    parser.add_argument(
        "water",
        type=Path,
        help="같은 보라색 배경에서 오른쪽부터 들어오는 캐릭터 없는 물 영상, 또는 물을 그대로 쓸 기존 swim.tiff",
    )
    parser.add_argument("output", type=Path, help="앱이 읽을 swim.tiff")
    parser.add_argument(
        "--keep-bounce",
        action="store_true",
        help="치키를 매 프레임 칸 가운데로 맞추지 않고 영상 전체의 세로 기울기만 빼서, 위아래 튀어오름을 남김",
    )
    parser.add_argument(
        "--clean-water",
        action="store_true",
        help="물을 전부 캐릭터 없는 물 영상에서 가져옴. 치키 영상의 물은 쓰지 않고, 또렷한 손그림 포말이 찢어지지 않게 물가를 넓게 맞춤",
    )
    args = parser.parse_args()
    packed = args.water.suffix.lower() in (".tif", ".tiff")
    if args.output.resolve() in (args.swimmer.resolve(), args.water.resolve()):
        parser.error("출력 경로가 입력 영상과 같음")
    if args.clean_water and packed:
        parser.error("--clean-water에는 기존 그림 파일이 아닌 물 영상이 필요함")
    frames = list(sample_frames(args.swimmer))
    found = [yellow_body(frame) for frame in frames]
    anchors = [None] * len(frames)
    if args.keep_bounce:
        # 가로 위치와 화면 위 동선은 앱이 정함. 직선 추세만 빼서 영상이 만든 튀어오름은 그대로 둠.
        centers = np.array([(bounds[1] + bounds[3] - 1) / 2 for _, bounds in found])
        steps = np.arange(len(centers))
        anchors = list(np.polyval(np.polyfit(steps, centers, 1), steps))
    if packed:
        waters = packed_water(args.water)
    elif args.clean_water:
        waters = (
            clean_water_tile(plate, index / (STEPS - 1))
            for index, plate in enumerate(sample_frames(args.water))
        )
    else:
        waters = (
            water_tile(frame, plate, bounds, index / (STEPS - 1))
            for index, (frame, plate, (_, bounds)) in enumerate(
                zip(frames, sample_frames(args.water), found, strict=True)
            )
        )
    pages = []
    for frame, (yellow, bounds), water, anchor in zip(frames, found, waters, anchors, strict=True):
        page = Image.new("RGBA", (WATER + BODY, ROWS))
        page.paste(water, (0, 0))
        page.paste(character_tile(frame, yellow, bounds, anchor), (WATER, 0))
        pages.append(page)
    if len(pages) != STEPS:
        raise ValueError("프레임 수가 맞지 않음")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=args.output.parent) as scratch:
        pack = Path(scratch) / "swim.tiff"
        pages[0].save(
            pack,
            save_all=True,
            append_images=pages[1:],
            compression="tiff_adobe_deflate",
            tiffinfo={317: 2},
        )
        with Image.open(pack) as image:
            if image.n_frames != STEPS:
                raise ValueError("저장된 프레임 수가 맞지 않음")
            image.seek(STEPS - 1)
            image.load()
        os.replace(pack, args.output)
    print(f"{args.output}: {len(pages)} frames, {args.output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
