// ── Rock Breaker ──────────────────────────────────────────────────────────
// A glowing weak spot appears on the rock and a ring closes in on it. Strike (E / SPACE / click)
// when the ring meets the spot: PERFECT / GOOD crack the rock, too early or too late is a MISS.
// The server decides the rock, the number of strikes, the ring speed and which strike is a gem vein.
// Uses post / $ / RARITY / sfx from app.js.

const BK = (() => {
    const W = 520, H = 640, CX = 260, CY = 370, R0 = 200;
    const cv = $('bkCanvas'), ctx = cv.getContext('2d');
    let G = null, last = 0, looping = false;

    const rand = (a, b) => a + Math.random() * (b - a);
    const rgb = (c, a = 1) => `rgba(${c[0]},${c[1]},${c[2]},${a})`;

    // ── rock shape ──
    function makeRock() {
        const pts = [];
        const n = 28;
        for (let i = 0; i < n; i++) {
            const a = (i / n) * Math.PI * 2;
            const r = R0 * (0.8 + Math.random() * 0.2) * (1 - 0.12 * Math.max(0, Math.sin(a))); // flatter on the bottom
            pts.push({ x: CX + Math.cos(a) * r * 1.08, y: CY + Math.sin(a) * r * 0.86 });
        }
        // smooth the outline a little
        const smooth = pts.map((p, i) => {
            const a = pts[(i + n - 1) % n], b = pts[(i + 1) % n];
            return { x: (a.x + p.x * 2 + b.x) / 4, y: (a.y + p.y * 2 + b.y) / 4 };
        });
        const blobs = Array.from({ length: 14 }, () => ({ x: CX + rand(-150, 150), y: CY + rand(-120, 110), rx: rand(20, 60), ry: rand(14, 40), a: rand(0, 3.1), dark: Math.random() < 0.6 }));
        const flecks = Array.from({ length: 46 }, () => ({ x: CX + rand(-170, 170), y: CY + rand(-140, 130), s: rand(3, 9), a: rand(0, 6.28), tw: rand(0, 6.28) }));
        return { pts: smooth, blobs, flecks };
    }

    function inside(x, y) {
        const pts = G.rock.pts;
        let c = false;
        for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
            if (((pts[i].y > y) !== (pts[j].y > y)) && (x < (pts[j].x - pts[i].x) * (y - pts[i].y) / (pts[j].y - pts[i].y) + pts[i].x)) c = !c;
        }
        return c;
    }

    // ── flow ──
    function open(p) {
        G = {
            p, t: 0, phase: 'play', rock: null, auto: !!p.auto,
            hits: 0, perfects: 0, goods: 0, misses: 0, attempt: 0, gem: false,
            spot: null, gapUntil: 0.6, cracks: [], chips: [], pops: [], dust: [], shake: 0, wedges: null, aim: 1,
        };
        G.rock = makeRock();
        G.dust = Array.from({ length: 40 }, () => ({ x: rand(0, W), y: rand(0, H), s: rand(0.6, 1.8), v: rand(4, 12) }));
        const r = RARITY[p.rarity] || RARITY.common;
        $('bkRar').textContent = r.label;
        $('bkRar').style.color = r.color;
        $('bkOre').textContent = `${p.label} rock`;
        hud();
        $('breaker').classList.remove('off');
        last = performance.now();
        if (!looping) { looping = true; requestAnimationFrame(frame); }
    }

    function close() {
        G = null;
        $('breaker').classList.add('off');
    }

    function finish(aborted) {
        if (!G || G.phase === 'sent') return;
        const body = aborted ? { aborted: true } : { perfects: G.perfects, goods: G.goods, misses: G.misses, gem: G.gem };
        G.phase = 'sent';
        post('breakerDone', body);
        setTimeout(close, aborted ? 0 : 250);
    }

    function hud() {
        $('bkStamina').innerHTML = Array.from({ length: G.p.misses }, (_, i) =>
            `<i class="fa-solid fa-hammer${i < G.p.misses - G.misses ? '' : ' gone'}"></i>`).join('');
        $('bkProgress').style.width = `${(G.hits / G.p.hits) * 100}%`;
    }

    function nextSpot() {
        G.attempt++;
        const gem = G.p.gemAt && G.attempt === G.p.gemAt;
        let x, y, tries = 0;
        do {
            x = CX + rand(-140, 140); y = CY + rand(-110, 100); tries++;
        } while (tries < 60 && (!inside(x, y) || !inside(x + 34, y) || !inside(x - 34, y) || !inside(x, y + 34) || !inside(x, y - 34)
                 || (G.spot && Math.hypot(x - G.spot.x, y - G.spot.y) < 110)));
        G.spot = { x, y, r: 24, start: G.t, dur: G.p.ring * (gem ? 0.8 : 1), gem };
        G.aim = Math.random() < 0.82 ? rand(0.95, 1.02) : rand(0.8, 0.88); // autoplay: mostly perfect, sometimes good
    }

    function pop(text, x, y, color, scale = 1) { G.pops.push({ text, x, y, color, scale, t: 0 }); }

    function crack(x, y) {
        const branches = 3 + Math.floor(Math.random() * 3);
        for (let b = 0; b < branches; b++) {
            let a = rand(0, 6.28), px = x, py = y;
            const line = [{ x: px, y: py }];
            const len = rand(40, 90);
            for (let s = 0; s < len; s += 12) {
                a += rand(-0.6, 0.6);
                px += Math.cos(a) * 12; py += Math.sin(a) * 12;
                if (!inside(px, py)) break;
                line.push({ x: px, y: py });
            }
            G.cracks.push(line);
        }
    }

    function chips(x, y, color, n = 14) {
        for (let i = 0; i < n; i++) {
            const a = rand(0, 6.28), v = rand(120, 320);
            G.chips.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 120, s: rand(2, 6), t: 0, life: rand(0.5, 0.9),
                           color: Math.random() < 0.35 ? color : [110 + rand(-20, 20), 100, 90] });
        }
    }

    function strike() {
        if (!G || G.phase !== 'play' || !G.spot) return;
        const s = G.spot, k = (G.t - s.start) / s.dur;
        let q = 'miss';
        if (k >= 0.9 && k <= 1.06) q = 'perfect';
        else if (k >= 0.75 && k <= 1.15) q = 'good';
        resolve(q);
    }

    function resolve(q) {
        const s = G.spot;
        G.spot = null;
        G.gapUntil = G.t + 0.28;
        post('breakerHit', { quality: q });
        if (q === 'miss') {
            G.misses++;
            G.shake = 9;
            sfx.miss();
            pop(s.gem ? 'GEM LOST' : 'MISS', s.x, s.y - 30, '#f87171', 1.1);
            hud();
            if (G.misses >= G.p.misses) {
                G.phase = 'tired';
                pop('TOO TIRED', CX, CY - 40, '#f87171', 1.6);
                setTimeout(() => finish(false), 900);
            }
            return;
        }
        G.hits++;
        if (q === 'perfect') G.perfects++; else G.goods++;
        G.shake = q === 'perfect' ? 7 : 4;
        crack(s.x, s.y);
        chips(s.x, s.y, G.p.color, q === 'perfect' ? 22 : 14);
        sfx.hit(q === 'perfect');
        if (s.gem) {
            G.gem = true;
            sfx.gem();
            pop('GEM FOUND!', s.x, s.y - 40, '#e879f9', 1.5);
            chips(s.x, s.y, [232, 121, 249], 24);
        } else {
            pop(q === 'perfect' ? 'PERFECT!' : 'GOOD', s.x, s.y - 30, q === 'perfect' ? '#facc15' : '#4ade80', q === 'perfect' ? 1.3 : 1.05);
        }
        hud();
        if (G.hits >= G.p.hits) shatter();
    }

    function shatter() {
        G.phase = 'shatter';
        G.shatterAt = G.t;
        sfx.crumble();
        const pts = G.rock.pts, n = pts.length, parts = 8;
        G.wedges = [];
        for (let w = 0; w < parts; w++) {
            const from = Math.floor((w / parts) * n), to = Math.floor(((w + 1) / parts) * n);
            const poly = [{ x: CX, y: CY }];
            for (let i = from; i <= to; i++) poly.push(pts[i % n]);
            const mid = poly[Math.floor(poly.length / 2)];
            const a = Math.atan2(mid.y - CY, mid.x - CX);
            G.wedges.push({ poly, vx: Math.cos(a) * rand(160, 260), vy: Math.sin(a) * rand(120, 220) - 140, rot: 0, vr: rand(-2.5, 2.5) });
        }
        chips(CX, CY, G.p.color, 40);
        setTimeout(() => finish(false), 750);
    }

    // ── update ──
    function update(dt) {
        G.t += dt;
        if (G.phase === 'play') {
            if (!G.spot && G.t >= G.gapUntil) nextSpot();
            if (G.spot) {
                const k = (G.t - G.spot.start) / G.spot.dur;
                if (G.auto && k >= G.aim) strike();
                else if (k > 1.15) resolve('miss');
            }
        }
        for (const c of G.chips) { c.t += dt; c.x += c.vx * dt; c.y += c.vy * dt; c.vy += 700 * dt; }
        G.chips = G.chips.filter((c) => c.t < c.life);
        for (const p of G.pops) p.t += dt;
        G.pops = G.pops.filter((p) => p.t < 1.1);
        for (const d of G.dust) { d.y += d.v * dt; d.x += Math.sin(G.t + d.s) * 0.2; if (d.y > H) d.y = 0; }
        if (G.wedges) for (const w of G.wedges) { w.vy += 600 * dt; w.rot += w.vr * dt; w.ox = (w.ox || 0) + w.vx * dt; w.oy = (w.oy || 0) + w.vy * dt; }
        G.shake *= Math.pow(0.01, dt);
    }

    // ── draw ──
    function drawBg() {
        const g = ctx.createRadialGradient(CX, CY - 60, 40, CX, CY, 520);
        g.addColorStop(0, '#3d342b'); g.addColorStop(0.6, '#1d1915'); g.addColorStop(1, '#0b0a08');
        ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
        ctx.fillStyle = 'rgba(230, 210, 180, 0.12)';
        for (const d of G.dust) { ctx.beginPath(); ctx.arc(d.x, d.y, d.s, 0, 6.28); ctx.fill(); }
        // ground shadow
        ctx.fillStyle = 'rgba(0,0,0,0.45)';
        ctx.beginPath(); ctx.ellipse(CX, CY + 170, 210, 26, 0, 0, 6.28); ctx.fill();
    }

    function rockPath(pts) {
        ctx.beginPath();
        ctx.moveTo(pts[0].x, pts[0].y);
        for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y);
        ctx.closePath();
    }

    function drawRock() {
        const pts = G.rock.pts;
        ctx.save();
        rockPath(pts);
        const g = ctx.createRadialGradient(CX - 70, CY - 90, 20, CX, CY, R0 * 1.2);
        g.addColorStop(0, '#8d8378'); g.addColorStop(0.55, '#5b544c'); g.addColorStop(1, '#2e2a26');
        ctx.fillStyle = g; ctx.fill();
        ctx.clip();
        for (const b of G.rock.blobs) {
            ctx.fillStyle = b.dark ? 'rgba(20,16,12,0.22)' : 'rgba(255,240,220,0.08)';
            ctx.beginPath(); ctx.ellipse(b.x, b.y, b.rx, b.ry, b.a, 0, 6.28); ctx.fill();
        }
        // ore flecks (twinkle on precious ores)
        const shiny = G.p.rarity === 'rare' || G.p.rarity === 'epic' || G.p.rarity === 'legendary';
        for (const f of G.rock.flecks) {
            const tw = shiny ? 0.55 + 0.45 * Math.sin(G.t * 3 + f.tw) : 0.85;
            ctx.fillStyle = rgb(G.p.color, tw);
            ctx.save(); ctx.translate(f.x, f.y); ctx.rotate(f.a);
            ctx.beginPath(); ctx.moveTo(-f.s, 0); ctx.lineTo(0, -f.s * 0.6); ctx.lineTo(f.s, 0); ctx.lineTo(0, f.s * 0.6); ctx.closePath(); ctx.fill();
            ctx.restore();
        }
        // cracks
        ctx.lineCap = 'round'; ctx.lineJoin = 'round';
        for (const line of G.cracks) {
            ctx.strokeStyle = 'rgba(255,235,210,0.25)'; ctx.lineWidth = 5;
            ctx.beginPath(); line.forEach((p, i) => (i ? ctx.lineTo(p.x + 1, p.y + 1) : ctx.moveTo(p.x + 1, p.y + 1))); ctx.stroke();
            ctx.strokeStyle = '#140f0b'; ctx.lineWidth = 3;
            ctx.beginPath(); line.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y))); ctx.stroke();
        }
        ctx.restore();
        ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.lineWidth = 3;
        rockPath(pts); ctx.stroke();
    }

    function drawWedges() {
        const k = Math.min(1, (G.t - G.shatterAt) / 0.75);
        ctx.globalAlpha = 1 - k;
        for (const w of G.wedges) {
            ctx.save();
            ctx.translate(CX + w.ox, CY + w.oy); ctx.rotate(w.rot); ctx.translate(-CX, -CY);
            rockPath(w.poly);
            ctx.fillStyle = '#5b544c'; ctx.fill();
            ctx.strokeStyle = '#1a1612'; ctx.lineWidth = 2; ctx.stroke();
            ctx.restore();
        }
        ctx.globalAlpha = 1;
    }

    function drawSpot() {
        const s = G.spot;
        if (!s) return;
        const k = Math.min(1.15, (G.t - s.start) / s.dur);
        const col = s.gem ? [232, 121, 249] : G.p.color;
        const pulse = 1 + Math.sin(G.t * 10) * 0.06;
        // glow
        const g = ctx.createRadialGradient(s.x, s.y, 2, s.x, s.y, s.r * 2.2);
        g.addColorStop(0, s.gem ? 'rgba(255,255,255,0.95)' : 'rgba(255,250,230,0.95)');
        g.addColorStop(0.35, rgb(col, 0.85)); g.addColorStop(1, rgb(col, 0));
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(s.x, s.y, s.r * 2.2 * pulse, 0, 6.28); ctx.fill();
        if (s.gem) {
            ctx.save(); ctx.translate(s.x, s.y); ctx.rotate(G.t * 2);
            ctx.fillStyle = `hsl(${(G.t * 220) % 360}, 90%, 70%)`;
            ctx.beginPath(); ctx.moveTo(0, -16); ctx.lineTo(12, 0); ctx.lineTo(0, 16); ctx.lineTo(-12, 0); ctx.closePath(); ctx.fill();
            ctx.restore();
            ctx.font = '700 18px Rajdhani'; ctx.textAlign = 'center'; ctx.fillStyle = '#f5d0fe';
            ctx.fillText('GEM VEIN', s.x, s.y - s.r - 40);
        }
        // target ring
        ctx.strokeStyle = 'rgba(255,255,255,0.85)'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(s.x, s.y, s.r, 0, 6.28); ctx.stroke();
        // closing ring
        const rr = s.r * (1 + 2.3 * Math.max(0, 1 - k));
        const near = k >= 0.75 && k <= 1.15;
        ctx.strokeStyle = near ? (k >= 0.9 && k <= 1.06 ? '#facc15' : '#4ade80') : 'rgba(255,255,255,0.9)';
        ctx.lineWidth = near ? 5 : 3.5;
        ctx.beginPath(); ctx.arc(s.x, s.y, rr, 0, 6.28); ctx.stroke();
    }

    function drawChips() {
        for (const c of G.chips) {
            ctx.globalAlpha = 1 - c.t / c.life;
            ctx.fillStyle = rgb(c.color);
            ctx.fillRect(c.x - c.s / 2, c.y - c.s / 2, c.s, c.s);
        }
        ctx.globalAlpha = 1;
    }

    function drawPops() {
        ctx.textAlign = 'center';
        for (const p of G.pops) {
            const a = Math.min(1, (1.1 - p.t) * 2.5), y = p.y - p.t * 60;
            ctx.globalAlpha = a;
            ctx.font = `700 ${Math.round(26 * p.scale)}px Rajdhani`;
            ctx.lineWidth = 5; ctx.strokeStyle = 'rgba(0,0,0,0.6)'; ctx.strokeText(p.text, p.x, y);
            ctx.fillStyle = p.color; ctx.fillText(p.text, p.x, y);
        }
        ctx.globalAlpha = 1;
    }

    function draw() {
        ctx.save();
        if (G.shake > 0.3) ctx.translate(rand(-G.shake, G.shake), rand(-G.shake, G.shake));
        drawBg();
        if (G.wedges) drawWedges(); else drawRock();
        if (G.phase === 'play') drawSpot();
        drawChips();
        drawPops();
        ctx.restore();
    }

    function frame(t) {
        if (!G) { looping = false; return; }
        const dt = Math.max(0, Math.min(0.033, (t - last) / 1000));
        last = t;
        update(dt);
        draw();
        requestAnimationFrame(frame);
    }

    // ── input ──
    window.addEventListener('keydown', (e) => {
        if (!G || G.phase !== 'play') return;
        if (e.code === 'Space' || e.code === 'KeyE') { e.preventDefault(); if (!e.repeat && !G.auto) strike(); }
        else if (e.code === 'Escape') finish(true);
    });
    cv.addEventListener('mousedown', () => { if (G && !G.auto) strike(); });

    return { open, close, state: () => G, _tick: (dt) => G && update(dt) }; // _tick: headless tests
})();

