# assets/models/

Taruh file `sawit_detector.tflite` hasil training di folder ini (lihat
`training_pipeline/`) jika Anda ingin memakai mode "Model Custom (TFLite)".

Folder ini sengaja dikosongkan (belum ada model) karena belum ada dataset
foto janjang/brondol yang berlabel. Selama file belum ada, aplikasi tetap
berjalan normal memakai mode "CV Klasik" (lihat
`lib/services/cv_detection_service.dart`) yang tidak butuh model AI sama
sekali.
