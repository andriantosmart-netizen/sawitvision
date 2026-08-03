#!/usr/bin/env python3
"""
train_yolov8.py -- latih model deteksi custom (Janjang / Brondol / Janjang Kosong) berbasis
Ultralytics YOLO, default ke YOLO26n (rilis Ultralytics Januari 2026, varian "nano" -- edge-first,
paling ringan/cepat, cocok untuk jalan di HP).

PENTING -- JALANKAN DI KOMPUTER/LAPTOP ANDA SENDIRI, BUKAN DI SANDBOX CLOUD CLAUDE:
  Training model deteksi objek (walau versi nano) butuh waktu jauh lebih wajar dengan GPU. Kalau
  komputer Anda TIDAK punya GPU NVIDIA, training tetap BISA jalan di CPU tapi jauh lebih lambat
  (bisa berjam-jam untuk beberapa ratus foto x 100 epoch, tergantung CPU) -- pertimbangkan Google
  Colab (ada GPU gratis dengan batas pemakaian) kalau tidak ada GPU sendiri.

Cara pakai (setelah dataset/data.yaml siap dari prepare_dataset.py):
    pip install -r requirements.txt
    python train_yolov8.py --data dataset/data.yaml

Opsi umum:
    python train_yolov8.py --data dataset/data.yaml --epochs 150 --imgsz 640 --batch 16
    python train_yolov8.py --data dataset/data.yaml --model yolov8n.pt   # fallback kalau
        # ultralytics yang terpasang belum mendukung YOLO26 (coba `pip install -U ultralytics` dulu)
    python train_yolov8.py --data dataset/data.yaml --device cpu         # paksa CPU (default:
        # otomatis pakai GPU NVIDIA kalau terdeteksi, CPU kalau tidak ada)

Hasil training tersimpan di runs/detect/<name>/weights/best.pt -- lanjutkan ke
export_to_tflite.py untuk dipakai di aplikasi Flutter.
"""
import argparse
import sys


def check_environment():
    """Cek ketersediaan GPU & versi ultralytics SEBELUM mulai training -- supaya kalau ada
    masalah (paket belum terpasang, atau CPU-only padahal user pikir ada GPU), user tahu dari
    awal, bukan menunggu training jalan lama dulu baru sadar salah setup."""
    try:
        import torch
    except ImportError:
        print("Paket 'torch' belum terpasang. Jalankan: pip install -r requirements.txt", file=sys.stderr)
        sys.exit(1)
    try:
        import ultralytics
    except ImportError:
        print("Paket 'ultralytics' belum terpasang. Jalankan: pip install -r requirements.txt", file=sys.stderr)
        sys.exit(1)

    print(f"ultralytics versi: {ultralytics.__version__}")
    print(f"torch versi: {torch.__version__}")
    cuda_ok = torch.cuda.is_available()
    if cuda_ok:
        print(f"GPU terdeteksi: {torch.cuda.get_device_name(0)} -- training akan pakai GPU ini.")
    else:
        print(
            "TIDAK ada GPU NVIDIA terdeteksi -- training akan jalan di CPU (JAUH lebih lambat, "
            "bisa berjam-jam). Kalau ini di luar dugaan (komputer Anda seharusnya punya GPU), "
            "cek dulu apakah PyTorch versi CUDA sudah terpasang benar: "
            "https://pytorch.org/get-started/locally/"
        )
    return cuda_ok


def main():
    ap = argparse.ArgumentParser(description="Latih model deteksi Janjang/Brondol/Janjang Kosong (Ultralytics YOLO)")
    ap.add_argument("--data", required=True, help="Path ke dataset/data.yaml (hasil prepare_dataset.py)")
    ap.add_argument(
        "--model", default="yolo26n.pt",
        help=(
            "Model dasar (pretrained COCO) untuk transfer learning -- default 'yolo26n.pt' "
            "(YOLO26, varian nano, rilis Ultralytics Jan 2026). Kalau ultralytics yang terpasang "
            "belum mendukungnya, coba 'pip install -U ultralytics' dulu, atau fallback ke "
            "'yolov8n.pt' (lebih lama tapi pasti didukung versi ultralytics mana pun)."
        ),
    )
    ap.add_argument("--epochs", type=int, default=100, help="Jumlah epoch (default 100 -- naikkan kalau dataset kecil & belum overfitting)")
    ap.add_argument("--imgsz", type=int, default=640, help="Ukuran gambar training (default 640 untuk akurasi; turunkan ke 320 saat export kalau prioritas kecepatan di HP)")
    ap.add_argument("--batch", type=int, default=-1, help="Batch size (-1 = otomatis dari ultralytics berdasar memori tersedia)")
    ap.add_argument("--device", default=None, help="'cpu', '0' (GPU pertama), dsb -- kosongkan untuk deteksi otomatis")
    ap.add_argument("--project", default="runs/detect", help="Folder induk hasil training")
    ap.add_argument("--name", default="sawit_train", help="Nama sub-folder run ini")
    ap.add_argument("--patience", type=int, default=30, help="Early stopping -- hentikan kalau tidak ada perbaikan selama N epoch")
    ap.add_argument("--resume", action="store_true", help="Lanjutkan training yang terputus (dari runs/detect/<name>/weights/last.pt)")
    args = ap.parse_args()

    check_environment()

    from ultralytics import YOLO

    print(f"\nMemuat model dasar: {args.model} (pretrained COCO, transfer learning) ...")
    model = YOLO(args.model)

    train_kwargs = dict(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        project=args.project,
        name=args.name,
        patience=args.patience,
        resume=args.resume,
    )
    if args.device:
        train_kwargs["device"] = args.device

    print(f"\nMulai training -- data={args.data}, epochs={args.epochs}, imgsz={args.imgsz}\n")
    results = model.train(**train_kwargs)

    best_weights = f"{args.project}/{args.name}/weights/best.pt"
    print("\n=== Training selesai ===")
    print(f"Bobot terbaik: {best_weights}")
    print(f"Metrik & grafik lengkap: {args.project}/{args.name}/")
    print("\nLangkah berikutnya:")
    print(f"  python export_to_tflite.py --weights {best_weights}")


if __name__ == "__main__":
    main()
