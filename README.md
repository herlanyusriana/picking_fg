# Picking FG (Finished Goods)

Aplikasi mobile Flutter untuk proses picking barang jadi (Finished Goods) di warehouse. Terintegrasi dengan sistem [Material Incoming](https://github.com/herlanyusriana/material_incoming) sebagai backend API.

## Fitur

- **Barcode Scanner** - Scan part number menggunakan kamera untuk proses picking
- **Picking per Delivery Order** - Picking dikelompokkan berdasarkan Delivery Order (DO)
- **Multi-DO Selector** - Jika part ada di beberapa DO, user bisa pilih DO yang dituju
- **Progress Tracking** - Tampilan progress picking per DO dengan persentase
- **Auto Delivery Note** - Notifikasi otomatis saat semua picking untuk satu DO selesai dan Surat Jalan (Delivery Note) dibuat otomatis
- **Trip Grouping** - Pengelompokan berdasarkan trip number untuk efisiensi pengiriman

## Tech Stack

- **Flutter** (Dart SDK ^3.10.8)
- **Dependencies:**
  - `http` - HTTP client untuk komunikasi API
  - `mobile_scanner` - Barcode/QR scanner
  - `shared_preferences` - Local storage untuk auth token
  - `intl` - Date/number formatting

## Struktur Proyek

```
lib/
├── config.dart              # Konfigurasi API URL & timeout
├── main.dart                # Entry point
├── models/
│   └── picking_item.dart    # Model data picking item
├── screens/
│   ├── home_screen.dart     # Halaman utama picking list
│   ├── login_screen.dart    # Halaman login
│   └── scanner_screen.dart  # Halaman barcode scanner
└── services/
    └── api_service.dart     # API client service
```

## Setup

1. Clone repository
   ```bash
   git clone https://github.com/herlanyusriana/picking_fg.git
   cd picking_fg
   ```

2. Install dependencies
   ```bash
   flutter pub get
   ```

3. Konfigurasi API URL di `lib/config.dart`
   ```dart
   static const String baseUrl = 'https://your-api-url.com/api';
   ```

4. Run
   ```bash
   flutter run
   ```

## API Endpoints

Aplikasi ini menggunakan API dari backend Material Incoming:

| Method | Endpoint | Deskripsi |
|--------|----------|-----------|
| GET | `/api/picking-fg` | List picking items by date |
| GET | `/api/picking-fg/status` | Summary status picking |
| GET | `/api/picking-fg/lookup` | Lookup part by part_no |
| POST | `/api/picking-fg/update` | Update qty picked |

## Alur Kerja

1. Login dengan akun Material Incoming
2. Pilih tanggal delivery
3. Scan barcode part number atau pilih dari list
4. Input jumlah qty yang di-pick
5. Jika part ada di beberapa DO, pilih DO tujuan
6. Sistem update progress picking
7. Saat semua item dalam satu DO selesai di-pick, Delivery Note (Surat Jalan) otomatis dibuat

## Build APK

```bash
flutter build apk --release
```

Output APK: `build/app/outputs/flutter-apk/app-release.apk`
