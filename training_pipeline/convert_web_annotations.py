"""Mengonversi hasil export dari halaman web "Koreksi & Bounding Box"
(koreksi.html -> tombol "Export Anotasi (JSON)") menjadi struktur
`raw/images` + `raw/labels` (format YOLO) yang siap dipakai oleh
prepare_dataset.py.

Pemakaian:
    python convert_web_annotations.py \
        --json sawitvision_annotations.json \
        --images /path/ke/folder/foto_asli \
        --out raw

Setelah ini jalankan seperti biasa:
    python prepare_dataset.py --raw raw --out dataset
    python train_yolov8.py --data dataset/data.yaml

Catatan:
- Hanya foto yang sudah ditandai "verified" (dicentang di koreksi.html)
  yang diikutkan secara default — pakai --include-unverified untuk
  mengikutkan semua foto termasuk yang belum dikoreksi/dicek.
- Foto tanpa kotak sama sekali tetap dicatat di CSV ringkasan, tapi
  dilewati dari dataset YOLO (tidak ada objek untuk dipelajari).
- Brondol TIDAK dihitung butir satu-satu di koreksi.html — tiap kotak oranye
  mewakili 1 TUMPUKAN. "final_jumlah_brondol_kg" di CSV ringkasan = jumlah
  tumpukan x kalibrasi berat/tumpukan (kg, disetel di koreksi.html — default
  5 kg, bisa 3/7/custom). Kalibrasi yang dipakai saat export ikut dicatat di
  kolom "brondol_pile_weight_kg" untuk audit/referensi.
- Fitur "Cek Foto Duplikat" di koreksi.html cuma memberi INDIKASI (skor
  kemiripan warna/pola, bukan kepastian) — foto yang tersangkut ditandai
  "is_duplicate_suspect" + daftar file mirip di kolom "duplicate_matches" pada
  CSV ringkasan, supaya bisa direview manual. Secara default foto ini TETAP
  diikutkan ke dataset YOLO (indikasi belum tentu benar duplikat) — pakai
  --exclude-duplicates untuk membuang foto yang terindikasi dari dataset.
"""
import argparse
import csv
import json
import shutil
from pathlib import Path

CLASS_ORDER = ["janjang", "brondol", "janjang_kosong"]  # class_id 0, 1, 2 — harus sama dengan prepare_dataset.py


def box_to_yolo_line(box):
    class_id = CLASS_ORDER.index(box["class"])
    x_center = box["x"] + box["width"] / 2
    y_center = box["y"] + box["height"] / 2
    return f"{class_id} {x_center:.6f} {y_center:.6f} {box['width']:.6f} {box['height']:.6f}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--json", required=True, help="File sawitvision_annotations.json hasil export")
    parser.add_argument("--images", required=True, help="Folder tempat foto asli (nama file harus sama persis)")
    parser.add_argument("--out", default="raw", help="Folder output (raw/images, raw/labels)")
    parser.add_argument(
        "--include-unverified",
        action="store_true",
        help="Ikutkan juga foto yang belum dicentang 'verified' di koreksi.html",
    )
    parser.add_argument(
        "--exclude-duplicates",
        action="store_true",
        help="Buang foto yang ditandai 'is_duplicate_suspect' (indikasi duplikat) dari dataset YOLO",
    )
    args = parser.parse_args()

    data = json.loads(Path(args.json).read_text(encoding="utf-8"))
    items = data.get("items", [])
    brondol_pile_weight_kg = data.get("brondol_pile_weight_kg")
    images_dir = Path(args.images)
    out = Path(args.out)
    (out / "images").mkdir(parents=True, exist_ok=True)
    (out / "labels").mkdir(parents=True, exist_ok=True)

    included = 0
    skipped_unverified = 0
    skipped_missing = 0
    skipped_no_boxes = 0
    skipped_duplicate = 0
    class_counts = {c: 0 for c in CLASS_ORDER}

    summary_rows = []

    for item in items:
        file_name = item["file_name"]
        src = images_dir / file_name
        summary_rows.append(
            {
                "file_name": file_name,
                "verified": item.get("verified", False),
                "final_jumlah_janjang": item.get("final_jumlah_janjang"),
                "final_jumlah_janjang_kosong": item.get("final_jumlah_janjang_kosong"),
                "jumlah_tumpukan_brondol": item.get(
                    "jumlah_tumpukan_brondol",
                    sum(1 for b in item.get("boxes", []) if b.get("class") == "brondol"),
                ),
                "final_jumlah_brondol_kg": item.get("final_jumlah_brondol"),
                "brondol_pile_weight_kg": brondol_pile_weight_kg,
                "source_note": item.get("source_note", ""),
                "jumlah_kotak": len(item.get("boxes", [])),
                "is_duplicate_suspect": item.get("is_duplicate_suspect", False),
                "duplicate_matches": "; ".join(
                    f"{m.get('file_name')} ({m.get('score')}%)" for m in item.get("duplicate_matches", [])
                ),
            }
        )

        if not item.get("verified") and not args.include_unverified:
            skipped_unverified += 1
            continue
        if args.exclude_duplicates and item.get("is_duplicate_suspect"):
            skipped_duplicate += 1
            continue
        if not src.exists():
            print(f"[peringatan] file tidak ditemukan, dilewati: {src}")
            skipped_missing += 1
            continue
        boxes = item.get("boxes", [])
        if not boxes:
            skipped_no_boxes += 1
            continue

        shutil.copy(src, out / "images" / file_name)
        label_path = out / "labels" / f"{Path(file_name).stem}.txt"
        lines = []
        for box in boxes:
            lines.append(box_to_yolo_line(box))
            class_counts[box["class"]] += 1
        label_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        included += 1

    # Simpan ringkasan level-bisnis (jumlah janjang/brondol final per foto) terpisah
    # dari label YOLO — ini yang dipakai untuk kalibrasi grading, bukan training model.
    csv_path = out / "sawitvision_labels.csv"
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "file_name",
                "verified",
                "final_jumlah_janjang",
                "final_jumlah_janjang_kosong",
                "jumlah_tumpukan_brondol",
                "final_jumlah_brondol_kg",
                "brondol_pile_weight_kg",
                "source_note",
                "jumlah_kotak",
                "is_duplicate_suspect",
                "duplicate_matches",
            ],
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    print("=== Selesai ===")
    print(f"Foto diikutkan ke dataset YOLO : {included}")
    print(f"Dilewati (belum verified)      : {skipped_unverified}")
    print(f"Dilewati (terindikasi duplikat): {skipped_duplicate}")
    print(f"Dilewati (file tidak ditemukan): {skipped_missing}")
    print(f"Dilewati (tidak ada kotak)     : {skipped_no_boxes}")
    print(f"Total kotak per kelas          : {class_counts}")
    print(f"Ringkasan lengkap disimpan di  : {csv_path}")
    print(f"\nLangkah berikutnya:")
    print(f"  python prepare_dataset.py --raw {out} --out dataset")
    print(f"  python train_yolov8.py --data dataset/data.yaml")


if __name__ == "__main__":
    main()