window.addEventListener('message', ({ data: m }) => {
    if (m.action === 'breaker') BK.open(m.data);
    else if (m.action === 'closeBreaker') BK.close();
});

// ── Browser preview (outside FiveM): ?breaker[&play][&ore=ore_gold] ─────────
if (!inGame && location.search.includes('breaker')) {
    const q = new URLSearchParams(location.search);
    const ores = {
        ore_copper: ['Copper Ore', 'uncommon', [230, 120, 50], 5], ore_iron: ['Iron Ore', 'uncommon', [190, 80, 60], 5],
        ore_silver: ['Silver Ore', 'rare', [220, 225, 235], 6], ore_gold: ['Gold Ore', 'epic', [250, 200, 40], 7],
        ore_coal: ['Coal', 'common', [60, 60, 70], 4],
    };
    const id = q.get('ore') || 'ore_gold', [label, rarity, color, hits] = ores[id];
    const realPost = post;
    post = (name, body) => {
        if (name === 'breakerDone' && !body.aborted && body.misses < 3) {
            setTimeout(() => showResult({ finds: [
                { item: id, label, rarity, count: 2 + Math.floor(body.perfects / 2), value: 38 * (2 + Math.floor(body.perfects / 2)) },
                { item: 'ore_stone', label: 'Stone', rarity: 'common', count: 1, value: 2 },
                ...(body.gem ? [{ item: 'gem_sapphire', label: 'Sapphire', rarity: 'epic', count: 1, carats: 1.7, value: 120 }] : []),
            ], xp: 30, perfects: body.perfects }), 300);
        }
        return realPost(name, body);
    };
    setTimeout(() => BK.open({ ore: id, label, rarity, color, hits, ring: 1.0, misses: 3, gemAt: 3, auto: !q.has('play') }), 400);
}
