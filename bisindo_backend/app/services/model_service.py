
import numpy as np
import tensorflow as tf
from pathlib import Path


# =====================================================
# MODEL CONFIGURATION
# =====================================================

MODEL_PATH = (
    Path(__file__).resolve().parent.parent
    / "models"
    / "si1_body_right_random_resampling_seed45.keras"
)

SEQUENCE_LENGTH = 30
FEATURE_DIMENSION = 66


# =====================================================
# CLASS LABELS
# Urutan harus sesuai class_id saat training
# =====================================================

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


# =====================================================
# LOAD MODEL
# =====================================================

if not MODEL_PATH.exists():
    raise FileNotFoundError(
        f"Model tidak ditemukan: {MODEL_PATH}"
    )

model = tf.keras.models.load_model(MODEL_PATH)

print("\n======================================")
print("MODEL BERHASIL DIMUAT")
print("======================================")
print(f"Model file  : {MODEL_PATH.name}")
print(f"Input shape : {model.input_shape}")
print(f"Output shape: {model.output_shape}")
print("Jumlah kelas:", len(CLASS_LABELS))
print("======================================\n")


# =====================================================
# PREDICTION
# =====================================================

def predict(sequence):

    # -------------------------------------------------
    # 1. CONVERT INPUT
    # -------------------------------------------------

    data = np.asarray(sequence, dtype=np.float32)

    # -------------------------------------------------
    # 2. VALIDATE INPUT SHAPE
    # -------------------------------------------------

    expected_shape = (
        SEQUENCE_LENGTH,
        FEATURE_DIMENSION
    )

    if data.shape != expected_shape:
        raise ValueError(
            f"Input harus berukuran {expected_shape}, "
            f"tetapi menerima {data.shape}"
        )

    # -------------------------------------------------
    # 3. VALIDATE NUMERICAL VALUES
    # -------------------------------------------------

    if not np.isfinite(data).all():
        raise ValueError(
            "Input mengandung nilai NaN atau infinity"
        )

    # -------------------------------------------------
    # 4. INPUT DEBUGGING
    # -------------------------------------------------

    print("\n========== INPUT DEBUG ==========")

    print("Shape:", data.shape)
    print("Min:", float(np.min(data)))
    print("Max:", float(np.max(data)))
    print("Mean:", float(np.mean(data)))
    print("Std:", float(np.std(data)))

    non_zero = np.count_nonzero(data)

    print("Non-zero values:", non_zero)
    print("Total values:", data.size)

    zero_percentage = (
        (data.size - non_zero) / data.size
    ) * 100

    print(f"Zero percentage: {zero_percentage:.2f}%")

    print("\nNon-zero values per frame:")

    for frame_idx in range(SEQUENCE_LENGTH):
        frame_non_zero = np.count_nonzero(
            data[frame_idx]
        )

        print(
            f"Frame {frame_idx + 1:02d}: "
            f"{frame_non_zero}/{FEATURE_DIMENSION}"
        )

    print("=================================")

    # -------------------------------------------------
    # 5. LANDMARK DEBUGGING
    # -------------------------------------------------

    print("\n========== LANDMARK DEBUG ==========")

    landmark_results = []

    for i, frame in enumerate(data):
        body_count = int(
            np.count_nonzero(frame[:24])
        )

        right_hand_count = int(
            np.count_nonzero(frame[24:66])
        )

        landmark_results.append(
            (i + 1, body_count, right_hand_count)
        )

    for frame_number, body_count, right_hand_count in landmark_results:
        print(
            f"Frame {frame_number:02d}: "
            f"Body {body_count}/24 | "
            f"Right Hand {right_hand_count}/42"
        )

    print("Total frames:", len(landmark_results))
    print("====================================")

    # -------------------------------------------------
    # 6. MODEL PREDICTION
    # -------------------------------------------------

    batch_data = np.expand_dims(data, axis=0)

    probabilities = model.predict(
        batch_data,
        verbose=0
    )[0]

    # -------------------------------------------------
    # 7. VALIDATE MODEL OUTPUT
    # -------------------------------------------------

    if probabilities.shape != (len(CLASS_LABELS),):
        raise ValueError(
            f"Output model tidak sesuai: "
            f"{probabilities.shape}"
        )

    if not np.isfinite(probabilities).all():
        raise ValueError(
            "Output model mengandung NaN atau infinity"
        )

    # -------------------------------------------------
    # 8. GET PREDICTED CLASS
    # -------------------------------------------------

    class_id = int(np.argmax(probabilities))

    # -------------------------------------------------
    # 9. TOP 5 PREDICTIONS
    # -------------------------------------------------

    top_indices = np.argsort(probabilities)[::-1][:5]

    print("\n========== PREDICTION DEBUG ==========")

    for rank, idx in enumerate(top_indices, start=1):
        print(
            f"{rank}. {CLASS_LABELS[idx]}: "
            f"{probabilities[idx] * 100:.2f}%"
        )

    print("--------------------------------------")

    print("Predicted class ID:", class_id)
    print("Predicted label:", CLASS_LABELS[class_id])

    print(
        "Confidence:",
        f"{probabilities[class_id] * 100:.2f}%"
    )

    print("======================================\n")

    # -------------------------------------------------
    # 10. RETURN RESULT
    # -------------------------------------------------

    return {
        "class_id": class_id,
        "label": CLASS_LABELS[class_id],
        "confidence": float(probabilities[class_id]),
    }
