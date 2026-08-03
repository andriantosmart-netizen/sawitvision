"""Auto-anotasi awal (pseudo-label) untuk foto janjang/brondol memakai
heuristik computer-vision yang BISA DISETEL (brightness/saturation/selisih
R-B + ukuran blob) — versi Python yang konsisten dengan panel "Deteksi
Otomatis (Bisa Disetel)" di `sawit_vision_web/koreksi.html`.

KENAPA "TANGKAI", BUKAN WARNA BUAH:
Untuk kelas **janjang**, deteksi berdasarkan warna buah (oranye/coklat)
TIDAK RELIABEL untuk foto tumpukan berisi banyak tandan yang saling
bersentuhan — blob warna buah antar-tandan menyatu sehingga jumlah blob
tidak mencerminkan jumlah tandan. Sesuai arahan lapangan: 1 tandan utuh
punya 1 bekas tangkai yang dipotong (khas warna krem/pucat & cerah,
berbeda dari buah yang jenuh warnanya tinggi) — jadi menghitung objek
berdasarkan bekas tangkai jauh lebih representatif untuk COUNTING per
tandan. Kelas **brondol** tetap pakai warna buah matang (oranye-kemerahan)
karena brondol memang butiran lepas, bukan tandan utuh.

INI BUKAN PENGGANTI KOREKSI MANUSIA. Hasilnya draft awal — periksa/koreksi
lewat koreksi.html (bisa import file `pre_annotations.json` di sini
sebagai draf kotak, lihat tombol "Import Pre-Anotasi (JSON)").

Kalibrasi (opsional):
Kalau sudah menemukan setelan slider yang pas di koreksi.html, klik
"Simpan Setelan" di sana untuk dapat `sawitvision_kalibrasi.json`, lalu
pakai di sini dengan --calibration supaya proses batch (mis. ratusan
foto sekaligus) konsisten dengan yang sudah diverifikasi visual di web.

Output:
- raw/images/*.jpeg           (copy foto asli)
- raw/labels/*.txt            (label YOLO: class_id x_center y_center w h)
- raw/sawitvision_labels.csv  (ringkasan jumlah objek per foto)
- raw/auto_annotations_preview/*.jpg  (foto + kotak digambar, untuk sanity check visual)
- pre_annotations.json        (format items[] yang sama dengan export koreksi.html,
                                 bisa diimpor lagi ke koreksi.html untuk dikoreksi)

Pemakaian:
    python auto_annotate_cv.py --images raw_batches/2026-07-16_SRIE1_TATA --out raw
    python auto_annotate_cv.py --images raw_batches/xxx --out raw \
        --calibration sawitvision_kalibrasi.json
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

WORKING_WIDTH = 480
# class_id 0, 1, 2 — harus sama dengan convert_web_annotations.py & prepare_dataset.py.
# "janjang_kosong" (tandan tanpa buah, setara Fraksi 5) saat ini MANUAL-ONLY di
# koreksi.html — belum ada profil auto-deteksi warna untuk kelas ini (lihat
# DEFAULT_PROFILES di bawah), jadi tidak ikut proses batch otomatis di sini.
CLASS_ORDER = ["janjang", "brondol", "janjang_kosong"]
BOX_COLOR = {"janjang": (46, 125, 50), "brondol": (230, 81, 0), "janjang_kosong": (198, 40, 40)}

# Default sama persis dengan default slider di koreksi.html (panel
# "Deteksi Otomatis (Bisa Disetel)"). minAreaRatio/maxAreaRatio di sini
# sudah dalam bentuk rasio (bukan nilai slider mentah).
DEFAULT_PROFILES = {
    "janjang": {  # bekas tangkai dipotong: krem/pucat, cerah, jenuh warna rendah
        "brightnessMin": 180,
        "saturationMax": 25,     # persen (0-100)
        "rMinusBMin": 12,
        "minAreaRatio": 0.0005,
        "maxAreaRatio": 0.03,
    },
    "brondol": {  # warna buah matang oranye-kemerahan (mirip cv_detection_service.dart)
        "brightnessMin": 100,
        "saturationMax": 100,
        "rMinusBMin": 40,
        "minAreaRatio": 0.00015,
        "maxAreaRatio": 0.01,
    },
}


def load_profiles(calibration_path):
    profiles = json.loads(json.dumps(DEFAULT_PROFILES))  # deep copy
    if not calibration_path:
        return profiles
    data = json.loads(Path(calibration_path).read_text(encoding="utf-8"))
    for cls in profiles:  # hanya kelas yang punya profil auto-deteksi (janjang, brondol)
        if cls not in data:
            continue
        p = data[cls]
        profiles[cls]["brightnessMin"] = p.get("brightnessMin", profiles[cls]["brightnessMin"])
        profiles[cls]["saturationMax"] = p.get("saturationMax", profiles[cls]["saturationMax"])
        profiles[cls]["rMinusBMin"] = p.get("rMinusBMin", profiles[cls]["rMinusBMin"])
        # koreksi.html menyimpan slider mentah (minAreaSlider/maxAreaSlider), bukan rasio langsung —
        # konversi kalau file kalibrasi berasal dari sana; kalau sudah berupa rasio, pakai apa adanya.
        if "minAreaSlider" in p:
            profiles[cls]["minAreaRatio"] = p["minAreaSlider"] / 10000
        elif "minAreaRatio" in p:
            profiles[cls]["minAreaRatio"] = p["minAreaRatio"]
        if "maxAreaSlider" in p:
            profiles[cls]["maxAreaRatio"] = p["maxAreaSlider"] / 1000
        elif "maxAreaRatio" in p:
            profiles[cls]["maxAreaRatio"] = p["maxAreaRatio"]
    return profiles


def pixel_mask(r, g, b, profile):
    """Sama persis logikanya dengan fungsi detectBlobs() di koreksi.html:
    brightness tinggi + saturasi rendah + R-B minimum tertentu."""
    r = r.astype(np.int16)
    g = g.astype(np.int16)
    b = b.astype(np.int16)
    maxc = np.maximum(np.maximum(r, g), b)
    minc = np.minimum(np.minimum(r, g), b)
    brightness = (r + g + b) / 3
    sat = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1), 0)
    return (
        (brightness >= profile["brightnessMin"])
        & (sat * 100 <= profile["saturationMax"])
        & ((r - b) >= profile["rMinusBMin"])
    )


def detect_blobs(arr, profile):
    """arr: HxWx3 uint8. Kembalikan list dict box ternormalisasi 0-1."""
    h, w = arr.shape[0], arr.shape[1]
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    mask = pixel_mask(r, g, b, profile)

    labeled, n = ndimage.label(mask, structure=ndimage.generate_binary_structure(2, 1))
    if n == 0:
        return []

    min_px = w * h * profile["minAreaRatio"]
    max_px = w * h * profile["maxAreaRatio"]

    boxes = []
    objs = ndimage.find_objects(labeled)
    for i, sl in enumerate(objs, start=1):
        if sl is None:
            continue
        ys, xs = sl
        count = int(np.sum(labeled[sl] == i))
        if count < min_px or count > max_px:
            continue
        boxes.append({
            "x": xs.start / w, "y": ys.start / h,
            "width": (xs.stop - xs.start) / w, "height": (ys.stop - ys.start) / h,
        })
    boxes.sort(key=lambda b: -(b["width"] * b["height"]))
    return boxes[:80]


def annotate_image(path, profiles):
    img = Image.open(path).convert("RGB")
    w0, h0 = img.size
    scale = WORKING_WIDTH / w0
    work_h = round(h0 * scale)
    small = img.resize((WORKING_WIDTH, work_h), Image.BILINEAR)
    arr = np.array(small)

    results = []
    for cls in profiles:  # hanya kelas yang punya profil auto-deteksi (janjang, brondol)
        for b in detect_blobs(arr, profiles[cls]):
            results.append({"class": cls, **b})
    return img, results


def draw_preview(img, boxes, out_path):
    preview = img.copy()
    draw = ImageDraw.Draw(preview)
    w, h = preview.size
    for b in boxes:
        x0 = b["x"] * w
        y0 = b["y"] * h
        x1 = x0 + b["width"] * w
        y1 = y0 + b["height"] * h
        color = BOX_COLOR.get(b["class"], (255, 0, 0))
        draw.rectangle([x0, y0, x1, y1], outline=color, width=3)
        draw.text((x0 + 3, max(0, y0 - 14)), b["class"], fill=color)
    preview.save(out_path, quality=85)


def box_to_yolo_line(box):
    class_id = CLASS_ORDER.index(box["class"])
    xc = box["x"] + box["width"] / 2
    yc = box["y"] + box["height"] / 2
    return f"{class_id} {xc:.6f} {yc:.6f} {box['width']:.6f} {box['height']:.6f}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--images", required=True, help="Folder foto mentah (jpg/jpeg/png)")
    parser.add_argument("--out", default="raw", help="Folder output (raw/images, raw/labels)")
    parser.add_argument("--calibration", default=None,
                         help="File JSON hasil 'Simpan Setelan' dari panel Deteksi Otomatis di koreksi.html")
    parser.add_argument("--max-boxes-per-image", type=int, default=80)
    args = parser.parse_args()

    profiles = load_profiles(args.calibration)
    print("Profil dipakai:")
    for cls in profiles:
        print(f"  {cls}: {profiles[cls]}")
    print(
        "  janjang_kosong: (belum ada profil auto-deteksi — tandai manual lewat koreksi.html)"
    )

    images_dir = Path(args.images)
    out = Path(args.out)
    (out / "images").mkdir(parents=True, exist_ok=True)
    (out / "labels").mkdir(parents=True, exist_ok=True)
    preview_dir = out / "auto_annotations_preview"
    preview_dir.mkdir(parents=True, exist_ok=True)

    image_files = sorted(
        p for p in images_dir.iterdir()
        if p.suffix.lower() in (".jpg", ".jpeg", ".png") and not p.name.startswith("_")
    )
    if not image_files:
        raise SystemExit(f"Tidak ada foto ditemukan di {images_dir}")

    items_for_koreksi = []
    csv_rows = []
    class_counts = {c: 0 for c in CLASS_ORDER}

    for path in image_files:
        img, boxes = annotate_image(path, profiles)
        boxes = boxes[: args.max_boxes_per_image]

        img.save(out / "images" / path.name, quality=95)
        label_lines = [box_to_yolo_line(b) for b in boxes]
        (out / "labels" / f"{path.stem}.txt").write_text(
            ("\n".join(label_lines) + "\n") if label_lines else "", encoding="utf-8"
        )
        draw_preview(img, boxes, preview_dir / path.name)

        jjg_count = sum(1 for b in boxes if b["class"] == "janjang")
        brd_count = sum(1 for b in boxes if b["class"] == "brondol")
        for b in boxes:
            class_counts[b["class"]] += 1

        items_for_koreksi.append({
            "file_name": path.name,
            "boxes": [{"class": b["class"], "x": b["x"], "y": b["y"],
                       "width": b["width"], "height": b["height"]} for b in boxes],
            "final_jumlah_janjang": jjg_count,
            "final_jumlah_janjang_kosong": 0,  # belum ada auto-deteksi untuk ini — isi manual di koreksi.html
            "final_jumlah_brondol": brd_count,
            "source_note": "auto-anotasi (bekas tangkai) — BELUM diperiksa manusia",
            "verified": False,
        })
        csv_rows.append((path.name, jjg_count, brd_count, len(boxes)))
        print(f"{path.name}: {jjg_count} janjang (tangkai), {brd_count} brondol (kotak={len(boxes)})")

    (out / "pre_annotations.json").write_text(
        json.dumps({"items": items_for_koreksi}, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    csv_path = out / "sawitvision_labels.csv"
    with open(csv_path, "w", encoding="utf-8") as f:
        f.write("file_name,auto_jumlah_janjang,auto_jumlah_brondol,jumlah_kotak\n")
        for row in csv_rows:
            f.write(",".join(str(x) for x in row) + "\n")

    print("\n=== Selesai auto-anotasi (PSEUDO-LABEL, belum diverifikasi manusia) ===")
    print(f"Total foto diproses    : {len(image_files)}")
    print(f"Total kotak per kelas  : {class_counts}")
    print(f"Label YOLO             : {out / 'labels'}")
    print(f"Preview visual (cek!)  : {preview_dir}")
    print(f"Import ke koreksi.html : {out / 'pre_annotations.json'}")


if __name__ == "__main__":
    main()
