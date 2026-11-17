/* Impor daftar guru dari file Excel "Lampiran 2 SK Penulis Kisi-kisi dan Soal".
   Bentuk tabel: satu kolom MATA PELAJARAN, lalu kolom kelas XII / XI / X berisi nama guru penulis soal.
   Dibaca langsung di browser dengan JSZip (tanpa pustaka Excel tambahan). */
(function () {
  'use strict';

  const q = (el, tag) => Array.from(el.getElementsByTagNameNS('*', tag));
  const xml = s => new DOMParser().parseFromString(s, 'application/xml');
  const teks = el => q(el, 't').map(t => t.textContent).join('');

  // "B10" -> 1 (indeks kolom mulai 0)
  function kolom(ref) {
    const m = /^([A-Z]+)/.exec(ref || '');
    if (!m) return -1;
    let n = 0;
    for (const ch of m[1]) n = n * 26 + (ch.charCodeAt(0) - 64);
    return n - 1;
  }

  // -> [{ nama, rows: [[sel, ...], ...] }]  (nilai sel berupa teks)
  async function bacaXlsx(file) {
    if (!window.JSZip) throw new Error('Pustaka JSZip tidak termuat.');
    let zip;
    try { zip = await JSZip.loadAsync(file); } catch (e) { throw new Error('File bukan Excel .xlsx yang valid. Simpan dulu sebagai .xlsx.'); }
    const baca = async p => { const f = zip.file(p); return f ? f.async('string') : null; };
    const wbXml = await baca('xl/workbook.xml');
    if (!wbXml) throw new Error('File bukan Excel .xlsx yang valid.');
    const shared = [];
    const ss = await baca('xl/sharedStrings.xml');
    if (ss) q(xml(ss), 'si').forEach(si => shared.push(teks(si)));
    const rels = {};
    const relXml = await baca('xl/_rels/workbook.xml.rels');
    if (relXml) q(xml(relXml), 'Relationship').forEach(r => { rels[r.getAttribute('Id')] = r.getAttribute('Target'); });
    const sheets = [];
    for (const s of q(xml(wbXml), 'sheet')) {
      const rid = s.getAttributeNS('http://schemas.openxmlformats.org/officeDocument/2006/relationships', 'id') || s.getAttribute('r:id');
      let target = rels[rid];
      if (!target) continue;
      target = target.replace(/^\//, '');
      if (!target.startsWith('xl/')) target = 'xl/' + target;
      const sx = await baca(target);
      if (!sx) continue;
      const rows = [];
      q(xml(sx), 'row').forEach(r => {
        const ri = parseInt(r.getAttribute('r'), 10) - 1;
        const row = [];
        q(r, 'c').forEach((c, i) => {
          const ci = c.hasAttribute('r') ? kolom(c.getAttribute('r')) : i;
          const t = c.getAttribute('t');
          const v = q(c, 'v')[0];
          let val = '';
          if (t === 's') val = v ? shared[parseInt(v.textContent, 10)] || '' : '';
          else if (t === 'inlineStr') val = teks(c);
          else val = v ? v.textContent : '';
          row[ci] = val;
        });
        rows[Number.isFinite(ri) ? ri : rows.length] = row;
      });
      // Sel gabungan (merge), mis. satu guru untuk kelas XII, XI, dan X: nilai sel pertama diisikan ke semua selnya.
      q(xml(sx), 'mergeCell').forEach(m => {
        const p = /^([A-Z]+)(\d+):([A-Z]+)(\d+)$/.exec(m.getAttribute('ref') || '');
        if (!p) return;
        const c1 = kolom(p[1]), r1 = +p[2] - 1, c2 = kolom(p[3]), r2 = +p[4] - 1;
        const val = (rows[r1] || [])[c1];
        if (val == null || val === '' || (r2 - r1 + 1) * (c2 - c1 + 1) > 400) return;
        for (let r = r1; r <= r2; r++) {
          rows[r] = rows[r] || [];
          for (let c = c1; c <= c2; c++) if (rows[r][c] == null || rows[r][c] === '') rows[r][c] = val;
        }
      });
      sheets.push({ nama: s.getAttribute('name') || '', rows: Array.from(rows, r => r || []) });
    }
    return sheets;
  }

  const rapi = s => String(s == null ? '' : s).replace(/\s+/g, ' ').trim();
  const RE_KELAS = /^(?:KELAS\s*)?(XII|XI|X)$/i;
  const RE_MAPEL = /^(mata\s*pelajaran|mapel)$/i;

  // Cari tabel (kolom MATA PELAJARAN + kolom kelas) di satu sheet.
  function cariTabel(rows) {
    for (let h = 0; h < rows.length; h++) {
      const mc = (rows[h] || []).findIndex(v => RE_MAPEL.test(rapi(v)));
      if (mc < 0) continue;
      // Judul kelas bisa di baris yang sama atau 1-2 baris di bawahnya (sel "KELAS" digabung).
      for (let k = h; k <= h + 2 && k < rows.length; k++) {
        const kelasCol = {};
        (rows[k] || []).forEach((v, ci) => {
          const m = RE_KELAS.exec(rapi(v));
          if (m && ci !== mc) kelasCol[m[1].toUpperCase()] = ci;
        });
        if (Object.keys(kelasCol).length) return { mapelCol: mc, kelasCol, mulai: k + 1 };
      }
    }
    return null;
  }

  // -> { daftar: [{ nama, mapel, kelas }], sheet, mapel: jumlah, guru: jumlah }
  function ambilGuru(sheets) {
    for (const s of sheets) {
      const tab = cariTabel(s.rows);
      if (!tab) continue;
      const daftar = [];
      const kunci = new Set();
      let mulaiData = false;
      for (let r = tab.mulai; r < s.rows.length; r++) {
        const row = s.rows[r] || [];
        const mapel = rapi(row[tab.mapelCol]);
        if (!mapel) { if (mulaiData) break; continue; } // baris kosong setelah tabel = akhir tabel
        if (/^catatan/i.test(mapel)) break;
        mulaiData = true;
        for (const [kelas, ci] of Object.entries(tab.kelasCol)) {
          String(row[ci] == null ? '' : row[ci]).split(/\r?\n/).map(rapi)
            .filter(n => n && !/^[-–—.]+$/.test(n))
            .forEach(nama => {
              const k = nama + '|' + mapel + '|' + kelas;
              if (!kunci.has(k)) { kunci.add(k); daftar.push({ nama: nama.slice(0, 80), mapel: mapel.slice(0, 80), kelas }); }
            });
        }
      }
      if (daftar.length) {
        return {
          daftar, sheet: s.nama,
          mapel: new Set(daftar.map(g => g.mapel)).size,
          guru: new Set(daftar.map(g => g.nama)).size,
        };
      }
    }
    throw new Error('Tabel guru tidak ditemukan. File harus punya kolom "MATA PELAJARAN" dan kolom kelas XII / XI / X berisi nama guru.');
  }

  window.ImporGuru = { bacaXlsx, ambilGuru };
})();
