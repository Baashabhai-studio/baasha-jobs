// Baasha Delivery — NUI (plain JS, no framework, no CDN)
const inGame = typeof GetParentResourceName === 'function';
const resource = inGame ? GetParentResourceName() : 'baasha_delivery';
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

let post = function (name, body = {}) {
    if (!inGame) { console.log('[post]', name, body); return Promise.resolve({}); }
    return fetch(`https://${resource}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body),
    }).then((r) => r.json()).catch(() => ({}));
};

const TYPES = {
    standard:  { color: '#b58900', glyph: '▣', label: 'Standard' },
    signature: { color: '#3b82f6', glyph: '✎', label: 'Signature' },
    fragile:   { color: '#e63946', glyph: '◇', label: 'Fragile' },
    express:   { color: '#f5b301', glyph: '⚡', label: 'Express' },
    large:     { color: '#7c5cff', glyph: '⬛', label: 'Large' },
};

const fmtTime = (s) => { s = Math.max(0, Math.floor(s || 0)); return String(Math.floor(s / 60)).padStart(2, '0') + ':' + String(s % 60).padStart(2, '0'); };

// ── Shape helpers ──────────────────────────────────────────────────────────
function rotateCells(cells, times) {
    let c = cells.map((p) => [p[0], p[1]]);
    for (let t = 0; t < ((times % 4) + 4) % 4; t++) {
        const next = c.map(([x, y]) => [-y, x]);
        const minX = Math.min(...next.map((p) => p[0]));
        const minY = Math.min(...next.map((p) => p[1]));
        c = next.map((p) => [p[0] - minX, p[1] - minY]);
    }
    return c;
}
const bounds = (cells) => ({
    w: Math.max(...cells.map((c) => c[0])) + 1,
    h: Math.max(...cells.map((c) => c[1])) + 1,
});

// ── Puzzle state ───────────────────────────────────────────────────────────
const puzzle = { grid: { w: 8, h: 5 }, parcels: [], allowAutoPack: true, startedAt: 0, timerId: null };
let loadOpen = false;
let drag = null;
let hoverParcel = null;

const parcelById = (id) => puzzle.parcels.find((p) => p.id === id);
const parcelCells = (p) => rotateCells(p.cells, p.rot);

function makeParcelEl(p, cells, b) {
    const el = document.createElement('div');
    el.className = 'parcel ' + p.type;
    el.style.gridTemplateColumns = `repeat(${b.w}, var(--cell))`;
    el.style.gridTemplateRows = `repeat(${b.h}, var(--cell))`;
    const occ = new Set(cells.map((c) => c[0] + ',' + c[1]));
    for (let y = 0; y < b.h; y++) {
        for (let x = 0; x < b.w; x++) {
            const c = document.createElement('div');
            c.className = occ.has(x + ',' + y) ? 'cellbox' : 'empty';
            el.appendChild(c);
        }
    }
    const lbl = document.createElement('div');
    lbl.className = 'plabel';
    lbl.textContent = '#' + p.id;
    el.appendChild(lbl);
    const icon = document.createElement('div');
    icon.className = 'picon';
    icon.style.background = TYPES[p.type].color;
    icon.textContent = TYPES[p.type].glyph;
    el.appendChild(icon);
    return el;
}

function renderLegend() {
    $('legend').innerHTML = Object.keys(TYPES).map((t) =>
        `<div class="legend-item"><span class="legend-dot" style="background:${TYPES[t].color}"></span>${TYPES[t].label}</div>`).join('');
}

function renderGrid() {
    const g = $('grid');
    g.style.gridTemplateColumns = `repeat(${puzzle.grid.w}, var(--cell))`;
    g.style.gridTemplateRows = `repeat(${puzzle.grid.h}, var(--cell))`;
    g.innerHTML = '';
    for (let y = 0; y < puzzle.grid.h; y++) {
        for (let x = 0; x < puzzle.grid.w; x++) {
            const c = document.createElement('div');
            c.className = 'cell';
            c.dataset.x = x;
            c.dataset.y = y;
            g.appendChild(c);
        }
    }
    for (const p of puzzle.parcels) {
        if (p.placed) {
            const cells = parcelCells(p);
            const b = bounds(cells);
            const el = makeParcelEl(p, cells, b);
            el.classList.add('placed');
            el.dataset.id = p.id;
            el.style.position = 'absolute';
            el.style.left = `calc(1.2vh + ${p.placed.x} * (var(--cell) + 0.35vh))`;
            el.style.top = `calc(1.2vh + ${p.placed.y} * (var(--cell) + 0.35vh))`;
            g.appendChild(el);
        }
    }
}

function renderTray() {
    const tray = $('tray');
    tray.innerHTML = '';
    const unplaced = puzzle.parcels.filter((p) => !p.placed);
    if (!unplaced.length) tray.innerHTML = '<div class="empty-note">All parcels packed!</div>';
    for (const p of unplaced) {
        const cells = parcelCells(p);
        const b = bounds(cells);
        const el = makeParcelEl(p, cells, b);
        el.dataset.id = p.id;
        tray.appendChild(el);
    }
    $('dockCount').textContent = `${puzzle.parcels.length - unplaced.length}/${puzzle.parcels.length}`;
}

function validPlacement(id, cells, x, y) {
    for (const [cx, cy] of cells) {
        const gx = x + cx, gy = y + cy;
        if (gx < 0 || gy < 0 || gx >= puzzle.grid.w || gy >= puzzle.grid.h) return false;
        for (const q of puzzle.parcels) {
            if (q.id === id || !q.placed) continue;
            const qc = parcelCells(q);
            if (qc.some(([qx, qy]) => q.placed.x + qx === gx && q.placed.y + qy === gy)) return false;
        }
    }
    return true;
}

function fullScore() {
    let orderScore = 30;
    const front = {};
    for (const p of puzzle.parcels) {
        front[p.id] = Math.min(...parcelCells(p).map((c) => c[1] + p.placed.y));
    }
    for (let i = 0; i < puzzle.parcels.length; i++) {
        for (let j = i + 1; j < puzzle.parcels.length; j++) {
            const a = puzzle.parcels[i], b = puzzle.parcels[j];
            if (front[a.id] > front[b.id]) orderScore -= 4;
        }
    }
    orderScore = Math.max(0, orderScore);

    const occ = {};
    for (const p of puzzle.parcels) {
        for (const c of parcelCells(p)) occ[(c[1] + p.placed.y) * puzzle.grid.w + (c[0] + p.placed.x)] = p.id;
    }
    let leftW = 0, rightW = 0;
    for (const p of puzzle.parcels) {
        const cells = parcelCells(p);
        const per = (p.weight || cells.length) / cells.length;
        for (const c of cells) {
            if ((c[0] + p.placed.x) < puzzle.grid.w / 2) leftW += per; else rightW += per;
        }
    }
    const total = leftW + rightW;
    const balance = total > 0 ? Math.abs(leftW - rightW) / total : 0;
    const balanceScore = Math.max(0, Math.floor(20 - balance * 60));

    let fragilePenalty = 0;
    for (const p of puzzle.parcels) {
        if (p.fragile) {
            for (const c of parcelCells(p)) {
                const above = occ[(c[1] + p.placed.y + 1) * puzzle.grid.w + (c[0] + p.placed.x)];
                const q = above && parcelById(above);
                if (q && q.heavy) fragilePenalty += 3;
            }
        }
    }
    const fragileScore = Math.max(0, 15 - fragilePenalty);
    return Math.max(0, Math.min(100, 40 + orderScore + balanceScore + fragileScore));
}

function computeScore() {
    const placed = puzzle.parcels.filter((p) => p.placed).length;
    if (placed < puzzle.parcels.length) return Math.round((placed / puzzle.parcels.length) * 100);
    return fullScore();
}

function updateScore() {
    const s = computeScore();
    $('scoreVal').textContent = s;
    $('scoreFill').style.width = s + '%';
    if (s === 100) {
        const lv = $('load');
        lv.classList.remove('burst');
        void lv.offsetWidth;
        lv.classList.add('burst');
    }
}

function renderAll() {
    renderGrid();
    renderTray();
    updateScore();
}

// ── Drag & drop ────────────────────────────────────────────────────────────
function buildGhost(p) {
    const cells = parcelCells(p);
    const b = bounds(cells);
    const g = document.createElement('div');
    g.className = 'ghost';
    g.style.gridTemplateColumns = `repeat(${b.w}, var(--cell))`;
    g.style.gridTemplateRows = `repeat(${b.h}, var(--cell))`;
    const occ = new Set(cells.map((c) => c[0] + ',' + c[1]));
    for (let y = 0; y < b.h; y++) {
        for (let x = 0; x < b.w; x++) {
            const c = document.createElement('div');
            c.className = occ.has(x + ',' + y) ? 'cellbox' : 'empty';
            g.appendChild(c);
        }
    }
    document.body.appendChild(g);
    drag.ghost = g;
}
function moveGhost(e) {
    if (!drag || !drag.ghost) return;
    drag.ghost.style.left = (e.clientX + 14) + 'px';
    drag.ghost.style.top = (e.clientY - 14) + 'px';
    if (Math.hypot(e.clientX - drag.startX, e.clientY - drag.startY) > 5) drag.moved = true;
}
function removeGhost() {
    if (drag && drag.ghost) { drag.ghost.remove(); drag.ghost = null; }
}
function clearHighlights() {
    document.querySelectorAll('.cell.hover-ok, .cell.hover-bad').forEach((c) => c.classList.remove('hover-ok', 'hover-bad'));
}
function cellAt(px, py) {
    const g = $('grid');
    const rect = g.getBoundingClientRect();
    const cells = g.querySelectorAll('.cell');
    if (cells.length < 2) return null;
    const c0 = cells[0].getBoundingClientRect();
    const c1 = cells[1].getBoundingClientRect();
    const cellW = c0.width, cellH = c0.height;
    const gapX = c1.left - c0.right, gapY = c1.top - c0.bottom;
    const padX = c0.left - rect.left, padY = c0.top - rect.top;
    const x = Math.floor((px - rect.left - padX) / (cellW + gapX));
    const y = Math.floor((py - rect.top - padY) / (cellH + gapY));
    if (x < 0 || y < 0 || x >= puzzle.grid.w || y >= puzzle.grid.h) return null;
    if ((px - rect.left - padX) - x * (cellW + gapX) > cellW) return null;
    if ((py - rect.top - padY) - y * (cellH + gapY) > cellH) return null;
    return { x, y };
}
function highlightCells(e) {
    clearHighlights();
    if (!drag) return;
    const p = parcelById(drag.id);
    if (!p) return;
    const cell = cellAt(e.clientX, e.clientY);
    if (!cell) return;
    const ok = validPlacement(p.id, parcelCells(p), cell.x, cell.y);
    for (const [cx, cy] of parcelCells(p)) {
        const gx = cell.x + cx, gy = cell.y + cy;
        if (gx < 0 || gy < 0 || gx >= puzzle.grid.w || gy >= puzzle.grid.h) continue;
        const el = document.querySelector(`.cell[data-x="${gx}"][data-y="${gy}"]`);
        if (el) el.classList.add(ok ? 'hover-ok' : 'hover-bad');
    }
}

function onPointerDown(e) {
    const el = e.target.closest('.parcel');
    if (!el || !loadOpen) return;
    const p = parcelById(el.dataset.id);
    if (!p) return;
    if (e.button === 2) { rotateParcel(p); return; }
    e.preventDefault();
    drag = { id: p.id, startX: e.clientX, startY: e.clientY, moved: false, ghost: null };
    buildGhost(p);
    moveGhost(e);
}
function onPointerMove(e) {
    if (drag) { moveGhost(e); highlightCells(e); return; }
    const el = e.target.closest('.parcel');
    hoverParcel = el ? el.dataset.id : null;
}
function onPointerUp(e) {
    if (!drag) return;
    const id = drag.id, moved = drag.moved;
    removeGhost();
    clearHighlights();
    drag = null;
    const p = parcelById(id);
    if (!p) return;
    if (!moved) {
        if (p.placed) { p.placed = null; renderAll(); }
        return;
    }
    const cell = cellAt(e.clientX, e.clientY);
    if (cell && validPlacement(p.id, parcelCells(p), cell.x, cell.y)) p.placed = { x: cell.x, y: cell.y };
    renderAll();
}

function rotateParcel(p) {
    const old = p.rot;
    p.rot = (p.rot + 1) % 4;
    if (p.placed && !validPlacement(p.id, parcelCells(p), p.placed.x, p.placed.y)) p.rot = old;
    renderAll();
}

function localAutoPack() {
    const order = [...puzzle.parcels].sort((a, b) => b.cells.length - a.cells.length || a.stop - b.stop);
    const occ = {};
    const fits = (cells, x, y) => cells.every(([cx, cy]) => {
        const gx = x + cx, gy = y + cy;
        return gx >= 0 && gy >= 0 && gx < puzzle.grid.w && gy < puzzle.grid.h && !occ[gy * puzzle.grid.w + gx];
    });
    const set = (cells, x, y, id) => cells.forEach(([cx, cy]) => { occ[(y + cy) * puzzle.grid.w + (x + cx)] = id; });
    function solve(i) {
        if (i >= order.length) return true;
        const p = order[i];
        for (let rot = 0; rot < 4; rot++) {
            const cells = rotateCells(p.cells, rot);
            for (let y = 0; y < puzzle.grid.h; y++) {
                for (let x = 0; x < puzzle.grid.w; x++) {
                    if (fits(cells, x, y)) {
                        set(cells, x, y, p.id);
                        const savedRot = p.rot, savedPlaced = p.placed;
                        p.rot = rot; p.placed = { x, y };
                        if (solve(i + 1)) return true;
                        set(cells, x, y, undefined);
                        p.rot = savedRot; p.placed = savedPlaced;
                    }
                }
            }
        }
        return false;
    }
    if (!solve(0)) return null;
    return order.map((p) => ({ id: p.id, x: p.placed.x, y: p.placed.y, rot: p.rot }));
}

function confirm() {
    const placed = puzzle.parcels.filter((p) => p.placed);
    if (placed.length !== puzzle.parcels.length) {
        const hint = document.querySelector('.load-foot .hint');
        hint.textContent = 'Pack every parcel first!';
        hint.style.color = '#ef4444';
        setTimeout(() => { hint.textContent = 'Drag parcels into the van · R / right-click to rotate · click a placed parcel to pick it up'; hint.style.color = ''; }, 2500);
        return;
    }
    const placements = placed.map((p) => ({ id: p.id, x: p.placed.x, y: p.placed.y, rot: p.rot }));
    post('loadDone', { placements });
}

async function autoPack() {
    const res = await post('autoPack');
    let placements = (res && res.ok && Array.isArray(res.placements)) ? res.placements : null;
    if (!placements) placements = localAutoPack();
    if (!placements) return;
    for (const p of puzzle.parcels) { p.placed = null; p.rot = 0; }
    for (const pl of placements) {
        const p = parcelById(pl.id);
        if (p) { p.placed = { x: pl.x, y: pl.y }; p.rot = pl.rot || 0; }
    }
    renderAll();
}

// Showcase: drop the parcels in one at a time (server's layout), then confirm like a player would.
async function demoPack(placements, delay) {
    for (const p of puzzle.parcels) { p.placed = null; p.rot = 0; }
    renderAll();
    for (const pl of placements || []) {
        await new Promise((r) => setTimeout(r, delay || 450));
        if (!loadOpen) return;
        const p = parcelById(pl.id);
        if (p) { p.rot = pl.rot || 0; p.placed = { x: pl.x, y: pl.y }; }
        renderAll();
    }
    await new Promise((r) => setTimeout(r, 1200));
    if (loadOpen) confirm();
}

// ── Open / close ───────────────────────────────────────────────────────────
function openLoad(data) {
    puzzle.grid = data.grid || { w: 8, h: 5 };
    puzzle.parcels = (data.parcels || []).map((p) => Object.assign({ rot: 0, placed: null }, p));
    puzzle.allowAutoPack = data.allowAutoPack !== false;
    $('autoPack').style.display = puzzle.allowAutoPack ? '' : 'none';
    renderLegend();
    renderAll();
    puzzle.startedAt = Date.now();
    clearInterval(puzzle.timerId);
    puzzle.timerId = setInterval(() => { $('timer').textContent = fmtTime(Math.floor((Date.now() - puzzle.startedAt) / 1000)); }, 500);
    $('load').classList.remove('hidden');
    loadOpen = true;
}
function closeLoad() {
    $('load').classList.add('hidden');
    loadOpen = false;
    clearInterval(puzzle.timerId);
    clearHighlights();
    removeGhost();
    drag = null;
}

// ── Signature ──────────────────────────────────────────────────────────────
let signCountdown = null;
function openSign(data) {
    $('signLabel').textContent = data.label || '';
    $('signCustomer').textContent = data.customer || '';
    $('sign').classList.remove('hidden');
    const path = $('signPath');
    path.style.animation = 'none';
    void path.offsetWidth;
    path.style.animation = '';
    let n = data.padTime || 6;
    $('signCount').textContent = n;
    clearInterval(signCountdown);
    signCountdown = setInterval(() => {
        n--;
        $('signCount').textContent = Math.max(0, n);
        if (n <= 0) confirmSign();
    }, 1000);
}
function confirmSign() {
    clearInterval(signCountdown);
    if ($('sign').classList.contains('hidden')) return;
    post('signDone');
}
function closeSign() {
    clearInterval(signCountdown);
    $('sign').classList.add('hidden');
}

// ── Rating ─────────────────────────────────────────────────────────────────
let rateTimer = null;
function openRate(data) {
    const stars = data.stars || 1;
    const starEl = $('rateStars');
    starEl.innerHTML = '';
    for (let i = 1; i <= 5; i++) {
        const s = document.createElement('i');
        s.textContent = '★';
        s.style.animationDelay = (i * 0.12) + 's';
        if (i > stars) s.style.color = 'rgba(255, 255, 255, 0.14)';
        starEl.appendChild(s);
    }
    let tipText = '';
    if (data.tip > 0) tipText = '+$' + data.tip + ' tip';
    if (data.express) tipText = (data.onTime ? 'On time! ' : 'Late! ') + tipText;
    $('rateTip').textContent = tipText || 'Thanks!';
    $('rateCond').textContent = data.condition != null ? 'Condition ' + data.condition + '%' : '';
    $('rate').classList.remove('hidden');
    clearTimeout(rateTimer);
    rateTimer = setTimeout(() => $('rate').classList.add('hidden'), 3000);
}

// ── HUD pill ───────────────────────────────────────────────────────────────
function renderHud(d) {
    const hud = $('hud');
    if (!d || !d.visible) { hud.classList.add('hidden'); return; }
    hud.classList.remove('hidden');
    hud.className = d.position === 'left' ? 'left' : d.position === 'right' ? 'right' : '';
    let html = `<div class="hud-title">${esc(d.title || '')}</div>`;
    if (d.line) html += `<div class="hud-line">${esc(d.line)}</div>`;
    if (d.express != null) html += `<div class="hud-chip express">⚡ ${fmtTime(d.express)}</div>`;
    if (d.condition != null) {
        const pct = Math.max(0, Math.min(100, d.condition));
        const color = pct < 20 ? '#ef4444' : pct < 60 ? '#f59e0b' : '#22c55e';
        html += `<div class="hud-chip fragile">◇ Condition ${pct}%</div>`
            + `<div class="hud-bar"><div style="width:${pct}%;background:${color}"></div></div>`;
    }
    if (d.hint) html += `<div class="hud-hint">${esc(d.hint)}</div>`;
    hud.innerHTML = html;
}

// ── Messages ───────────────────────────────────────────────────────────────
window.addEventListener('message', ({ data: m }) => {
    if (!m || !m.action) return;
    if (m.action === 'open') {
        if (m.view === 'load') openLoad(m.data);
        else if (m.view === 'sign') openSign(m.data);
        else if (m.view === 'rate') openRate(m.data);
    } else if (m.action === 'close') {
        if (m.view === 'load') closeLoad();
        else if (m.view === 'sign') closeSign();
        else if (m.view === 'rate') $('rate').classList.add('hidden');
    } else if (m.action === 'demoPack') {
        demoPack(m.placements, m.delay);
    } else if (m.action === 'hud') {
        renderHud(m.data);
    } else if (m.action === 'loadError') {
        const hint = document.querySelector('.load-foot .hint');
        if (hint) { hint.textContent = m.msg || 'Invalid layout'; hint.style.color = '#ef4444'; }
    }
});

// ── Controls ───────────────────────────────────────────────────────────────
$('confirm').onclick = confirm;
$('autoPack').onclick = autoPack;
$('signConfirm').onclick = confirmSign;
document.addEventListener('contextmenu', (e) => { if (loadOpen) e.preventDefault(); });
document.addEventListener('pointerdown', onPointerDown);
document.addEventListener('pointermove', onPointerMove);
document.addEventListener('pointerup', onPointerUp);
window.addEventListener('keydown', (e) => {
    if ((e.key === 'r' || e.key === 'R') && loadOpen) {
        const id = (drag && drag.id) || hoverParcel;
        if (id) { const p = parcelById(id); if (p) rotateParcel(p); }
    }
    if (e.key === 'Escape') post('close');
});

// ── Browser preview (no FiveM) ─────────────────────────────────────────────
if (!inGame) {
    document.body.style.background = 'linear-gradient(160deg, #1c1c22, #0a0a0c)';
    const view = new URLSearchParams(location.search).get('view') || 'load';
    if (view === 'load') {
        openLoad({
            grid: { w: 8, h: 5 }, allowAutoPack: true,
            parcels: [
                { id: 'A01', type: 'standard', label: 'Mirror Park Blvd 1287', cells: [[0, 0], [0, 1]], weight: 2, fragile: false, heavy: false, stop: 1 },
                { id: 'A02', type: 'standard', label: 'East Mirror Drive 2', cells: [[0, 0], [1, 0], [0, 1], [1, 1]], weight: 4, fragile: false, heavy: false, stop: 2 },
                { id: 'A03', type: 'signature', label: 'Vespucci Blvd 811', cells: [[0, 0], [0, 1]], weight: 2, fragile: false, heavy: false, stop: 3 },
                { id: 'A04', type: 'fragile', label: 'Del Perro Fwy 4', cells: [[0, 0], [0, 1]], weight: 2, fragile: true, heavy: false, stop: 4 },
                { id: 'A05', type: 'express', label: 'Rockford Dr 3655', cells: [[0, 0], [1, 0], [0, 1], [1, 1]], weight: 4, fragile: false, heavy: false, stop: 5 },
                { id: 'A06', type: 'large', label: 'Vinewood Blvd 1900', cells: [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1]], weight: 6, fragile: false, heavy: true, stop: 6 },
            ],
        });
    } else if (view === 'sign') {
        openSign({ label: '#A12 · 1287 Mirror Park Blvd', customer: 'Amelia Hart' });
    } else if (view === 'rate') {
        openRate({ stars: 5, tip: 24, condition: 92, express: true, onTime: true });
    } else if (view === 'hud') {
        renderHud({ visible: true, stage: 'driving', title: 'Stop 3/8', line: '#A12 · Fragile', condition: 72, hint: '[J] Job tablet · End shift' });
    }
}
