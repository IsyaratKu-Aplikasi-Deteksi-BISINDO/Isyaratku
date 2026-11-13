# BISINDO Backend

Panduan menjalankan backend FastAPI untuk aplikasi BISINDO Mobile.

## 1. Lokasi proyek

Folder backend:

``` text
C:\coding\IsyaratKu\bisindo_backend
```

Struktur folder yang sudah diketahui:

``` text
bisindo_backend/
├── app/
│   ├── main.py
│   ├── models/
│   ├── services/
│   └── __init__.py
└── venv/
```

File utama FastAPI adalah `app/main.py`.

## 2. Menjalankan backend

Buka PowerShell, lalu masuk ke folder backend:

``` powershell
cd C:\coding\IsyaratKu\bisindo_backend
```

Aktifkan virtual environment jika belum aktif:

``` powershell
.\venv\Scripts\Activate.ps1
```

Jika berhasil, prompt PowerShell akan diawali dengan `(venv)`.

Jalankan FastAPI:

``` powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

Biarkan terminal ini tetap terbuka selama aplikasi mobile menggunakan
backend.

## 3. Memastikan backend aktif

Saat berhasil, Uvicorn akan menampilkan pesan yang kurang lebih seperti:

``` text
Uvicorn running on http://0.0.0.0:8000
```

Buka alamat berikut dari browser laptop:

-   Halaman backend: http://127.0.0.1:8000
-   Dokumentasi API: http://127.0.0.1:8000/docs

Jika halaman dokumentasi API terbuka, server dapat diakses dari laptop.

## 4. Menghubungkan aplikasi Android

Agar HP Android dapat mengakses backend di laptop:

1.  Pastikan laptop dan HP terhubung ke jaringan Wi-Fi yang sama.

2.  Jalankan backend dengan `--host 0.0.0.0` seperti command di atas.

3.  Cari alamat IPv4 laptop menggunakan PowerShell:

    ``` powershell
    ipconfig
    ```

4.  Cari bagian adapter Wi-Fi yang sedang digunakan, lalu catat
    `IPv4 Address`.

5.  Pastikan konfigurasi alamat API di aplikasi Flutter menggunakan
    alamat IP laptop dan port `8000`, bukan `127.0.0.1` atau
    `localhost`.

Format alamat dari HP:

``` text
http://ALAMAT_IP_LAPTOP:8000
```

Contoh format saja (bukan alamat laptop yang sebenarnya):

``` text
http://192.168.1.10:8000
```

Gunakan alamat IP aktual dari hasil `ipconfig`. Path endpoint API harus
mengikuti endpoint yang didefinisikan di `app/main.py` dan konfigurasi
`ApiService` pada aplikasi Flutter.

## 5. Menghentikan backend

Untuk menghentikan server, fokuskan terminal yang menjalankan Uvicorn,
lalu tekan:

``` text
Ctrl + C
```

## 6. Menjalankan kembali di lain waktu

Setiap kali ingin menggunakan backend:

1.  Buka PowerShell.
2.  Masuk ke folder `C:\coding\IsyaratKu\bisindo_backend`.
3.  Aktifkan `venv` jika belum aktif.
4.  Jalankan command Uvicorn pada bagian 2.
5.  Biarkan terminal tetap berjalan saat aplikasi digunakan.

## 7. Troubleshooting singkat

### Perintah `uvicorn` tidak dikenali

Pastikan virtual environment aktif. Gunakan bentuk command berikut agar
Python dari environment yang aktif menjalankan Uvicorn:

``` powershell
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

### Port 8000 sedang digunakan

Artinya kemungkinan ada proses lain yang sedang memakai port tersebut.
Periksa proses yang memakai port 8000 sebelum menghentikannya atau
memilih port lain. Jika port diganti, alamat di aplikasi Flutter juga
harus disesuaikan.

### HP tidak bisa terhubung ke backend

Periksa hal-hal berikut:

-   Backend masih berjalan dan terminal Uvicorn belum ditutup.
-   Backend dijalankan dengan `--host 0.0.0.0`.
-   Laptop dan HP berada pada jaringan yang sama.
-   Aplikasi Flutter menggunakan IPv4 laptop, bukan `localhost` atau
    `127.0.0.1`.
-   Firewall Windows tidak memblokir koneksi masuk pada port 8000.

### Dokumentasi `/docs` tidak terbuka

Pastikan server sudah menampilkan pesan Uvicorn berjalan dan periksa
pesan error pada terminal.

------------------------------------------------------------------------

**Command utama yang perlu diingat:**

``` powershell
cd C:\coding\IsyaratKu\bisindo_backend
.\venv\Scripts\Activate.ps1
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```
