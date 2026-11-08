"""Run the household detector on an image and print what it finds.

Usage:
    python try_detector.py IMAGE [--weights yolov8s-worldv2.pt] [--conf 0.1] [--save out.jpg]

Uses the same vocabulary file the app ships (Stashlog/Resources/Detector/DetectorVocabulary.json).
"""
import argparse
import json
from pathlib import Path

from ultralytics import YOLOWorld

ROOT = Path(__file__).resolve().parents[2]
VOCAB = ROOT / "Stashlog/Resources/Detector/DetectorVocabulary.json"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--weights", default="yolov8s-worldv2.pt")
    ap.add_argument("--conf", type=float, default=0.1)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--save")
    args = ap.parse_args()

    classes = json.loads(VOCAB.read_text())["classes"]
    model = YOLOWorld(args.weights)
    model.set_classes([c["prompt"] for c in classes])

    result = model.predict(args.image, conf=args.conf, imgsz=args.imgsz, verbose=False)[0]
    rows = []
    for box in result.boxes:
        idx = int(box.cls)
        x1, y1, x2, y2 = (round(v) for v in box.xyxy[0].tolist())
        rows.append((float(box.conf), classes[idx]["name"], classes[idx]["prompt"], (x1, y1, x2, y2)))
    for conf, name, prompt, xyxy in sorted(rows, reverse=True):
        print(f"{conf:5.2f}  {name:<20} ({prompt})  box={xyxy}")
    if not rows:
        print("nothing above threshold")
    if args.save:
        result.save(filename=args.save)


if __name__ == "__main__":
    main()
