"""Melatih model deteksi objek YOLOv8n (varian paling ringan) untuk
mendeteksi janjang & brondol, memakai library ultralytics.

Pemakaian:
    python train_yolov8.py --data dataset/data.yaml --epochs 100 --imgsz 320
"""
import argparse

from ultralytics import YOLO


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, help="Path ke data.yaml")
    parser.add_argument("--model", default="yolov8n.pt",
                         help="Model dasar (nano = paling ringan, cocok untuk HP)")
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--imgsz", type=int, default=320,
                         help="Harus sama dengan inputSize di tflite_detection_service.dart")
    parser.add_argument("--batch", type=int, default=16)
    args = parser.parse_args()

    model = YOLO(args.model)
    model.train(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
    )

    metrics = model.val()
    print("Hasil validasi:", metrics.results_dict)
    print("Weights terbaik tersimpan di: runs/detect/train/weights/best.pt")


if __name__ == "__main__":
    main()
