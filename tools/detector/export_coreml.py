"""Export the household detector to Core ML for the app.

Bakes the vocabulary (Stashlog/Resources/Detector/DetectorVocabulary.json) into a YOLO-World
model, so the app needs no text encoder, and writes HouseholdDetector.mlpackage into the
app's Resources/Detector folder. Re-run whenever the vocabulary changes.

    python export_coreml.py [--weights yolov8m-worldv2.pt] [--imgsz 640]

Weights: Ultralytics YOLO-World v2 (AGPL-3.0). Stashlog is GPL-3.0, which may be combined
with AGPL-3.0 code (GPLv3 section 13); the app's full source stays public.
"""
import argparse
import json
import shutil
from pathlib import Path

from ultralytics import YOLOWorld

ROOT = Path(__file__).resolve().parents[2]
DETECTOR_DIR = ROOT / "Stashlog/Resources/Detector"
VOCAB = DETECTOR_DIR / "DetectorVocabulary.json"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", default="yolov8m-worldv2.pt")
    ap.add_argument("--imgsz", type=int, default=640)
    args = ap.parse_args()

    prompts = [c["prompt"] for c in json.loads(VOCAB.read_text())["classes"]]
    model = YOLOWorld(args.weights)
    model.set_classes(prompts)
    exported = Path(model.export(format="coreml", imgsz=args.imgsz, nms=True, half=True))

    target = DETECTOR_DIR / "HouseholdDetector.mlpackage"
    if target.exists():
        shutil.rmtree(target)
    shutil.move(str(exported), target)
    print(f"Wrote {target} ({len(prompts)} classes)")


if __name__ == "__main__":
    main()
