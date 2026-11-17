#!/usr/bin/env bash
#
# Web Ujian Gabung: memasang DUA aplikasi di SATU server Debian 12/13 (dengan sudo):
#   http://IP-SERVER/        -> Konver Soal (+ layanan Kirim soal ke email, halaman admin)
#   http://IP-SERVER/ujian/  -> Web Ujian (konverter jadwal & user CBT)
#
# Pemakaian (file aplikasi akan dimiliki user biasa, mis. smiler):
#   sebagai root (Debian minimal tanpa sudo):
#     su -c "curl -fsSL https://raw.githubusercontent.com/ichalsmiler/web_ujian_gabung/main/pasang.sh | bash"
#   atau bila sudo sudah ada:
#     curl -fsSL https://raw.githubusercontent.com/ichalsmiler/web_ujian_gabung/main/pasang.sh | sudo bash
#
# Kode diunduh ke /opt/web_ujian_gabung, file aplikasi disalin ke /srv/apps/... (milik user itu).
# Update berikutnya TANPA sudo:  bash /opt/web_ujian_gabung/perbarui.sh
# Menjalankan ulang skrip ini aman (pengaturan email & sandi admin yang sudah ada dipertahankan).
#
set -euo pipefail

REPO="${REPO:-https://github.com/ichalsmiler/web_ujian_gabung.git}"
CABANG="${CABANG:-main}"
KODE=/opt/web_ujian_gabung
# Pemilik file aplikasi: pemanggil sudo, atau PEMILIK=..., atau user "smiler" bila ada.
PEMILIK="${PEMILIK:-${SUDO_USER:-}}"
if [[ -z "$PEMILIK" || "$PEMILIK" == root ]] && id smiler >/dev/null 2>&1; then PEMILIK=smiler; fi
ROOT_APPS=/srv/apps
KONVER="$ROOT_APPS/konver-soal"
UJIAN="$ROOT_APPS/ujian"
STATE=/var/lib/konver-soal
ENV_DIR=/etc/konver-soal
ENV_FILE="$ENV_DIR/kirim.env"
SVC=konver-soal-kirim
KIRIM_PORT=3091
MAIL_TO="${MAIL_TO:-terimasoal@sman2makassar.sch.id}"
SITE=/etc/nginx/sites-available/apps

