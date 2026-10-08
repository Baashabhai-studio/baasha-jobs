const inGame = typeof GetParentResourceName === 'function';
const resource = inGame ? GetParentResourceName() : 'baasha_mining';
const $ = (id) => document.getElementById(id);

let post = function (name, body = {}) {
    if (!inGame) { console.log('[post]', name, body); return Promise.resolve({}); }
    return fetch(`https://${resource}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body),
    }).then((r) => r.json()).catch(() => ({}));
};

const RARITY = {
    common: { label: 'COMMON', color: '#a1a1aa' }, uncommon: { label: 'UNCOMMON', color: '#22c55e' },
    rare: { label: 'RARE', color: '#3b82f6' }, epic: { label: 'EPIC', color: '#a855f7' },
    legendary: { label: 'LEGENDARY', color: '#eab308' },
};
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');

// Item picture: our own images first, then the inventory's image folder (same file names), then an icon
const IMG_DIRS = ['images/', 'nui://qb-inventory/html/images/', 'nui://ox_inventory/web/images/', 'nui://qs-inventory/html/images/'];
window.nextItemImg = (img) => {
    const next = Number(img.dataset.try || 0) + 1;
    if (next >= IMG_DIRS.length) { img.outerHTML = '<i class="fa-solid fa-gem"></i>'; return; }
    img.dataset.try = next;
    img.src = IMG_DIRS[next] + img.dataset.item + '.png';
};
const itemImg = (item) => item
    ? `<img class="item-img" data-item="${esc(item)}" src="${IMG_DIRS[0]}${esc(item)}.png" onerror="nextItemImg(this)">`
    : '<i class="fa-solid fa-gem"></i>';

// ── Sounds (tiny WebAudio, shared with the minigame) ─────────────────────
let AC = null;
function audio() { try { AC = AC || new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { AC = null; } return AC; }
function tone(freq, dur, type = 'sine', vol = 0.06, slide = 0) {
    const ac = audio(); if (!ac) return;
    const o = ac.createOscillator(), g = ac.createGain();
    o.type = type; o.frequency.value = freq;
    if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), ac.currentTime + dur);
    g.gain.setValueAtTime(vol, ac.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + dur);
    o.connect(g).connect(ac.destination);
    o.start(); o.stop(ac.currentTime + dur);
}
function noise(dur, vol = 0.2, lowpass = 1200) {
    const ac = audio(); if (!ac) return;
    const buf = ac.createBuffer(1, Math.floor(ac.sampleRate * dur), ac.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / d.length, 2.2);
    const src = ac.createBufferSource(), f = ac.createBiquadFilter(), g = ac.createGain();
    src.buffer = buf; f.type = 'lowpass'; f.frequency.value = lowpass; g.gain.value = vol;
    src.connect(f).connect(g).connect(ac.destination);
    src.start();
}
const sfx = {
    hit: (perfect) => { noise(0.12, 0.25, 2600); tone(perfect ? 1500 : 1100, 0.12, 'triangle', 0.05); },
    miss: () => { noise(0.18, 0.12, 500); tone(180, 0.2, 'sawtooth', 0.04, -80); },
    gem: () => [1320, 1760, 2349].forEach((f, i) => setTimeout(() => tone(f, 0.16, 'sine', 0.05), i * 70)),
    crumble: () => { noise(0.6, 0.35, 900); setTimeout(() => noise(0.4, 0.2, 600), 120); },
    boom: (v = 1) => { noise(1.6, 0.9 * v, 380); tone(60, 0.9, 'sine', 0.35 * v, -25); },
};

// ── Finds card ───────────────────────────────────────────────────────────
let resultTimer = null;
function showResult(r) {
    const finds = r.finds || [];
    const total = finds.reduce((n, f) => n + f.value, 0);
    $('rTitle').innerHTML = r.blast ? 'BOOM! <span>BOULDER</span>' : 'ROCK <span>BROKEN</span>';
    $('rList').innerHTML = finds.map((f, i) => {
        const rr = RARITY[f.rarity] || RARITY.common;
        return `<div class="r-row" style="border-left-color:${rr.color};animation-delay:${i * 0.07}s">
            ${itemImg(f.item)}
            <div><div class="r-name">${esc(f.label)}</div><div class="r-rar" style="color:${rr.color}">${rr.label}</div></div>
            <div class="r-count">${f.carats ? `${Number(f.carats).toFixed(1)} ct · ` : ''}<b>×${f.count}</b></div>
            <div class="r-v">${money(f.value)}</div>
        </div>`;
    }).join('');
    const perfect = r.perfects ? ` · ${r.perfects} perfect` : '';
    $('rMeta').textContent = `+${r.xp || 0} XP${perfect}`;
    $('rTotal').textContent = money(total);
    $('result').classList.remove('off');
    if (finds.some((f) => f.carats)) sfx.gem();
    clearTimeout(resultTimer);
    resultTimer = setTimeout(() => $('result').classList.add('off'), 5200);
}

// ── Mining Office ────────────────────────────────────────────────────────
const office = { data: null, tab: 'bag', busy: false, qty: {}, timer: null };

function renderBag(d) {
    if (!d.bag.length) return '<div class="m-empty"><i class="fa-solid fa-box-open"></i>Your ore bag is empty. Go break some rocks!</div>';
    const rows = d.bag.map((b) => {
        const r = RARITY[b.rarity] || RARITY.common;
        return `<div class="row">
            <div class="row-img">${itemImg(b.item)}</div>
            <div><div class="row-name">${esc(b.label)}</div><div class="row-rar" style="color:${r.color}">${r.label}</div></div>
            <div class="row-mid"><b>×${b.count}</b> · ${money(b.each)} each</div>
            <div class="row-v">${money(b.value)}</div>
        </div>`;
    }).join('');
    const n = d.bag.reduce((s, b) => s + b.count, 0);
    return `${rows}
        <div class="sell-bar">
            <div class="sell-total">${n} items<b>${money(d.total)}</b></div>
            <button class="m-btn gold" data-act="officeSell"><i class="fa-solid fa-sack-dollar"></i> Sell all</button>
        </div>`;
}

function renderFurnace(d) {
    const j = d.smelter;
    if (!j) {
        return `<div class="furnace idle"><div class="furnace-icon"><i class="fa-solid fa-fire"></i></div>
            <div class="furnace-body"><div class="furnace-title">Smelter is cold</div>
            <div class="furnace-sub">Pick a recipe below: ore + coal in, ingots out. Ingots sell for more than raw ore.</div></div></div>`;
    }
    const done = j.left <= 0;
    const pct = done ? 100 : Math.min(100, ((j.seconds - j.left) / j.seconds) * 100);
    return `<div class="furnace ${done ? '' : 'burning'}">
        <div class="furnace-icon">${done ? itemImg(j.ingotItem) : '<i class="fa-solid fa-fire"></i>'}</div>
        <div class="furnace-body">
            <div class="furnace-title">${done ? `${j.amount} × ${esc(j.ingotLabel)} ready!` : `Smelting ${j.amount} × ${esc(j.ingotLabel)}`}</div>
            <div class="furnace-sub">${done ? 'Collect them to your inventory.' : `Ready in ${j.left}s · you can keep mining meanwhile`}</div>
            <div class="furnace-bar"><div style="width:${pct}%"></div></div>
        </div>
        <button class="m-btn gold" data-act="officeCollect" ${done ? '' : 'disabled'}><i class="fa-solid fa-hand-holding"></i> Collect</button>
    </div>`;
}

function renderSmelter(d) {
    const busy = !!d.smelter;
    const cards = d.recipes.map((rc) => {
        const q = Math.min(office.qty[rc.index] ?? rc.max, rc.max);
        office.qty[rc.index] = q;
        const can = !busy && !rc.locked && q > 0;
        return `<div class="recipe ${rc.locked ? 'locked' : ''}">
            <div class="recipe-flow">
                <div class="ing"><div class="row-img">${itemImg(rc.oreItem)}</div>${rc.amount}× ${esc(rc.oreLabel)}</div>
                <div class="op"><i class="fa-solid fa-plus"></i></div>
                <div class="ing"><div class="row-img">${itemImg('ore_coal')}</div>${rc.fuelAmount}× ${esc(rc.fuelLabel)}</div>
                <div class="op"><i class="fa-solid fa-arrow-right"></i></div>
                <div class="ing out"><div class="row-img">${itemImg(rc.ingotItem)}</div>${esc(rc.ingotLabel)}</div>
                <div class="recipe-val">${money(rc.ingotValue)}</div>
            </div>
            <div class="recipe-ctl">
                ${rc.locked ? `<span class="furnace-sub">Unlocks at level ${rc.level}</span>` : `
                <button class="m-btn dark" data-qty="${rc.index}" data-d="-1" ${q <= 1 ? 'disabled' : ''}><i class="fa-solid fa-minus"></i></button>
                <div class="qty">${q}</div>
                <button class="m-btn dark" data-qty="${rc.index}" data-d="1" ${q >= rc.max ? 'disabled' : ''}><i class="fa-solid fa-plus"></i></button>
                <span class="furnace-sub">max ${rc.max}</span>`}
                <button class="m-btn gold" style="margin-left:auto" data-act="officeSmelt" data-index="${rc.index}" ${can ? '' : 'disabled'}><i class="fa-solid fa-fire"></i> Smelt</button>
            </div>
        </div>`;
    }).join('');
    return renderFurnace(d) + `<div class="recipes">${cards}</div>`;
}

function renderCollection(d) {
    const pct = d.collection.length ? (d.found / d.collection.length) * 100 : 0;
    const card = (c) => {
        const r = RARITY[c.rarity] || RARITY.common;
        const seen = c.count > 0;
        return `<div class="c-card ${seen ? '' : 'new'}" style="border-top-color:${seen ? r.color : r.color + '55'}">
            <div class="row-img">${itemImg(c.item)}</div>
            <div class="c-name">${esc(c.label)}</div>
            <div class="c-meta" style="color:${r.color}">${r.label}${c.level > 1 ? ` · Lv ${c.level}` : ''}</div>
            <div class="c-meta ${seen ? '' : 'c-newtag'}">${seen ? `Found ×${c.count}${c.best ? ` · Best ${Number(c.best).toFixed(1)} ct` : ''}` : 'Not found yet'}</div>
            <div class="c-price">${money(c.value)}</div>
        </div>`;
    };
    const ores = d.collection.filter((c) => c.kind === 'ore'), gems = d.collection.filter((c) => c.kind === 'gem');
    return `<div class="col-head">
            <div class="col-count"><span>${d.found}</span> / ${d.collection.length} discovered</div>
            <div class="col-bar"><div style="width:${pct}%"></div></div>
        </div>
        <div class="col-title">ORES</div><div class="col-grid">${ores.map(card).join('')}</div>
        <div class="col-title">GEMS</div><div class="col-grid">${gems.map(card).join('')}</div>`;
}

function renderOffice() {
    const d = office.data;
    if (!d) return;
    $('oLevel').textContent = d.level;
    document.querySelectorAll('.m-tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === office.tab));
    const view = $('oView');
    view.innerHTML = office.tab === 'smelter' ? renderSmelter(d) : office.tab === 'collection' ? renderCollection(d) : renderBag(d);
    view.querySelectorAll('[data-qty]').forEach((b) => b.onclick = () => {
        const i = Number(b.dataset.qty);
        office.qty[i] = (office.qty[i] || 1) + Number(b.dataset.d);
        renderOffice();
    });
    view.querySelectorAll('[data-act]').forEach((b) => b.onclick = async () => {
        if (office.busy) return;
        office.busy = true;
        b.disabled = true;
        const body = b.dataset.index ? { index: Number(b.dataset.index), amount: office.qty[Number(b.dataset.index)] } : {};
        const fresh = await post(b.dataset.act, body);
        office.busy = false;
        if (fresh && fresh.bag) { office.data = fresh; renderOffice(); } else { b.disabled = false; }
    });
    // smelter countdown: tick down locally, ask the server once it should be done
    clearInterval(office.timer);
    if (d.smelter && d.smelter.left > 0) {
        office.timer = setInterval(async () => {
            if (!office.data || !office.data.smelter) return clearInterval(office.timer);
            office.data.smelter.left = Math.max(0, office.data.smelter.left - 1);
            if (office.data.smelter.left === 0) {
                clearInterval(office.timer);
                const fresh = await post('officeRefresh');
                if (fresh && fresh.bag) office.data = fresh;
            }
            if (office.tab === 'smelter') renderOffice();
        }, 1000);
    }
}

function openOffice(d) {
    office.data = d;
    office.tab = 'bag';
    office.qty = {};
    $('office').classList.remove('off');
    renderOffice();
}

function closeOffice(notify = true) {
    if ($('office').classList.contains('off')) return;
    $('office').classList.add('off');
    clearInterval(office.timer);
    if (notify) { post('officeClose'); post('officeClosed'); }
}

function scrollOffice(ms) {
    const view = $('oView');
    view.scrollTop = 0;
    const start = performance.now();
    const step = (t) => {
        const k = Math.min(1, (t - start) / ms);
        view.scrollTop = (view.scrollHeight - view.clientHeight) * (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);
        if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
}

document.querySelectorAll('.m-tab').forEach((t) => t.onclick = () => { office.tab = t.dataset.tab; renderOffice(); });
$('oClose').onclick = () => closeOffice();
window.addEventListener('keyup', (e) => { if (e.key === 'Escape') closeOffice(); });

window.addEventListener('message', ({ data: m }) => {
    if (m.action === 'office') openOffice(m.data);
    else if (m.action === 'closeOffice') closeOffice(false);
    else if (m.action === 'officeTab') { office.tab = m.tab; renderOffice(); if (m.scroll) scrollOffice(m.scroll); }
    else if (m.action === 'officePress') {
        // showcase videos: press an office button on camera (highlight, then a real click)
        const sel = m.arg ? `[data-act="${m.act}"][data-index="${m.arg}"]` : `[data-act="${m.act}"]`;
        const b = $('oView').querySelector(sel);
        if (b) { b.classList.add('pressed'); setTimeout(() => b.click(), 450); }
    }
    else if (m.action === 'result') showResult(m.data);
    else if (m.action === 'boom') sfx.boom(m.volume);
});

// ── Browser preview (outside FiveM): ?office · ?result ───────────────────
if (!inGame) {
    document.body.style.background = 'linear-gradient(160deg, #4b4136, #2a2520 60%, #17140f)';
    const finds = [
        { item: 'ore_gold', label: 'Gold Ore', rarity: 'epic', count: 3, value: 114 },
        { item: 'ore_stone', label: 'Stone', rarity: 'common', count: 2, value: 4 },
        { item: 'gem_ruby', label: 'Ruby', rarity: 'epic', count: 1, carats: 2.4, value: 150 },
    ];
    if (location.search.includes('result')) showResult({ finds, xp: 54, perfects: 4 });
    if (location.search.includes('office')) {
        const recipe = (index, ore, oreLabel, ingot, ingotLabel, value, rarity, level, max) => ({ index, ore, oreItem: ore, oreLabel, amount: 2, fuelLabel: 'Coal', fuelAmount: 1,
            ingot, ingotItem: ingot, ingotLabel, ingotValue: value, rarity, level, locked: level > 4, max });
        const col = (id, label, rarity, value, level, kind, count, best) => ({ id, item: id, label, rarity, value, level, kind, count, best });
        openOffice({
            level: 4, total: 612, secondsPerIngot: 4,
            bag: [
                { item: 'gem_ruby', label: 'Ruby', rarity: 'epic', count: 1, each: 150, value: 150 },
                { item: 'ore_gold', label: 'Gold Ore', rarity: 'epic', count: 6, each: 38, value: 228 },
                { item: 'ore_iron', label: 'Iron Ore', rarity: 'uncommon', count: 9, each: 11, value: 99 },
                { item: 'ore_copper', label: 'Copper Ore', rarity: 'uncommon', count: 8, each: 9, value: 72 },
                { item: 'ore_coal', label: 'Coal', rarity: 'common', count: 7, each: 5, value: 35 },
                { item: 'ore_stone', label: 'Stone', rarity: 'common', count: 14, each: 2, value: 28 },
            ],
            smelter: { ingot: 'ingot_iron', ingotItem: 'ingot_iron', ingotLabel: 'Iron Ingot', amount: 4, seconds: 16, left: 9 },
            recipes: [
                recipe(1, 'ore_copper', 'Copper Ore', 'ingot_copper', 'Copper Ingot', 30, 'uncommon', 1, 4),
                recipe(2, 'ore_iron', 'Iron Ore', 'ingot_iron', 'Iron Ingot', 34, 'uncommon', 1, 4),
                recipe(3, 'ore_silver', 'Silver Ore', 'ingot_silver', 'Silver Ingot', 62, 'rare', 2, 0),
                recipe(4, 'ore_gold', 'Gold Ore', 'ingot_gold', 'Gold Ingot', 115, 'epic', 4, 3),
            ],
            found: 7,
            collection: [
                col('ore_stone', 'Stone', 'common', 2, 1, 'ore', 40, 0), col('ore_coal', 'Coal', 'common', 5, 1, 'ore', 22, 0),
                col('ore_copper', 'Copper Ore', 'uncommon', 9, 1, 'ore', 18, 0), col('ore_iron', 'Iron Ore', 'uncommon', 11, 1, 'ore', 20, 0),
                col('ore_silver', 'Silver Ore', 'rare', 20, 2, 'ore', 6, 0), col('ore_gold', 'Gold Ore', 'epic', 38, 4, 'ore', 6, 0),
                col('gem_amethyst', 'Amethyst', 'rare', 45, 1, 'gem', 2, 1.8), col('gem_emerald', 'Emerald', 'rare', 75, 2, 'gem', 0, 0),
                col('gem_sapphire', 'Sapphire', 'epic', 120, 4, 'gem', 0, 0), col('gem_ruby', 'Ruby', 'epic', 150, 5, 'gem', 0, 0),
                col('gem_diamond', 'Diamond', 'legendary', 300, 7, 'gem', 0, 0),
            ],
        });
        post = (name) => { console.log('[post]', name); return Promise.resolve(office.data); };
    }
}
