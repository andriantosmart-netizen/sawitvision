#!/usr/bin/env python3
"""
export_to_tflite.py -- ekspor bobot hasil training (best.pt) ke format TFLite, siap ditaruh di
`assets/models/sawit_detector.tflite` pada project Flutter.

Jalankan di komputer yang sama tempat training dilakukan (butuh package yang sama di
requirements.txt -- export TFLite Ultralytics juga akan otomatis install beberapa dependency
tambahan seperti tensorflow saat pertama kali dipakai).

Cara pakai:
    python export_to_tflite.py --weights runs/detect/sawit_train/weights/best.pt

Opsi kuantisasi (memperkecil ukuran file & mempercepat inferensi di HP, dengan sedikit trade-off
akurasi):
    python export_to_tflite.py --weights best.pt --half        # float16 (disarankan, aman)
    python export_to_tflite.py --weights best.pt --int8 --data dataset/data.yaml
        # int8 lebih kecil/cepat lagi, tapi butuh --data (dataset kalibrasi) & akurasinya perlu
        # dicek ulang -- jangan langsung pakai tanpa uji coba dulu.
"""
import argparse
import shutil
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser(description="Ekspor bobot YOLO (best.pt) ke TFLite untuk aplikasi Flutter")
    ap.add_argument("--weights", required=True, help="Path ke best.pt hasil train_yolov8.py")
    ap.add_argument("--imgsz", type=int, default=640, help="Ukuran input model (samakan dengan --imgsz saat training, atau turunkan untuk lebih cepat di HP -- lihat catatan akurasi di README)")
    ap.add_argument("--half", action="store_true", help="Kuantisasi float16 (disarankan -- lebih kecil, akurasi nyaris sama)")
    ap.add_argument("--int8", action="store_true", help="Kuantisasi int8 (paling kecil/cepat, butuh --data untuk kalibrasi & wajib diuji ulang akurasinya)")
    ap.add_argument("--data", default=None, help="dataset/data.yaml -- wajib kalau pakai --int8 (dipakai untuk kalibrasi kuantisasi)")
    ap.add_argument("--out", default="sawit_detector.tflite", help="Nama file TFLite hasil akhir (langsung siap rename ke ini di assets/models/)")
    args = ap.parse_args()

    if args.int8 and not args.data:
        print("--int8 butuh --data dataset/data.yaml untuk kalibrasi. Tambahkan argumen itu.", file=sys.stderr)
        sys.exit(1)

    weights_path = Path(args.weights)
    if not weights_path.exists():
        print(f"File bobot tidak ditemukan: {weights_path}", file=sys.stderr)
        sys.exit(1)

    from ultralytics import YOLO

    print(f"Memuat bobot: {weights_path}")
    model = YOLO(str(weights_path))

    export_kwargs = dict(format="tflite", imgsz=args.imgsz)
    if args.half:
        export_kwargs["half"] = True
    if args.int8:
        export_kwargs["int8"] = True
        export_kwargs["data"] = args.data

    print(f"Mengekspor ke TFLite (imgsz={args.imgsz}, half={args.half}, int8={args.int8}) ...")
    exported_path = model.export(**export_kwargs)

    final_path = Path(args.out)
    shutil.copy(exported_path, final_path)

    print("\n=== Ekspor selesai ===")
    print(f"File TFLite: {final_path.resolve()}")
    print("\nLangkah berikutnya:")
    print(f"  1. Rename/salin '{final_path}' -> assets/models/sawit_detector.tflite di project Flutter")
    print("  2. Pastikan urutan kelas di assets/labels/labels.txt SAMA PERSIS dengan 'names' di dataset/data.yaml")
    print("  3. Aktifkan mode 'Model Custom (TFLite)' di layar Settings aplikasi, lalu uji di beberapa foto nyata")
    print("     sebelum dipakai penuh -- bandingkan hasilnya dengan koreksi manual dulu.")


if __name__ == "__main__":
    main()