c_ok=$'\e[32m'; c_warn=$'\e[33m'; c_err=$'\e[31m'; c_off=$'\e[0m'
info() { echo "${c_ok}==>${c_off} $*"; }
warn() { echo "${c_warn}[!]${c_off} $*"; }
die()  { echo "${c_err}[x]${c_off} $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Jalankan sebagai root (su -) atau dengan sudo."
[[ -n "$PEMILIK" && "$PEMILIK" != root ]] || die "Tentukan pemilik file aplikasi, mis.: PEMILIK=smiler bash pasang.sh"
id "$PEMILIK" >/dev/null 2>&1 || die "User $PEMILIK tidak ada."
command -v apt-get >/dev/null || die "Skrip ini untuk Debian/Ubuntu."

# ---------- Paket ----------
info "Memasang paket: nginx nodejs git rsync curl"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq </dev/null
apt-get install -y -qq sudo nginx nodejs git rsync curl ca-certificates </dev/null >/dev/null
echo "    nginx $(nginx -v 2>&1 | sed 's/.*\///'), Node.js $(node --version)"

# ---------- Kode dari GitHub (milik $PEMILIK, agar update tidak perlu sudo) ----------
if [[ -d "$KODE/.git" ]]; then
  info "Mengambil versi terbaru di $KODE"
  chown -R "$PEMILIK:$PEMILIK" "$KODE"
  runuser -u "$PEMILIK" -- git -C "$KODE" fetch --quiet origin "$CABANG"
  runuser -u "$PEMILIK" -- git -C "$KODE" reset --quiet --hard "origin/$CABANG"
else
  info "Mengunduh $REPO ke $KODE"
  install -d -o "$PEMILIK" -g "$PEMILIK" "$KODE"
  runuser -u "$PEMILIK" -- git clone --quiet --branch "$CABANG" "$REPO" "$KODE" </dev/null
fi
echo "    Versi: $(runuser -u "$PEMILIK" -- git -C "$KODE" log -1 --format='%h %s')"

# ---------- Folder ----------
info "Menyiapkan folder aplikasi (milik $PEMILIK)"
install -d -m 755 -o "$PEMILIK" -g "$PEMILIK" "$ROOT_APPS" "$KONVER" "$UJIAN"
install -d -m 750 -o "$PEMILIK" -g "$PEMILIK" "$STATE"
install -d -m 755 "$ENV_DIR"
# nginx (www-data) cukup membaca file aplikasi
chmod o+rx "$ROOT_APPS" "$KONVER" "$UJIAN"
info "Menyalin aplikasi ke $ROOT_APPS"
runuser -u "$PEMILIK" -- bash "$KODE/perbarui.sh" --tanpa-pull

# ---------- Pengaturan email & sandi admin (rahasia, hanya root) ----------
if [[ ! -f "$ENV_FILE" ]]; then
  cat > "$ENV_FILE" <<ENV
# Akun Gmail pengirim untuk tombol "Kirim" + kata sandi admin Konver Soal
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=
SMTP_PASS=
MAIL_TO=${MAIL_TO}
MAIL_FROM_NAME=Konver Soal
PORT=${KIRIM_PORT}
HOST=127.0.0.1
RATE_PER_HOUR=20
ADMIN_PASS=
ENV
fi
chmod 600 "$ENV_FILE"
set_env() { # set_env KUNCI NILAI (nilai tidak ditampilkan)
  local tmp; tmp="$(mktemp)"
  grep -v "^$1=" "$ENV_FILE" > "$tmp" || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  install -m 600 "$tmp" "$ENV_FILE"; rm -f "$tmp"
}
punya() { grep -q "^$1=.\+" "$ENV_FILE"; }

if [[ -r /dev/tty ]]; then
  if ! punya SMTP_USER || ! punya SMTP_PASS; then
    echo
    info "Akun Gmail pengirim untuk tombol Kirim (sama dengan di server lama; Enter = lewati dulu)"
    read -r -p "    Alamat email pengirim [kirimsoal@sman2makassar.sch.id]: " U </dev/tty
    U="${U:-kirimsoal@sman2makassar.sch.id}"
    read -r -s -p "    App Password Gmail (16 huruf, tidak tampil; Enter = lewati): " P </dev/tty; echo
    P="$(printf '%s' "$P" | tr -d '[:space:][:cntrl:]')"
    if [[ -n "$P" ]]; then set_env SMTP_USER "$U"; set_env SMTP_PASS "$P"; info "Akun pengirim disimpan."
    else warn "Akun pengirim dilewati: tombol Kirim belum aktif. Jalankan ulang skrip ini untuk mengisinya."; fi
  fi
  if ! punya ADMIN_PASS; then
    echo
    info "Kata sandi admin Konver Soal (min. 8 karakter, tanpa spasi/tanda kutip; Enter = lewati)"
    read -r -s -p "    Kata sandi admin: " A </dev/tty; echo
    if [[ -n "$A" ]]; then
      read -r -s -p "    Ulangi kata sandi admin: " A2 </dev/tty; echo
      [[ "$A" == "$A2" ]] || die "Kata sandi tidak sama."
      (( ${#A} >= 8 )) || die "Kata sandi admin minimal 8 karakter."
      [[ "$A" != *[\"\'\\[:space:]]* ]] || die "Kata sandi admin tidak boleh berisi spasi atau tanda kutip."
      set_env ADMIN_PASS "$A"; info "Kata sandi admin disimpan."
    else warn "Sandi admin dilewati: halaman admin belum bisa dipakai."; fi
  fi
fi

# ---------- Layanan Kirim (berjalan sebagai $PEMILIK) ----------
info "Memasang layanan $SVC"
cat > "/etc/systemd/system/$SVC.service" <<UNIT
[Unit]
Description=Konver Soal - layanan kirim soal ke email & pengaturan admin
After=network-online.target
Wants=network-online.target
ConditionPathExists=$KONVER/server/kirim.js

[Service]
User=$PEMILIK
Group=$PEMILIK
EnvironmentFile=$ENV_FILE
Environment=STATE_DIR=$STATE
ExecStart=$(command -v node) $KONVER/server/kirim.js
Restart=on-failure
RestartSec=3
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=$STATE
ProtectHome=yes
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
UNIT
# Jalankan ulang layanan otomatis bila kirim.js diperbarui (update tanpa sudo).
cat > "/etc/systemd/system/$SVC-ulang.path" <<UNIT
[Unit]
Description=Pantau perubahan kirim.js Konver Soal

[Path]
PathChanged=$KONVER/server/kirim.js
Unit=$SVC-ulang.service

[Install]
WantedBy=multi-user.target
UNIT
cat > "/etc/systemd/system/$SVC-ulang.service" <<UNIT
[Unit]
Description=Jalankan ulang $SVC setelah kirim.js berubah

[Service]
Type=oneshot
ExecStart=/bin/sleep 2
ExecStart=/bin/systemctl restart $SVC.service
UNIT
systemctl daemon-reload
systemctl enable --now "$SVC-ulang.path" >/dev/null 2>&1
systemctl enable "$SVC" >/dev/null 2>&1
if [[ -f "$KONVER/server/kirim.js" ]]; then systemctl restart "$SVC"; fi

# ---------- nginx: dua aplikasi dalam satu situs ----------
info "Menulis konfigurasi nginx ($SITE)"
cat > "$SITE" <<NGINX
# Dibuat oleh siapkan-server-apps.sh: Konver Soal di / dan Web Ujian di /ujian/
server {
    listen 80;
    listen [::]:80;
    server_name _;

    root $KONVER;
    index index.html;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "same-origin" always;

    gzip on;
    gzip_types text/css application/javascript text/javascript text/html;

    # ---- Konver Soal: layanan Kirim & admin ----
    location = /api/kirim {
        proxy_pass http://127.0.0.1:${KIRIM_PORT}/api/kirim;
        proxy_set_header X-Real-IP \$remote_addr;
        client_max_body_size 64m;
        proxy_read_timeout 1200s;
        proxy_send_timeout 1200s;
    }
    location = /api/kirim/status { proxy_pass http://127.0.0.1:${KIRIM_PORT}/api/kirim/status; }
    location = /api/pengaturan {
        proxy_pass http://127.0.0.1:${KIRIM_PORT}/api/pengaturan;
        proxy_set_header X-Real-IP \$remote_addr;
        add_header Cache-Control "no-store" always;
    }
    location = /api/guru {
        proxy_pass http://127.0.0.1:${KIRIM_PORT}/api/guru;
        proxy_set_header X-Real-IP \$remote_addr;
        client_max_body_size 1m;
        add_header Cache-Control "no-store" always;
    }

    # ---- Web Ujian (satu file index.html) ----
    location = /ujian { return 301 /ujian/; }
    location /ujian/ {
        alias $UJIAN/;
        try_files \$uri \$uri/ /ujian/index.html;
        add_header Cache-Control "no-cache" always;
    }

    # ---- Konver Soal (file statis) ----
    location ~ ^/(server|deploy)/ { deny all; }
    location ~ /\. { deny all; }
    location ~* \.md\$ { deny all; }
    location ~* \.(?:js|css)\$ { expires 1h; }
    location / {
        try_files \$uri \$uri/ =404;
        add_header Cache-Control "no-cache";
    }
}
NGINX
ln -sf "$SITE" /etc/nginx/sites-enabled/apps
rm -f /etc/nginx/sites-enabled/default
nginx -t >/dev/null 2>&1 || { nginx -t; die "Konfigurasi nginx tidak valid."; }
systemctl enable --now nginx >/dev/null 2>&1 || true
systemctl reload nginx

if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null && info "Firewall (ufw): port 80 dibuka."
fi

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo
info "Server siap."
echo "    Konver Soal : http://${IP}/        (file: $KONVER)"
echo "    Web Ujian   : http://${IP}/ujian/  (file: $UJIAN/index.html)"
echo "    Data admin  : $STATE   Pengaturan rahasia: $ENV_FILE"
punya SMTP_PASS && echo "    Kirim       : akun pengirim terisi" || warn "Kirim belum aktif (akun pengirim kosong)."
punya ADMIN_PASS && echo "    Admin       : sandi terisi" || warn "Sandi admin belum diatur."
echo "    Update berikutnya (tanpa sudo, sebagai $PEMILIK): bash $KODE/perbarui.sh"
