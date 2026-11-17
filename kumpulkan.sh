#!/usr/bin/env bash
#
# (Di komputer pengembang) Menyusun ulang isi repo ini dari dua repo sumber di folder sebelah:
#   ../konver-soal  -> konver-soal/      (versi yang sudah di-commit, HEAD)
#   ../web-ujian    -> ujian/index.html  (hasil npm run build)
# Lalu periksa, commit, dan push repo ini; di server jalankan perbarui.sh.
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
KS=../konver-soal
WU=../web-ujian
g() { git -c safe.directory='*' "$@"; }

echo "==> Konver Soal ($KS, HEAD)"
rm -rf konver-soal && mkdir konver-soal
g -C "$KS" archive HEAD | tar -x -C konver-soal
rm -rf konver-soal/.githooks konver-soal/.gitattributes konver-soal/deploy konver-soal/contoh-berantakan.docx

echo "==> Web Ujian ($WU, build)"
(cd "$WU" && npm run build --silent)
mkdir -p ujian && cp "$WU/dist/index.html" ujian/index.html

printf 'konver-soal  V%s  %s\nweb-ujian    %s\n' \
  "$(tr -d '\r\n' < "$KS/VERSION")" "$(g -C "$KS" log -1 --format='%h %s')" "$(g -C "$WU" log -1 --format='%h %s')" > SUMBER.txt
cat SUMBER.txt
