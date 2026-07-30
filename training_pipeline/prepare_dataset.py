"""Membagi foto+label mentah menjadi struktur train/val siap dipakai
Ultralytics YOLO, dan membuat file data.yaml.

Input yang diharapkan (sebelum dijalankan):
    raw/
      images/*.jpg
      labels/*.txt   # format YOLO, 1 file per gambar, nama sama (tanpa ekstensi)

Pemakaian:
    python prepare_dataset.py --raw raw --out dataset --val-ratio 0.2 \
        --classes janjang brondol
"""
import argparse
import random
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw", default="raw", help="Folder foto+label mentah")
    parser.add_argument("--out", default="dataset", help="Folder output")
    parser.add_argument("--val-ratio", type=float, default=0.2)
    parser.add_argument("--classes", nargs="+", default=["janjang", "brondol"])
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    raw = Path(args.raw)
    out = Path(args.out)
    images_dir = raw / "images"
    labels_dir = raw / "labels"

    if not images_dir.exists():
        raise SystemExit(f"Folder gambar tidak ditemukan: {images_dir}")

    image_files = sorted(
        [p for p in images_dir.iterdir() if p.suffix.lower() in (".jpg", ".jpeg", ".png")]
    )
    if not image_files:
        raise SystemExit("Tidak ada foto ditemukan di folder raw/images.")

    random.seed(args.seed)
    random.shuffle(image_files)

    n_val = max(1, int(len(image_files) * args.val_ratio))
    val_files = image_files[:n_val]
    train_files = image_files[n_val:]

    for split, files in (("train", train_files), ("val", val_files)):
        (out / "images" / split).mkdir(parents=True, exist_ok=True)
        (out / "labels" / split).mkdir(parents=True, exist_ok=True)
        for img_path in files:
            label_path = labels_dir / f"{img_path.stem}.txt"
            shutil.copy(img_path, out / "images" / split / img_path.name)
            if label_path.exists():
                shutil.copy(label_path, out / "labels" / split / label_path.name)
            else:
                print(f"[peringatan] label tidak ditemukan untuk {img_path.name}, dilewati")

    data_yaml = out / "data.yaml"
    data_yaml.write_text(
        "path: .\n"
        "train: images/train\n"
        "val: images/val\n"
        f"nc: {len(args.classes)}\n"
        f"names: {args.classes}\n"
    )

    print(f"Selesai. Train: {len(train_files)} foto, Val: {len(val_files)} foto.")
    print(f"data.yaml dibuat di: {data_yaml}")


if __name__ == "__main__":
    main()
