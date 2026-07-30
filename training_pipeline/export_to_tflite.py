"""Export model YOLOv8 (.pt) hasil training menjadi TFLite, siap dipakai
oleh tflite_detection_service.dart di aplikasi Flutter.

Pemakaian:
    python export_to_tflite.py --weights runs/detect/train/weights/best.pt
"""
import argparse
import shutil
from pathlib import Path

from ultralytics import YOLO


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", required=True, help="Path ke best.pt hasil training")
    parser.add_argument("--imgsz", type=int, default=320)
    parser.add_argument("--half", action="store_true",
                         help="Gunakan float16 quantization (ukuran lebih kecil)")
    parser.add_argument("--out-name", default="sawit_detector.tflite")
    args = parser.parse_args()

    model = YOLO(args.weights)
    exported_path = model.export(format="tflite", imgsz=args.imgsz, half=args.half)

    dest_dir = Path("../assets/models")
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / args.out_name
    shutil.copy(exported_path, dest)

    print(f"Model TFLite disalin ke: {dest.resolve()}")
    print("Jangan lupa update assets/labels/labels.txt sesuai urutan kelas "
          "di data.yaml, lalu aktifkan mode 'Model Custom (TFLite)' di Settings app.")


if __name__ == "__main__":
    main()
