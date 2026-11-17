#!/usr/bin/env bash
#
# Memperbarui Konver Soal dan Konvert User di server ke versi terbaru di GitHub (TANPA sudo).
# Jalankan sebagai pemilik /srv/apps (mis. smiler):
#   bash /opt/web_ujian_gabung/perbarui.sh
#
# Layanan Kirim dijalankan ulang otomatis oleh systemd bila server/kirim.js berubah.
# Opsi --tanpa-pull: hanya menyalin isi folder ini (dipakai oleh pasang.sh).
#
set -euo pipefail

KODE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_APPS=/srv/apps

if [[ "${1:-}" != "--tanpa-pull" ]]; then
  echo "==> Mengambil versi terbaru dari GitHub"
  git -C "$KODE" fetch --quiet origin main
  git -C "$KODE" reset --quiet --hard origin/main
fi
echo "    Versi: $(git -C "$KODE" log -1 --format='%h %s' 2>/dev/null || echo '-')"

[[ -w "$ROOT_APPS/konver-soal" && -w "$ROOT_APPS/user" ]] ||
  { echo "Folder $ROOT_APPS belum siap atau bukan milik $(id -un). Jalankan dulu pasang.sh dengan sudo." >&2; exit 1; }

echo "==> Menyalin Konver Soal ke $ROOT_APPS/konver-soal"
rsync -a --delete --chmod=D755,F644 --exclude '*.md' "$KODE/konver-soal/" "$ROOT_APPS/konver-soal/"
echo "==> Menyalin Konvert User ke $ROOT_APPS/user"
rsync -a --delete --chmod=D755,F644 "$KODE/user/" "$ROOT_APPS/user/"

echo "==> Selesai. Konver Soal V$(tr -d '\r\n' < "$ROOT_APPS/konver-soal/VERSION" 2>/dev/null || echo '?')"
