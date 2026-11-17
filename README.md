# Web Ujian Gabung

Dua aplikasi ujian SMAN 2 Makassar dalam satu server:

| Alamat | Aplikasi |
|---|---|
| `http://IP-SERVER/` | **Konver Soal**: merapikan soal Word ke RTF ExamView, tombol Kirim ke email, halaman admin (`/#admin`) |
| `http://IP-SERVER/ujian/` | **Web Ujian**: konverter jadwal, user CBT, kelas moving, Moodle |

Repo ini berisi hasil siap pakai. Kode sumbernya ada di
[ichalsmiler/konver-soal](https://github.com/ichalsmiler/konver-soal) dan
[ichalsmiler/web-ujian](https://github.com/ichalsmiler/web-ujian).

## Pasang (sekali, Debian 12/13)

Masuk ke server (mis. sebagai `smiler`), lalu jalankan sebagai root. Debian minimal belum punya `sudo`, jadi pakai `su` (sandi root):

```bash
su -c "curl -fsSL https://raw.githubusercontent.com/ichalsmiler/web_ujian_gabung/main/pasang.sh | bash"
```

Bila `sudo` sudah ada: `curl -fsSL https://raw.githubusercontent.com/ichalsmiler/web_ujian_gabung/main/pasang.sh | sudo bash`.
File aplikasi dimiliki user pemanggil sudo, atau `smiler` bila dijalankan sebagai root (ganti dengan `PEMILIK=namauser`).

Skrip ini memasang sudo, nginx, Node.js, git, dan rsync; mengunduh repo ke `/opt/web_ujian_gabung`; menyalin
aplikasi ke `/srv/apps/konver-soal` dan `/srv/apps/ujian`; memasang layanan `konver-soal-kirim`
(berjalan sebagai user tadi); dan membuat situs nginx. Saat pertama dipasang, skrip menanyakan:

- alamat email pengirim (Enter = `kirimsoal@sman2makassar.sch.id`) dan **App Password Gmail**;
- **kata sandi admin** Konver Soal.

Keduanya disimpan di `/etc/konver-soal/kirim.env` (hanya root). Menjalankan ulang skrip ini aman.

## Update (tanpa sudo)

```bash
bash /opt/web_ujian_gabung/perbarui.sh
```

Layanan Kirim dijalankan ulang otomatis bila `server/kirim.js` berubah.

## Data

- Daftar guru (hasil impor) dan pengaturan admin: `/var/lib/konver-soal/` (`guru.json`, `pengaturan.json`).
- Web Ujian tidak menyimpan apa pun di server: file jadwal dan data siswa diproses di browser.

## Menyusun ulang repo ini (komputer pengembang)

Dengan `konver-soal` dan `web-ujian` di folder sebelah: `bash kumpulkan.sh`, lalu commit dan push.
`SUMBER.txt` mencatat commit sumber yang dipakai.
