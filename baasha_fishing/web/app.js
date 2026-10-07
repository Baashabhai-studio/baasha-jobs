const inGame = typeof GetParentResourceName === 'function';
const resource = inGame ? GetParentResourceName() : 'baasha_fishing';
const $ = (id) => document.getElementById(id);

let post = function (name, body = {}) {
    if (!inGame) { console.log('[post]', name, body); return Promise.resolve({}); }
    return fetch(`https://${resource}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body),
    }).then((r) => r.json()).catch(() => ({}));
}

const RARITY = {
    common: { label: 'COMMON', color: '#a1a1aa' }, uncommon: { label: 'UNCOMMON', color: '#22c55e' },
    rare: { label: 'RARE', color: '#3b82f6' }, epic: { label: 'EPIC', color: '#a855f7' },
    legendary: { label: 'LEGENDARY', color: '#eab308' }, junk: { label: 'JUNK', color: '#71717a' },
};

// ── Bite prompt ───────────────────────────────────────────────────────────
let biteTimer = null;
function showBite(seconds) {
    const ring = $('biteRing');
    ring.style.transition = 'none';
    ring.style.strokeDashoffset = '0';
    $('bite').classList.remove('hidden');
    void ring.offsetWidth;
    ring.style.transition = `stroke-dashoffset ${seconds}s linear`;
    ring.style.strokeDashoffset = '276.5';
    clearTimeout(biteTimer);
    biteTimer = setTimeout(() => $('bite').classList.add('hidden'), seconds * 1000 + 200);
}
function hideBite() { clearTimeout(biteTimer); $('bite').classList.add('hidden'); }

// ── Strike minigame ───────────────────────────────────────────────────────
// A needle spins around the ring: press when it's inside the green zone.
// Every hit reels the fish closer (the needle turns around and a new zone appears),
// every miss weakens the line. Difficulty (zone, speed, hits, misses) comes from the server.
const game = { running: false };
const RING = 2 * Math.PI * 42;                       // circumference of the ring (r = 42)
const norm = (a) => ((a % 360) + 360) % 360;
const inZone = () => norm(game.angle - game.zoneStart) <= game.zoneSize;

function placeZone() {
    // well ahead of the needle in the direction it's turning
    const gap = 110 + Math.random() * 140;
    game.zoneStart = norm(game.dir > 0 ? game.angle + gap : game.angle - gap - game.zoneSize);
    const arc = $('sringZone');
    arc.style.strokeDasharray = `${(RING * game.zoneSize) / 360} ${RING}`;
    arc.setAttribute('transform', `rotate(${game.zoneStart - 90} 50 50)`); // circles start at 3 o'clock
}

function renderPips() {
    $('hitPips').innerHTML = Array.from({ length: game.need }, (_, i) =>
        `<i class="fa-solid fa-fish${i < game.hits ? ' on' : ''}"></i>`).join('');
    $('linePips').innerHTML = Array.from({ length: game.maxMisses }, (_, i) =>
        `<span class="${i < game.maxMisses - game.misses ? 'on' : ''}"></span>`).join('');
}

function flash(text, cls) {
    const f = $('sFlash');
    f.className = 's-flash';
    f.textContent = text;
    void f.offsetWidth;
    if (cls) f.classList.add(cls);
}

function startReel(p) {
    const r = RARITY[p.rarity] || RARITY.common;
    $('reelRarity').textContent = p.rarity === 'junk' ? '???' : r.label;
    $('reelRarity').style.color = r.color;
    Object.assign(game, {
        running: true, landing: false, auto: !!p.auto,
        need: p.hits || 3, hits: 0, misses: 0, maxMisses: p.misses || 3,
        zoneSize: p.zone || 80, speed: p.speed || 160, angle: 0, dir: 1,
        lockUntil: 0, pauseUntil: 0, started: performance.now(), last: performance.now(),
    });
    placeZone();
    renderPips();
    flash('');
    $('reel').classList.remove('hidden');
    requestAnimationFrame(tick);
}

function finishReel(success) {
    if (!game.running) return;
    game.running = false;
    $('reel').classList.add('hidden');
    post('reelDone', { success });
}

function strike() {
    if (!game.running || game.landing) return;
    const t = performance.now();
    if (t < game.lockUntil) return;
    game.lockUntil = t + 250; // no button mashing
    const hit = inZone();
    post('reelSound', { hit });
    if (hit) {
        game.hits++;
        flash('HIT!', 'hit');
        renderPips();
        if (game.hits >= game.need) {
            // landed: wait out the server's minimum reel time, then finish
            game.landing = true;
            return setTimeout(() => finishReel(true), Math.max(450, 2300 - (t - game.started)));
        }
        game.dir = -game.dir;
        game.pauseUntil = game.lockUntil = t + 350;
        placeZone();
    } else {
        game.misses++;
        flash('MISS', 'miss');
        renderPips();
        const ring = $('sring');
        ring.classList.remove('shake');
        void ring.getBoundingClientRect();
        ring.classList.add('shake');
        if (game.misses >= game.maxMisses) {
            game.landing = true; // line snapped: let the MISS show, then close
            setTimeout(() => finishReel(false), 400);
        }
    }
}

function tick(t) {
    if (!game.running) return;
    const dt = Math.min(0.05, (t - game.last) / 1000);
    game.last = t;
    if (!game.landing && t >= game.pauseUntil) game.angle = norm(game.angle + game.dir * game.speed * dt);
    $('needle').setAttribute('transform', `rotate(${game.angle} 50 50)`);
    $('sringZone').classList.toggle('on', inZone());

    // Showcase autoplay: strike a little way into the zone, like a good player
    if (game.auto && !game.landing && t >= game.lockUntil && inZone()) {
        const into = norm(game.angle - game.zoneStart) / game.zoneSize; // 0 → 1 across the zone
        if (game.dir > 0 ? into >= 0.3 : into <= 0.7) strike();
    }
    if (t - game.started > 40000) return finishReel(false);
    requestAnimationFrame(tick);
}

window.addEventListener('keydown', (e) => {
    if ((e.code === 'Space' || e.code === 'KeyE') && game.running) { e.preventDefault(); if (!e.repeat) strike(); }
});
window.addEventListener('mousedown', () => { if (game.running) strike(); });

// ── Catch card ────────────────────────────────────────────────────────────
let catchTimer = null;
function showCatch(c) {
    const r = c.junk ? RARITY.junk : (RARITY[c.rarity] || RARITY.common);
    $('cStripe').style.background = r.color;
    $('cIcon').style.color = r.color;
    const fallback = c.junk ? '<i class="fa-solid fa-shoe-prints"></i>' : '<i class="fa-solid fa-fish"></i>';
    $('cIcon').innerHTML = c.item ? fishImg(c.item) : fallback;
    $('cIcon').classList.toggle('has-img', !!c.item);
    $('cRarity').textContent = r.label;
    $('cRarity').style.color = r.color;
    $('cName').textContent = c.label;
    $('cMeta').textContent = c.junk ? `+${c.xp} XP` : `${Number(c.weight).toFixed(1)} kg  ·  +${c.xp} XP`;
    $('cValue').textContent = `$${c.value}`;
    $('catch').classList.remove('hidden');
    clearTimeout(catchTimer);
    catchTimer = setTimeout(() => $('catch').classList.add('hidden'), 4200);
}

// ── Fish Market ───────────────────────────────────────────────────────────
const market = { data: null, tab: 'cooler', busy: false };
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');

// Fish picture (web/images/<item>.png), falling back to the fish icon
// Our own images first, then the inventory's image folder (same file names), then the plain icon
const IMG_DIRS = ['images/', 'nui://qb-inventory/html/images/', 'nui://ox_inventory/web/images/', 'nui://qs-inventory/html/images/'];
window.nextFishImg = (img) => {
    const next = Number(img.dataset.try || 0) + 1;
    if (next >= IMG_DIRS.length) { img.outerHTML = '<i class="fa-solid fa-fish"></i>'; return; }
    img.dataset.try = next;
    img.src = IMG_DIRS[next] + img.dataset.item + '.png';
};
const fishImg = (item, cls = '') => item
    ? `<img class="fish-img ${cls}" data-item="${esc(item)}" src="${IMG_DIRS[0]}${esc(item)}.png" onerror="nextFishImg(this)">`
    : '<i class="fa-solid fa-fish"></i>';
const priceRange = (s) => s.min === s.max ? money(s.min) : `${money(s.min)} – ${money(s.max)}`;

function renderCooler(d) {
    if (!d.cooler.length) {
        return '<div class="m-empty"><i class="fa-solid fa-box-open"></i>Your cooler is empty. Go catch something!</div>';
    }
    const rows = [...d.cooler].sort((a, b) => b.value - a.value).map((f) => {
        const r = RARITY[f.rarity] || RARITY.common;
        return `<div class="fish-row">
            <div class="fish-dot" style="color:${r.color}">${fishImg(f.item)}</div>
            <div><div class="fish-name">${esc(f.label)}</div><div class="fish-rar" style="color:${r.color}">${r.label}</div></div>
            <div class="fish-w">${f.count ? `×${f.count} in inventory` : `${Number(f.weight).toFixed(1)} kg`}</div>
            <div class="fish-v">${money(f.value)}</div>
        </div>`;
    }).join('');
    return `${rows}
        <div class="sell-bar">
            <div class="sell-total">${d.cooler.reduce((n, f) => n + (f.count || 1), 0)} items<b>${money(d.total)}</b></div>
            <button class="m-btn gold" data-act="marketSell"><i class="fa-solid fa-sack-dollar"></i> Sell all</button>
        </div>`;
}

function renderBoat(d) {
    const out = d.boatRented;
    return `<div class="boat-card">
        <div class="boat-icon"><i class="fa-solid fa-ship"></i></div>
        <div>
            <span class="boat-status" style="background:${out ? 'rgba(34,197,94,.15);color:#4ade80' : 'rgba(255,255,255,.07);color:#a1a1aa'}">${out ? 'BOAT IS OUT' : 'AVAILABLE'}</span>
            <div class="boat-name">Fishing Dinghy</div>
            <div class="boat-meta">Sail out to open water for the <b>deep sea</b>: tuna, swordfish, marlin and sharks.<br>
                Deposit <b>${money(d.boat.deposit)}</b>, refunded when you bring it back under the pier (damage reduces the refund).</div>
            ${out
                ? '<button class="m-btn red" data-act="marketReturn"><i class="fa-solid fa-anchor"></i> Return boat</button>'
                : `<button class="m-btn gold" data-act="marketRent"><i class="fa-solid fa-ship"></i> Rent boat · ${money(d.boat.deposit)}</button>`}
        </div>
    </div>`;
}

function renderGuide(d) {
    const pct = d.species.length ? (d.found / d.species.length) * 100 : 0;
    const cards = d.species.map((s) => {
        const r = RARITY[s.rarity] || RARITY.common;
        if (!s.count) {
            return `<div class="g-card unknown" style="border-top-color:${r.color}55">
                ${fishImg(s.item)}<div class="g-name">${esc(s.label)}</div>
                <div class="g-meta" style="color:${r.color}">${r.label}</div><div class="g-meta">${esc(s.habitat)}${s.level > 1 ? ` · Lv ${s.level}` : ''}</div>
                <div class="g-meta g-new">Not caught yet</div>
                <div class="g-price">${priceRange(s)}</div>
            </div>`;
        }
        return `<div class="g-card" style="border-top-color:${r.color}">
            ${fishImg(s.item)}<div class="g-name">${esc(s.label)}</div>
            <div class="g-meta" style="color:${r.color}">${r.label}</div>
            <div class="g-meta">Caught ×${s.count} · Best ${Number(s.best).toFixed(1)} kg</div>
            <div class="g-price">${priceRange(s)}</div>
        </div>`;
    }).join('');
    return `<div class="guide-head">
            <div class="guide-count"><span>${d.found}</span> / ${d.species.length} discovered</div>
            <div class="guide-bar"><div style="width:${pct}%"></div></div>
        </div>
        <div class="guide-grid">${cards}</div>`;
}

// Smoothly scroll the market list to the bottom (showcase videos: show the whole Fish Guide)
function scrollMarket(ms) {
    const view = $('mView');
    view.scrollTop = 0;
    const start = performance.now();
    const step = (t) => {
        const k = Math.min(1, (t - start) / ms);
        view.scrollTop = (view.scrollHeight - view.clientHeight) * (k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2);
        if (k < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
}

function renderMarket() {
    const d = market.data;
    if (!d) return;
    $('mLevel').textContent = d.level;
    document.querySelectorAll('.m-tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === market.tab));
    $('mView').innerHTML = market.tab === 'boat' ? renderBoat(d) : market.tab === 'guide' ? renderGuide(d) : renderCooler(d);
    $('mView').querySelectorAll('[data-act]').forEach((b) => b.onclick = async () => {
        if (market.busy) return;
        market.busy = true;
        b.disabled = true;
        const fresh = await post(b.dataset.act);
        market.busy = false;
        if (fresh && fresh.species) { market.data = fresh; renderMarket(); } else { b.disabled = false; }
    });
}

function openMarket(d) {
    market.data = d;
    market.tab = 'cooler';
    $('market').classList.remove('hidden');
    renderMarket();
}

function closeMarket(notify = true) {
    if ($('market').classList.contains('hidden')) return;
    $('market').classList.add('hidden');
    if (notify) post('marketClose');
}

document.querySelectorAll('.m-tab').forEach((t) => t.onclick = () => { market.tab = t.dataset.tab; renderMarket(); });
$('mClose').onclick = () => closeMarket();
window.addEventListener('keyup', (e) => { if (e.key === 'Escape') closeMarket(); });

window.addEventListener('message', ({ data: m }) => {
    if (m.action === 'market') openMarket(m.data);
    else if (m.action === 'marketTab') {
        market.tab = m.tab;
        renderMarket();
        if (m.scroll) scrollMarket(m.scroll);
    }
    else if (m.action === 'marketPress') {
        // showcase videos: press a market button on camera (highlight, then a real click)
        const b = $('mView').querySelector(`[data-act="${m.act}"]`);
        if (b) { b.classList.add('pressed'); setTimeout(() => b.click(), 450); }
    }
    else if (m.action === 'closeMarket') closeMarket(false);
    else if (m.action === 'bite') showBite(m.seconds || 2.5);
    else if (m.action === 'hideBite') hideBite();
    else if (m.action === 'reel') { hideBite(); startReel(m.data); }
    else if (m.action === 'stopReel') finishReel(false);
    else if (m.action === 'catch') showCatch(m.data);
});

// ── Browser preview ───────────────────────────────────────────────────────
if (!inGame) {
    document.body.style.background = 'linear-gradient(160deg, #2b4c5c, #183240 60%, #0f222c)';
    if (location.search.includes('market')) {
        const sp = (id, label, rarity, habitat, level, count, best) => ({ id, label, rarity, habitat, level, count, best, item: `fish_${id}`, min: 5 + label.length * 3, max: 20 + label.length * 9 });
        openMarket({
            level: 3, total: 412, found: 7, boatRented: false, boat: { deposit: 300, model: 'dinghy' },
            cooler: [
                { item: 'fish_stingray', label: 'Stingray', rarity: 'rare', weight: 12.8, value: 115 }, { item: 'fish_snapper', label: 'Red Snapper', rarity: 'uncommon', weight: 5.5, value: 66 },
                { item: 'fish_octopus', label: 'Octopus', rarity: 'epic', weight: 6.1, value: 183 }, { item: 'fish_mackerel', label: 'Mackerel', rarity: 'common', weight: 1.0, value: 18 },
                { label: 'Sardine', rarity: 'common', weight: 0.2, value: 7 }, { label: 'Sea Bass', rarity: 'uncommon', weight: 2.1, value: 23 },
            ],
            species: [
                sp('anchovy', 'Anchovy', 'common', 'Piers & coast', 1, 4, 0.2), sp('sardine', 'Sardine', 'common', 'Piers & coast', 1, 3, 0.3),
                sp('mackerel', 'Mackerel', 'common', 'Piers & coast', 1, 2, 1.1), sp('seabass', 'Sea Bass', 'uncommon', 'Piers & coast', 1, 1, 2.1),
                sp('snapper', 'Red Snapper', 'uncommon', 'Piers & coast', 1, 1, 5.5), sp('halibut', 'Halibut', 'rare', 'Piers & coast', 1, 0, 0),
                sp('stingray', 'Stingray', 'rare', 'Piers & coast', 1, 1, 12.8), sp('octopus', 'Octopus', 'epic', 'Piers & coast', 4, 1, 6.1),
                sp('moray', 'Moray Eel', 'epic', 'Piers & coast', 4, 0, 0), sp('bluegill', 'Bluegill', 'common', 'Alamo Sea', 1, 0, 0),
                sp('trout', 'Rainbow Trout', 'rare', 'Alamo Sea', 1, 0, 0), sp('goldcarp', 'Golden Carp', 'legendary', 'Alamo Sea', 7, 0, 0),
                sp('tuna', 'Bluefin Tuna', 'uncommon', 'Deep sea (boat)', 1, 0, 0), sp('swordfish', 'Swordfish', 'epic', 'Deep sea (boat)', 4, 0, 0),
                sp('greatwhite', 'Great White Shark', 'legendary', 'Deep sea (boat)', 7, 0, 0),
            ],
        });
    } else if (!location.search.includes('drop')) { // ?drop previews Deep Drop (deepdrop.js)
        setTimeout(() => showBite(2.5), 300);
        // ?play = play it yourself, otherwise it plays itself
        setTimeout(() => startReel({ rarity: 'rare', hits: 4, zone: 80, speed: 184, misses: 3, auto: !location.search.includes('play') }), 3000);
        // When the demo reel ends, show what the catch card looks like
        const realPost = post;
        post = (name, body) => {
            if (name === 'reelDone') showCatch({ item: 'fish_trout', label: 'Rainbow Trout', rarity: 'rare', weight: 2.4, value: 58, xp: 12 });
            return realPost(name, body);
        };
    }
}
