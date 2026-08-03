// Helper bersama dipakai di semua halaman dashboard.
// Dimuat setelah assets/config.js.

/** Redirect ke halaman login jika belum ada sesi admin yang valid. */
async function requireAdminSession() {
  if (!window.supabaseClient) {
    document.body.innerHTML =
      '<div class="p-8 max-w-lg mx-auto text-center text-slate-600">' +
      'Supabase belum dikonfigurasi. Isi <code>assets/config.js</code> ' +
      'dengan URL & anon key project Anda terlebih dahulu.</div>';
    throw new Error('Supabase belum dikonfigurasi');
  }

  const { data } = await window.supabaseClient.auth.getSession();
  if (!data.session) {
    window.location.href = 'index.html';
    throw new Error('Belum login');
  }
  return data.session;
}

/** Ambil profil admin (termasuk company_id) untuk user yang sedang login. */
async function getAdminProfile(userId) {
  const { data, error } = await window.supabaseClient
    .from('admin_profiles')
    .select('*')
    .eq('id', userId)
    .single();

  if (error || !data) {
    throw new Error(
      'Akun ini belum terdaftar sebagai admin (tabel admin_profiles). ' +
        'Lihat docs/SETUP_SUPABASE_WEB.md untuk cara mendaftarkan admin pertama.'
    );
  }
  return data;
}

async function signOutAndRedirect() {
  if (window.supabaseClient) {
    await window.supabaseClient.auth.signOut();
  }
  window.location.href = 'index.html';
}

function formatDateTime(iso) {
  if (!iso) return '-';
  const d = new Date(iso);
  return d.toLocaleString('id-ID', {
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

const FRAKSI_LABEL = {
  f00: 'Fraksi 00',
  f0: 'Fraksi 0',
  f1: 'Fraksi 1',
  f2: 'Fraksi 2',
  f3: 'Fraksi 3',
  f4: 'Fraksi 4',
  f5: 'Fraksi 5',
};

const FRAKSI_IDEAL = new Set(['f2', 'f3']);
const FRAKSI_TOLAK = new Set(['f00', 'f5']);

function fraksiColor(fraksi) {
  if (FRAKSI_IDEAL.has(fraksi)) return '#2E7D32';
  if (FRAKSI_TOLAK.has(fraksi)) return '#C62828';
  return '#F9A825';
}

/** Konversi array of objects jadi string CSV sederhana (tanpa dependency). */
function toCsv(rows, headers) {
  const escape = (val) => {
    const s = val === null || val === undefined ? '' : String(val);
    if (s.includes(',') || s.includes('"') || s.includes('\n')) {
      return '"' + s.replace(/"/g, '""') + '"';
    }
    return s;
  };
  const lines = [headers.map((h) => escape(h.label)).join(',')];
  for (const row of rows) {
    lines.push(headers.map((h) => escape(h.get(row))).join(','));
  }
  return lines.join('\n');
}

function downloadTextFile(filename, content, mime = 'text/csv;charset=utf-8;') {
  const blob = new Blob([content], { type: mime });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/** Render nav bar sederhana ke dalam elemen dengan id="nav". */
function renderNav(active) {
  const el = document.getElementById('nav');
  if (!el) return;
  const items = [
    { href: 'dashboard.html', label: 'Dashboard', key: 'dashboard' },
    { href: 'photos.html', label: 'Foto & Dataset', key: 'photos' },
    { href: 'koreksi.html', label: 'Koreksi Data', key: 'koreksi' },
    { href: 'devices.html', label: 'Devices', key: 'devices' },
  ];
  el.innerHTML = `
    <div class="flex items-center justify-between px-4 py-3 bg-emerald-800 text-white">
      <div class="font-bold">SawitVision — Web Dashboard</div>
      <div class="flex items-center gap-4 text-sm">
        ${items
          .map(
            (it) =>
              `<a href="${it.href}" class="${
                it.key === active ? 'font-bold underline' : 'opacity-80 hover:opacity-100'
              }">${it.label}</a>`
          )
          .join('')}
        <button onclick="signOutAndRedirect()" class="opacity-80 hover:opacity-100">Keluar</button>
      </div>
    </div>
  `;
}
