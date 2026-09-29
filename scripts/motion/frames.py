"""Frame strips and touch-to-response counts from a MotionScript recording.

    uv run --with numpy --with pillow python3 scripts/motion/frames.py <video> <out-dir>

Each strip starts with frame L, the finger's last, so the next tile is the
first frame after the lift. The app draws a red ring under each finger (-FieldTouchMarks) and removes it
the moment the finger lifts, before it acts on the touch. So for each lift:
the last frame with the ring is L, and the response is the first frame after L
whose bottom half differs from L's (the ring's own spot masked out). A
response one frame after the lift is L + 1.
"""
import subprocess
import sys
from pathlib import Path

import numpy as np

FPS = 60
W = 201  # half points: the iPhone 17 simulator records 402 points wide at 3x


def frames(video):
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
         "-of", "csv=p=0", video], capture_output=True, text=True, check=True).stdout.strip()
    width, height = map(int, probe.split(","))
    h = round(height * W / width / 2) * 2
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-vf", f"fps={FPS},scale={W}:{h}",
         "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, h, W, 3)


def rings(video):
    """Per frame, the ring's centre or None."""
    out = []
    for frame in video:
        r, g, b = (frame[..., i] for i in range(3))
        ys, xs = np.nonzero((r > 200) & (g < 110) & (b < 110))
        out.append((xs.mean(), ys.mean()) if len(xs) > 30 else None)
    return out


def flagged(frame):
    """The green square the app puts in the bottom-left corner at a commit."""
    corner = frame[-6:, :6].astype(int)
    return bool(((corner[..., 1] > 150) & (corner[..., 0] < 120) & (corner[..., 2] < 150)).sum() > 6)


def changed(a, b, centre, top):
    d = np.abs(a[top:].astype(int) - b[top:].astype(int)).max(axis=2) > 28
    if centre is not None:
        yy, xx = np.mgrid[top:a.shape[0], 0:a.shape[1]]
        d &= (xx - centre[0]) ** 2 + (yy - centre[1]) ** 2 > 12 ** 2
    return d.sum() > 8


def strip(video_path, first, count, path, step=1, cols=8):
    """Frames `first`, `first + step`, ... (`count` of them, counted at FPS
    from the start, as the analysis counts them): the bottom 55%, tiled."""
    rows = (count + cols - 1) // cols
    last = first + step * (count - 1)
    pick = f"between(n\\,{first}\\,{last})*not(mod(n-{first}\\,{step}))"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", video_path, "-frames:v", "1",
         "-vf", f"fps={FPS},select='{pick}',crop=iw:ih*0.55:0:ih*0.45,scale=200:-2,tile={cols}x{rows}",
         str(path)], check=True)


def main(video_path, out):
    out = Path(out)
    video = frames(video_path)
    ring = rings(video)
    h = video.shape[1]
    top = int(h * 0.45)
    lifts = [i for i in range(len(ring) - 1) if ring[i] is not None and ring[i + 1] is None]
    report = []
    for n, last in enumerate(lifts):
        centre = ring[last]
        response = None
        for j in range(last + 1, min(last + 90, len(video))):
            if changed(video[last], video[j], centre, top):
                response = j - last
                break
        flag = next((j - last for j in range(last + 1, min(last + 20, len(video))) if flagged(video[j])), None)
        report.append(f"lift {n}: frame {last} ({last / FPS:.2f} s) at y={centre[1] * 2:.0f}pt, "
                      f"first change {response if response is not None else 'none within 90'} frame(s) later"
                      + (f", commit flag {flag}" if flag is not None else ""))
        # The lift at 60 fps, close up, then the whole motion at 30.
        strip(video_path, last, 16, out / f"tap{n}-60fps.png")
        strip(video_path, last, 24, out / f"tap{n}-30fps.png", step=2)
    (out / "report.txt").write_text("\n".join(report) + "\n")
    print("\n".join(report))


if __name__ == "__main__":
    main(*sys.argv[1:3])
