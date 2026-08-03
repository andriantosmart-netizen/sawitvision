# assets/models/

Berisi `sawit_detector.tflite` -- model YOLO26n hasil training custom (lihat
`training_pipeline/`), dipasang 2026-08-03.

Status data training saat model ini dibuat: 76 foto lapangan terverifikasi
(2 sesi pemotretan), dengan 582 kotak janjang, 91 kotak brondol, dan hanya 6
kotak janjang_kosong -- karena itu kelas `janjang_kosong` kemungkinan besar
masih sangat lemah/jarang terdeteksi, sedangkan janjang & brondol sudah jauh
lebih baik dari mode CV Klasik (bisa memisahkan tandan yang saling menempel
jadi kotak individual).

Urutan kelas HARUS SAMA PERSIS dengan `assets/labels/labels.txt` (index 0, 1,
2): `janjang`, `brondol`, `janjang_kosong`. Jangan ubah urutan salah satu file
tanpa mengubah yang lain.

Kalau nanti melatih ulang model (ronde 2, dengan lebih banyak/lebih beragam
foto terverifikasi lewat koreksi.html), timpa file ini dengan hasil baru dari
`training_pipeline/export_to_tflite.py` atau notebook Colab-nya, lalu update
catatan status data di atas.

Selama file `sawit_detector.tflite` ADA di folder ini (seperti sekarang),
mode "Model Custom (TFLite)" di Settings bisa dipakai. Kalau file ini
dihapus, aplikasi otomatis fallback ke mode "CV Klasik" (lihat
`lib/services/cv_detection_service.dart`), tidak crash.
