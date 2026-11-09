import numpy as np
import tensorflow as tf
from pathlib import Path


# Lokasi model
MODEL_PATH = (
    Path(__file__).resolve().parent.parent
    / "models"
    / "si1_best.keras"
)


# Urutan label harus mengikuti class_id saat training
CLASS_LABELS = [
    "air",
    "belajar",
    "cari",
    "hari",
    "ingat",
    "lagi",
    "maaf",
    "makan",
    "motor",
    "saya",
    "terima kasih",
    "tuli",
    "apa",
    "siapa",
    "kapan",
    "di mana",
    "mengapa",
    "bagaimana",
    "merah",
    "kuning",
    "hijau",
    "hitam",
    "dengar",
    "berangkat",
    "datang",
    "teman",
    "keluarga",
    "rumah",
    "pagi",
    "siang",
    "sore",
    "malam",
]


# Memuat model satu kali
model = tf.keras.models.load_model(MODEL_PATH)


def predict(sequence):
    data = np.asarray(sequence, dtype=np.float32)

    if data.shape != (30, 66):
        raise ValueError(
            f"Input harus berukuran (30, 66), "
            f"diterima {data.shape}"
        )

    if not np.isfinite(data).all():
        raise ValueError("Input mengandung NaN atau Infinity")

    # Tambahkan dimensi batch
    data = np.expand_dims(data, axis=0)

    # Prediksi model
    probabilities = model.predict(data, verbose=0)[0]

    class_id = int(np.argmax(probabilities))

    return {
        "class_id": class_id,
        "label": CLASS_LABELS[class_id],
        "confidence": float(probabilities[class_id]),
    }