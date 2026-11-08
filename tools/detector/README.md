# Household detector

Stashlog names captured items with an on-device open-vocabulary object detector:
[YOLO-World v2](https://docs.ultralytics.com/models/yolo-world/) (medium) with Stashlog's
household vocabulary baked in, converted to Core ML. Nothing runs off the phone.

- `../../Stashlog/Resources/Detector/DetectorVocabulary.json`: what the detector looks for
  (`prompt`), and the name and category the app shows. Order matters: it's the class index.
- `try_detector.py IMAGE`: print detections for a photo (handy when tuning prompts).
- `export_coreml.py`: rebuild `HouseholdDetector.mlpackage` after changing the vocabulary.

## Setup

coremltools needs Python 3.9–3.13 and PyTorch ≤ 2.8:

```bash
python3.12 -m venv .venv
.venv/bin/pip install "torch<2.9" "torchvision<0.24" ultralytics coremltools "git+https://github.com/ultralytics/CLIP.git"
.venv/bin/python export_coreml.py
```

## License

The YOLO-World v2 weights are from Ultralytics and licensed AGPL-3.0. Stashlog is GPL-3.0,
which can be combined with AGPL-3.0 code (GPLv3 §13), and the full source stays public.
