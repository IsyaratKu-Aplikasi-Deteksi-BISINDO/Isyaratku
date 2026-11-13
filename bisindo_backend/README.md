# BISINDO Backend

Backend FastAPI untuk aplikasi BISINDO Mobile yang digunakan untuk melakukan prediksi bahasa isyarat menggunakan model deep learning berbasis LSTM.

Backend menerima sequence landmark hasil ekstraksi MediaPipe Holistic dari aplikasi Android, kemudian memprosesnya menggunakan model yang telah dilatih.

## 1. Lokasi Proyek

Folder backend:

```text
C:\coding\IsyaratKu\bisindo_backend
```

Struktur direktori:

```text
bisindo_backend/
├── app/
│   ├── main.py
│   ├── models/
│   │   ├── si1_best.keras
│   │   └── si1_body_right_random_resampling_seed45.keras
│   ├── services/
│   │   └── model_service.py
│   └── __init__.py
├── venv/
├── requirements.txt
├── Dockerfile
├── .dockerignore
└── README.md
```

File utama:
- `app/main.py`: konfigurasi dan endpoint FastAPI.
- `app/services/model_service.py`: pemuatan model dan proses prediksi.
- `app/models/`: penyimpanan model hasil pelatihan.
- `requirements.txt`: daftar dependensi Python.
- `Dockerfile`: konfigurasi pembuatan Docker image.

Model yang digunakan oleh backend saat ini:

```text
si1_body_right_random_resampling_seed45.keras
```

## 2. Teknologi yang Digunakan

- Python 3.11
- FastAPI
- Uvicorn
- TensorFlow / Keras
- NumPy
- Docker

## 3. Arsitektur Backend

Alur komunikasi aplikasi:

```text
Android Application
        |
        v
MediaPipe Holistic
        |
        v
Landmark Extraction
        |
        v
Sequence 30 Frames
        |
        v
66 Features per Frame
        |
        v
HTTP POST Request
        |
        v
FastAPI Backend
        |
        v
LSTM Model
        |
        v
Prediction Result
        |
        v
Android Application
```

Input model terdiri dari:
- Panjang sequence: 30 frame.
- Jumlah fitur: 66 fitur per frame.
- Total nilai fitur: 1.980.

## 4. Menjalankan Backend Menggunakan Docker

Docker merupakan metode deployment backend yang sudah berhasil diuji pada lingkungan pengembangan.

### 4.1 Menjalankan Docker Desktop

Pastikan Docker Desktop sudah terinstal dan berjalan.

Periksa Docker melalui PowerShell:

```powershell
docker --version
docker info
```

### 4.2 Build Docker Image

Masuk ke folder backend:

```powershell
cd C:\coding\IsyaratKu\bisindo_backend
```

Build image:

```powershell
docker build -t bisindo-backend .
```

Proses ini akan membuat Docker image bernama `bisindo-backend`.

### 4.3 Menjalankan Container

Jalankan perintah:

```powershell
docker run -d --name bisindo-api -p 8000:8000 bisindo-backend:latest
```

Keterangan:
- `-d`: menjalankan container di background.
- `--name bisindo-api`: memberikan nama container.
- `-p 8000:8000`: menghubungkan port 8000 komputer dengan port 8000 container.

### 4.4 Memeriksa Status Container

```powershell
docker ps
```

Pastikan container `bisindo-api` memiliki status `Up`.

### 4.5 Memeriksa Log Backend

```powershell
docker logs bisindo-api
```

### 4.6 Memeriksa Koneksi Backend

Buka PowerShell:

```powershell
Invoke-RestMethod -Uri http://localhost:8000/health -Method GET
```

Jika berhasil, backend memberikan respons:

```json
{
  "status": "api siap di gunakan",
  "service": "BISINDO Mobile API"
}
```

Dokumentasi API dapat dibuka melalui browser:

```text
http://localhost:8000/docs
```

## 5. Menghubungkan Aplikasi Android

Aplikasi Android dapat mengakses backend melalui jaringan Wi-Fi yang sama dengan komputer.

### 5.1 Memeriksa IP Address Komputer

Jalankan:

```powershell
ipconfig
```

Cari bagian:

```text
Wireless LAN adapter Wi-Fi
```

Catat alamat `IPv4 Address`.

Contoh alamat yang digunakan pada pengujian:

```text
192.168.1.2
```

Catatan: IP tersebut merupakan alamat komputer pada jaringan Wi-Fi saat pengujian. Alamat dapat berubah sesuai konfigurasi jaringan.

### 5.2 Menguji Koneksi dari Android

Pastikan HP Android dan komputer terhubung ke jaringan Wi-Fi yang sama.

Buka browser Android:

```text
http://192.168.1.2:8000/health
```

Jika respons health check muncul, HP berhasil mengakses backend.

### 5.3 Konfigurasi ApiService Flutter

Pada file `ApiService.dart`, konfigurasi alamat backend:

```dart
static const String baseUrl = 'http://192.168.1.2:8000';
```

Endpoint prediksi:

```dart
static const String predictEndpoint = '/v1/predict';
```

Gunakan IPv4 aktual komputer jika alamat jaringan berubah.

## 6. Dokumentasi API

Backend menyediakan dua endpoint utama.

### 6.1 Health Check

| Informasi | Nilai |
|---|---|
| Method | GET |
| Endpoint | `/health` |
| Fungsi | Memeriksa status backend |

Contoh request:

```http
GET /health
```

Contoh response:

```json
{
  "status": "api siap di gunakan",
  "service": "BISINDO Mobile API"
}
```

### 6.2 Prediction

| Informasi | Nilai |
|---|---|
| Method | POST |
| Endpoint | `/v1/predict` |
| Content-Type | application/json |
| Fungsi | Melakukan prediksi bahasa isyarat |

Format request:

```json
{
  "sequence": [
    [0.1, 0.2, 0.3]
  ]
}
```

Catatan: Contoh di atas hanya ilustrasi struktur JSON. Request sebenarnya harus berisi tepat 30 frame dengan masing-masing 66 fitur numerik.

Contoh response:

```json
{
  "success": true,
  "prediction": {
    "class_id": 0,
    "label": "air",
    "confidence": 0.95
  }
}
```

Nilai confidence di atas hanya contoh format response, bukan hasil pengujian tertentu.

## 7. Menjalankan Backend Secara Lokal Tanpa Docker

Backend juga dapat dijalankan langsung menggunakan Python virtual environment.

Masuk ke folder backend:

```powershell
cd C:\coding\IsyaratKu\bisindo_backend
```

Aktifkan virtual environment:

```powershell
.\venv\Scripts\Activate.ps1
```

Jalankan Uvicorn:

```powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Biarkan terminal tetap terbuka selama backend digunakan.

## 8. Menghentikan dan Menjalankan Kembali Docker

### Menghentikan container

```powershell
docker stop bisindo-api
```

### Menjalankan kembali container

```powershell
docker start bisindo-api
```

### Menghapus container

Jika memang ingin menghapus container:

```powershell
docker stop bisindo-api
docker rm bisindo-api
```

Docker image tidak ikut terhapus ketika container dihapus.

## 9. Troubleshooting

### Container tidak berjalan

Periksa status:

```powershell
docker ps -a
```

Periksa log:

```powershell
docker logs bisindo-api
```

### Port 8000 sedang digunakan

Periksa proses yang menggunakan port:

```powershell
netstat -ano | findstr :8000
```

Pastikan tidak ada proses lain yang menggunakan port tersebut.

### HP tidak dapat mengakses backend

Per