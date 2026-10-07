// ── Deep Drop minigame ────────────────────────────────────────────────────
// The server builds the water (which fish, where, how heavy, what they're worth) and checks the result.
// 1. Drop: steer the hook down, dodge fish (a bump ends the dive) and hazards. Gold rings = +1 hook.
// 2. Reel up: the hook flies back up, steer into fish to hook them. Hazards knock your last fish off.
// 3. The server confirms the catch → results card.
// Uses post / $ / RARITY / IMG_DIRS / inGame from app.js.

const DD = (() => {
    const W = 480, H = 800, PX = 15, SKY = 12;
    // Size on screen (px), hitbox height factor, swim speed (px/s)
    const VIS = {
        anchovy: [44, 0.12, 120], sardine: [50, 0.12, 115], mackerel: [62, 0.12, 105], seabass: [76, 0.16, 85],
        snapper: [76, 0.17, 80], halibut: [96, 0.2, 55], stingray: [92, 0.26, 60], octopus: [84, 0.3, 45], moray: [104, 0.16, 50],
        bluegill: [58, 0.22, 90], carp: [84, 0.2, 60], catfish: [96, 0.14, 55], bass: [80, 0.17, 80], trout: [76, 0.13, 100],
        pike: [104, 0.1, 115], sturgeon: [150, 0.1, 50], goldcarp: [84, 0.2, 70],
        mackerel2: [86, 0.12, 120], mahi: [100, 0.15, 110], tuna: [128, 0.15, 100], barracuda: [112, 0.1, 135],
        swordfish: [170, 0.1, 120], marlin: [176, 0.12, 110], hammerhead: [190, 0.14, 70], greatwhite: [230, 0.15, 60],
        boot: [54, 0.35, 0], can: [44, 0.4, 0], tire: [60, 0.4, 0],
    };
    const WATER = {
        coast: [[0, [40, 176, 214]], [25, [18, 112, 162]], [60, [10, 62, 108]]],
        lake:  [[0, [70, 150, 128]], [15, [40, 106, 88]], [40, [16, 52, 44]]],
        deep:  [[0, [30, 150, 205]], [25, [16, 98, 150]], [70, [10, 58, 102]], [130, [5, 30, 60]], [230, [2, 10, 24]]],
    };
    const cv = $('ddCanvas'), ctx = cv.getContext('2d');
    const IMG = {};
    const keys = {};
    let G = null, mouseX = null, last = 0;

    // ── images (own folder first, then the inventory's) ──
    function img(item) {
        if (IMG[item]) return IMG[item];
        const im = new Image();
        let tryIdx = 0;
        im.onerror = () => { if (++tryIdx < IMG_DIRS.length) im.src = IMG_DIRS[tryIdx] + item + '.png'; };
        im.src = IMG_DIRS[0] + item + '.png';
        IMG[item] = im;
        return im;
    }

    // ── sound ──
    let AC = null;
    function tone(freq, dur, type = 'sine', vol = 0.08, slide = 0) {
        try {
            AC = AC || new (window.AudioContext || window.webkitAudioContext)();
            const o = AC.createOscillator(), g = AC.createGain();
            o.type = type; o.frequency.value = freq;
            if (slide) o.frequency.exponentialRampToValueAtTime(Math.max(40, freq + slide), AC.currentTime + dur);
            g.gain.setValueAtTime(vol, AC.currentTime);
            g.gain.exponentialRampToValueAtTime(0.0001, AC.currentTime + dur);
            o.connect(g).connect(AC.destination);
            o.start(); o.stop(AC.currentTime + dur);
        } catch (e) { /* no audio */ }
    }
    const sfx = {
        splash: () => tone(320, 0.25, 'triangle', 0.08, -220),
        catch: (r) => { const f = { common: 520, uncommon: 620, rare: 740, epic: 880, legendary: 1040, junk: 300 }[r] || 520; tone(f, 0.12, 'square', 0.04); setTimeout(() => tone(f * 1.5, 0.16, 'square', 0.04), 70); },
        bump: () => tone(160, 0.25, 'sawtooth', 0.07, -80),
        zap: () => tone(900, 0.2, 'sawtooth', 0.05, -700),
        ring: () => { tone(880, 0.1, 'sine', 0.07); setTimeout(() => tone(1320, 0.18, 'sine', 0.07), 80); },
        surface: () => [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => tone(f, 0.18, 'triangle', 0.05), i * 90)),
    };

    const rand = (a, b) => a + Math.random() * (b - a);
    const sy = (m) => (m - G.camY) * PX;

    // ── start / finish ──
    function open(d) {
        const ents = d.ents.map((e) => {
            const v = VIS[e.id] || [70, 0.14, 80];
            return { ...e, x: e.x * W, w: v[0], hb: v[1], sp: v[2] * (e.speed || 0), bob: Math.random() * 6.28, img: e.item };
        });
        ents.forEach((e) => { if (e.item) img(e.item); });
        G = {
            phase: 'dive', t: 0, d, ents, auto: !!d.auto,
            hook: { x: W / 2, y: 0.6, tx: W / 2, vy: 0 },
            camY: -SKY, shake: 0, slots: d.hooks, rings: 0, caught: [], pops: [], bubbles: [],
            snow: Array.from({ length: 60 }, () => ({ x: rand(0, W), y: rand(0, H), s: rand(0.6, 2), v: rand(6, 18) })),
            deepest: 0, zapUntil: 0, fullShown: false, reelT: 0, surfaceT: 0, aiX: W / 2,
        };
        mouseX = null;
        $('ddSpot').textContent = d.spot || '';
        $('ddResults').classList.add('hidden');
        $('drop').classList.remove('hidden');
        sfx.splash();
        hud();
        last = performance.now();
        startLoop();
    }

    function close() {
        if (!G) return;
        G = null;
        $('drop').classList.add('hidden');
    }

    function abort() {
        if (!G || G.phase === 'sent' || G.phase === 'result') return;
        close();
        post('dropDone', { aborted: true });
    }

    function startReel(reason) {
        if (G.phase !== 'dive') return;
        G.phase = 'reel'; G.reelT = 0;
        if (reason) pop(reason, G.hook.x, G.hook.y - 2, '#fff', 1.3);
        hud();
    }

    function hookFish(e) {
        e.caught = true;
        G.caught.push(e);
        const r = e.junk ? 'junk' : e.rarity;
        pop(`+$${e.value} ${e.label}`, e.x, e.y, RARITY[r].color, r === 'legendary' ? 1.6 : 1.1);
        sfx.catch(r);
        if (r === 'legendary' || r === 'epic') G.shake = 8;
        hud();
    }

    function surfaced() {
        G.phase = 'sent';
        sfx.surface();
        post('dropDone', { caught: G.caught.map((e) => e.i), deepest: Math.round(G.deepest * 10) / 10, rings: G.rings });
    }

    // Server-confirmed catch → results card
    function result(r) {
        if (!G) return;
        G.phase = 'result';
        const list = [...(r && r.catches || [])].sort((a, b) => b.value - a.value);
        const total = list.reduce((n, c) => n + c.value, 0);
        $('ddTitle').innerHTML = list.length >= G.slots ? 'FULL <span>LINE!</span>' : list.length ? 'NICE <span>CATCH</span>' : 'EMPTY <span>HOOK</span>';
        $('ddList').innerHTML = list.length ? list.map((c) => {
            const rr = c.junk ? RARITY.junk : (RARITY[c.rarity] || RARITY.common);
            return `<div class="dd-row" style="border-left-color:${rr.color}">
                ${fishImg(c.item)}
                <div><div class="dd-name">${esc(c.label)}</div><div class="dd-rar" style="color:${rr.color}">${rr.label}</div></div>
                <div class="dd-w">${c.weight ? Number(c.weight).toFixed(1) + ' kg' : ''}</div><div class="dd-v">$${c.value}</div>
            </div>`;
        }).join('') : '<div class="dd-empty">The fish got lucky this time. Dodge on the way down to dive deeper!</div>';
        $('ddCount').textContent = `${list.length} caught · deepest ${Math.floor(G.deepest)} m · +${(r && r.xp) || 0} XP`;
        $('ddTotal').textContent = `$${total.toLocaleString('en-US')}`;
        $('ddResults').classList.remove('hidden');
        G.closeAt = performance.now() + (G.auto ? 4500 : 7000);
    }

    function pop(text, x, yM, color, scale = 1) { G.pops.push({ text, x, y: yM, color, scale, t: 0 }); }

    function hud() {
        const labels = { dive: '▼ DROP', reel: '▲ REEL UP', surface: 'SURFACE', sent: 'SURFACE', result: 'DONE' };
        $('ddPhase').textContent = labels[G.phase] || '';
        $('ddPhase').style.color = G.phase === 'reel' ? '#facc15' : '';
        $('ddHooks').innerHTML = Array.from({ length: G.slots }, (_, i) => `<i class="fa-solid fa-fish${i < G.caught.length ? ' on' : ''}"></i>`).join('');
        $('ddCash').textContent = '$' + G.caught.reduce((n, c) => n + c.value, 0).toLocaleString('en-US');
    }

    // ── autoplay (showcase / tests): dodge on the way down, grab fish on the way up ──
    function aiSteer() {
        const h = G.hook;
        const hazards = G.ents.filter((e) => (e.kind === 'jelly' || e.kind === 'snag') && !e.done);
        if (G.phase === 'dive') {
            // pick the column with the most room in the next few metres
            let best = h.x, bestScore = -1e9;
            for (let x = 30; x <= W - 50; x += 15) {
                let score = -Math.abs(x - h.x) * 0.15;
                for (const e of G.ents) {
                    if (e.done || e.caught || e.y < h.y - 0.5 || e.y > h.y + 7) continue;
                    const ahead = (e.y - h.y) / Math.max(1, h.vy);              // seconds until the hook gets there
                    const ex = e.kind === 'fish' ? e.x + e.dir * e.sp * ahead : e.x;
                    const reach = e.kind === 'fish' ? e.w * 0.55 + 18 : (e.kind === 'ring' ? -1 : e.size + 24);
                    if (e.kind === 'ring') { if (Math.abs(ex - x) < 20) score += 30; continue; }
                    const gap = Math.abs(ex - x);
                    if (gap < reach) score -= (reach - gap) * 4;
                }
                if (score > bestScore) { bestScore = score; best = x; }
            }
            G.aiX = best;
        } else if (G.phase === 'reel') {
            let best = null, bestD = 1e9;
            if (G.caught.length < G.slots) {
                for (const e of G.ents) {
                    if (e.kind !== 'fish' || e.caught || e.done || e.y > h.y || e.y < h.y - 14) continue;
                    const ahead = (h.y - e.y) / 16;
                    const ex = e.x + e.dir * e.sp * ahead;
                    if (ex < 20 || ex > W - 40) continue;
                    // nothing on the hook yet: take the risk rather than come up empty
                    const danger = G.caught.length > 0 && hazards.some((z) => z.y < h.y && z.y > e.y - 2 && Math.abs(z.x - ex) < z.size + 20);
                    const d = Math.abs(ex - h.x) + (h.y - e.y) * 6 + (danger ? 400 : 0) - e.value * 0.5;
                    if (d < bestD) { bestD = d; best = ex; }
                }
            }
            let x = best ?? h.x;
            for (const z of hazards) {
                if (z.y < h.y && z.y > h.y - 6 && Math.abs(z.x - x) < z.size + 22) x = z.x + (x < z.x ? -1 : 1) * (z.size + 30);
            }
            G.aiX = x;
        }
        h.tx = G.aiX;
    }

    // ── update ──
    function hitFish(e, hx, hy) {
        const rx = e.w * 0.42, ry = Math.max(8, e.w * e.hb);
        const dx = (hx - e.x) / rx, dy = (hy - sy(e.y)) / ry;
        return dx * dx + dy * dy <= 1;
    }
    function hitHazard(e, hx, hy) {
        if (e.kind === 'snag') return Math.abs(hx - e.x) < e.size * 0.9 && Math.abs(hy - sy(e.y)) < 10;
        return Math.hypot(hx - e.x, hy - sy(e.y)) < e.size * 0.55;
    }

    function update(dt) {
        G.t += dt;
        const h = G.hook;
        if (G.auto) aiSteer();
        else {
            const steer = (keys.ArrowRight || keys.KeyD ? 1 : 0) - (keys.ArrowLeft || keys.KeyA ? 1 : 0);
            if (steer) { h.tx += steer * 520 * dt; mouseX = null; } else if (mouseX !== null) h.tx = mouseX;
        }
        h.tx = Math.max(22, Math.min(W - 40, h.tx));
        h.x += (h.tx - h.x) * Math.min(1, dt * 11);

        for (const e of G.ents) {
            if (e.kind === 'fish' && !e.caught && e.sp) {
                e.x += e.dir * e.sp * dt;
                const m = e.w * 0.6;
                if (e.x > W + m) e.x = -m; else if (e.x < -m) e.x = W + m;
            }
        }

        if (G.phase === 'dive') {
            const fast = !G.auto && (keys.ArrowDown || keys.KeyS);
            h.vy += ((fast ? 14 : 7.5) - h.vy) * Math.min(1, dt * 3);
            h.y += h.vy * dt;
            G.deepest = Math.max(G.deepest, h.y);
            const hy = sy(h.y);
            for (const e of G.ents) {
                if (e.done || e.caught) continue;
                if (e.kind === 'ring') {
                    if (Math.abs(h.x - e.x) < 26 && Math.abs(h.y - e.y) < 2.2) {
                        e.done = true; G.slots++; G.rings++; sfx.ring(); pop('+1 HOOK', e.x, e.y, '#facc15', 1.3); hud();
                    }
                } else if (e.kind === 'jelly' || e.kind === 'snag') {
                    if (hitHazard(e, h.x, hy)) { sfx.zap(); G.shake = 10; startReel(e.kind === 'snag' ? 'SNAGGED! Reel up' : 'ZAP! Reel up'); break; }
                } else if (e.kind === 'fish' && !e.junk && hitFish(e, h.x, hy)) {
                    sfx.bump(); G.shake = 7; hookFish(e); startReel('BUMP! Reel up');
                    break;
                }
            }
            if (G.phase === 'dive') {
                const floor = G.d.floor;
                const limit = floor ? Math.min(G.d.line, floor - 1.2) : G.d.line;
                if (h.y >= limit) { h.y = limit; startReel(floor && G.d.line >= floor - 1.2 ? 'BOTTOM! Reel up' : 'LINE OUT! Reel up'); }
            }
        } else if (G.phase === 'reel') {
            G.reelT += dt;
            h.vy = -Math.min(17, 4 + G.reelT * 16);
            h.y += h.vy * dt;
            const hy = sy(h.y);
            for (const e of G.ents) {
                if (e.done || e.caught) continue;
                if ((e.kind === 'jelly' || e.kind === 'snag') && G.t > G.zapUntil && hitHazard(e, h.x, hy)) {
                    G.zapUntil = G.t + 1.0; G.shake = 9; sfx.zap();
                    const lost = G.caught.pop();
                    if (lost) {
                        lost.caught = false; lost.done = true; lost.x = h.x; lost.y = h.y + 1; lost.sp = (lost.sp || 60) * 1.4;
                        pop(`${e.kind === 'snag' ? 'SNAG' : 'ZAP'}! Lost ${lost.label}`, h.x, h.y, '#f87171', 1.1);
                        G.fullShown = false;
                    } else pop(e.kind === 'snag' ? 'SNAG!' : 'ZAP!', h.x, h.y, '#f87171');
                    hud();
                } else if (e.kind === 'fish' && hitFish(e, h.x, hy)) {
                    if (G.caught.length < G.slots) hookFish(e);
                    else if (!G.fullShown) { G.fullShown = true; pop('LINE FULL', h.x, h.y, '#facc15', 1.2); }
                }
            }
            if (h.y <= 0) { h.y = 0; G.phase = 'surface'; G.surfaceT = 0; hud(); }
        } else if (G.phase === 'surface') {
            G.surfaceT += dt;
            if (G.surfaceT > 0.6) surfaced();
        } else if (G.phase === 'result' && performance.now() > G.closeAt) {
            close();
            return;
        }

        const anchor = G.phase === 'reel' ? 0.68 : 0.34;
        const want = G.phase === 'dive' || G.phase === 'reel' ? h.y - (H * anchor) / PX : -SKY;
        G.camY += (Math.max(-SKY, want) - G.camY) * Math.min(1, dt * (G.phase === 'reel' ? 6 : 4));
        G.shake *= Math.pow(0.02, dt);

        if ((G.phase === 'dive' || G.phase === 'reel') && Math.random() < dt * 22) G.bubbles.push({ x: h.x + rand(-6, 6), y: h.y, r: rand(1.5, 4), v: rand(1.5, 3.5) });
        for (const b of G.bubbles) { b.y -= b.v * dt; b.x += Math.sin(G.t * 4 + b.r) * 0.3; }
        G.bubbles = G.bubbles.filter((b) => b.y > 0 && b.y > G.camY - 2);
        for (const p of G.pops) p.t += dt;
        G.pops = G.pops.filter((p) => p.t < 1.4);
        for (const s of G.snow) { s.y -= s.v * dt * (G.phase === 'reel' ? -6 : 1) * 0.6; if (s.y < 0) s.y = H; if (s.y > H) s.y = 0; }
    }

    // ── draw ──
    function waterColor(d) {
        const stops = WATER[G.d.habitat] || WATER.coast;
        if (d <= 0) return stops[0][1];
        for (let i = 1; i < stops.length; i++) {
            if (d <= stops[i][0]) {
                const [ad, ac] = stops[i - 1], [bd, bc] = stops[i], k = (d - ad) / (bd - ad);
                return ac.map((v, j) => Math.round(v + (bc[j] - v) * k));
            }
        }
        return stops[stops.length - 1][1];
    }

    function drawPier(surfaceY) {
        const top = surfaceY - 74;
        ctx.fillStyle = '#5b4632';
        for (let x = 30; x < W; x += 70) ctx.fillRect(x, top + 12, 9, 64);
        ctx.fillStyle = '#8a6a48'; ctx.fillRect(0, top, W * 0.62, 14);
        ctx.fillStyle = '#6d5238'; ctx.fillRect(0, top + 14, W * 0.62, 4);
        ctx.strokeStyle = '#c9c9c9'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(0, top - 18); ctx.lineTo(W * 0.62, top - 18); ctx.stroke();
        for (let x = 10; x < W * 0.62; x += 36) { ctx.beginPath(); ctx.moveTo(x, top - 18); ctx.lineTo(x, top); ctx.stroke(); }
    }
    function drawBoat(surfaceY) {
        const x = W / 2 - 150, y = surfaceY - 30 + Math.sin(G.t * 1.6) * 2;
        ctx.fillStyle = '#e8e8e8';
        ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x + 300, y); ctx.lineTo(x + 260, y + 34); ctx.lineTo(x + 30, y + 34); ctx.fill();
        ctx.fillStyle = '#c0392b'; ctx.fillRect(x + 20, y + 22, 250, 5);
        ctx.fillStyle = '#d4d4d4'; ctx.fillRect(x + 70, y - 34, 110, 34);
        ctx.fillStyle = '#7fb6d1'; ctx.fillRect(x + 80, y - 28, 40, 16); ctx.fillRect(x + 130, y - 28, 40, 16);
    }

    function drawBackground() {
        const surfaceY = sy(0), lake = G.d.habitat === 'lake';
        if (surfaceY > 0) {
            const g = ctx.createLinearGradient(0, 0, 0, surfaceY);
            g.addColorStop(0, '#7ec3e6'); g.addColorStop(1, '#d6edf7');
            ctx.fillStyle = g; ctx.fillRect(0, 0, W, surfaceY);
            ctx.fillStyle = lake ? 'rgba(120, 110, 80, 0.45)' : 'rgba(70, 110, 120, 0.35)';
            ctx.beginPath(); ctx.moveTo(0, surfaceY - 18);
            for (let x = 0; x <= W; x += 40) ctx.lineTo(x, surfaceY - 18 - Math.sin(x * 0.02) * 10 - 8);
            ctx.lineTo(W, surfaceY); ctx.lineTo(0, surfaceY); ctx.fill();
            if (G.d.habitat === 'deep') drawBoat(surfaceY); else drawPier(surfaceY);
        }
        for (let y = Math.max(0, Math.floor(surfaceY)); y < H; y += 16) {
            const c = waterColor(G.camY + y / PX);
            ctx.fillStyle = `rgb(${c[0]},${c[1]},${c[2]})`;
            ctx.fillRect(0, y, W, 17);
        }
        const near = Math.max(0, 1 - Math.max(0, G.camY) / 45);
        if (near > 0) {
            ctx.save();
            ctx.globalCompositeOperation = 'lighter';
            const top = Math.max(0, surfaceY);
            for (let i = 0; i < 5; i++) {
                const x = (i * 120 + Math.sin(G.t * 0.4 + i) * 30) % (W + 80) - 40;
                const g = ctx.createLinearGradient(0, top, 0, top + 420);
                g.addColorStop(0, `rgba(180, 235, 255, ${0.09 * near})`); g.addColorStop(1, 'rgba(180, 235, 255, 0)');
                ctx.fillStyle = g;
                ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x + 40, top); ctx.lineTo(x + 110, top + 420); ctx.lineTo(x + 30, top + 420); ctx.fill();
            }
            ctx.restore();
        }
        if (surfaceY > -10 && surfaceY < H) {
            ctx.fillStyle = 'rgba(255, 255, 255, 0.55)';
            ctx.beginPath(); ctx.moveTo(0, surfaceY);
            for (let x = 0; x <= W; x += 8) ctx.lineTo(x, surfaceY + Math.sin(x * 0.05 + G.t * 2.4) * 2.5);
            ctx.lineTo(W, surfaceY + 5); ctx.lineTo(0, surfaceY + 5); ctx.fill();
        }
        if (G.d.floor) {
            const fy = sy(G.d.floor);
            if (fy < H + 40) {
                const g = ctx.createLinearGradient(0, fy - 20, 0, fy + 80);
                g.addColorStop(0, lake ? '#3a3524' : '#3b3a2a'); g.addColorStop(1, '#1a1912');
                ctx.fillStyle = g;
                ctx.beginPath(); ctx.moveTo(0, H + 50);
                for (let x = 0; x <= W; x += 24) ctx.lineTo(x, fy + Math.sin(x * 0.04) * 8 + Math.sin(x * 0.13) * 4);
                ctx.lineTo(W, H + 50); ctx.fill();
                ctx.strokeStyle = lake ? 'rgba(90, 130, 50, 0.75)' : 'rgba(60, 120, 60, 0.7)'; ctx.lineWidth = 4; ctx.lineCap = 'round';
                for (let i = 0; i < 9; i++) {
                    const x = 20 + i * 55, base = fy + Math.sin(x * 0.04) * 8;
                    ctx.beginPath(); ctx.moveTo(x, base);
                    ctx.quadraticCurveTo(x + Math.sin(G.t * 1.5 + i) * 10, base - 30, x + Math.sin(G.t * 1.5 + i + 1) * 14, base - 55 - (i % 3) * 12);
                    ctx.stroke();
                }
            }
        }
        const deepK = Math.min(1, Math.max(0, G.camY) / 80);
        ctx.fillStyle = `rgba(220, 240, 255, ${0.08 + deepK * 0.3})`;
        for (const s of G.snow) { if (s.y > surfaceY) { ctx.beginPath(); ctx.arc(s.x, s.y, s.s, 0, 6.28); ctx.fill(); } }
    }

    function drawFish(e, x, yPx, opts = {}) {
        const im = IMG[e.img], w = e.w * (opts.scale || 1);
        ctx.save();
        ctx.translate(x, yPx);
        if (opts.rot) ctx.rotate(opts.rot);
        if (!opts.rot && e.dir < 0) ctx.scale(-1, 1);
        const r = e.rarity;
        if (r === 'rare' || r === 'epic' || r === 'legendary') {
            ctx.shadowColor = RARITY[r].color;
            ctx.shadowBlur = r === 'legendary' ? 26 : r === 'epic' ? 20 : 12;
        }
        if (im && im.complete && im.naturalWidth) ctx.drawImage(im, -w / 2, -w / 2, w, w);
        else { ctx.fillStyle = '#ccc'; ctx.beginPath(); ctx.ellipse(0, 0, w * 0.4, w * 0.14, 0, 0, 6.28); ctx.fill(); }
        ctx.restore();
    }

    function drawJelly(e) {
        const x = e.x, y = sy(e.y) + Math.sin(G.t * 2 + e.x) * 6, r = e.size / 2;
        ctx.save();
        ctx.shadowColor = '#f472b6'; ctx.shadowBlur = 18;
        const g = ctx.createRadialGradient(x, y - r * 0.3, 2, x, y, r);
        g.addColorStop(0, 'rgba(255, 200, 235, 0.95)'); g.addColorStop(1, 'rgba(236, 72, 153, 0.55)');
        ctx.fillStyle = g;
        ctx.beginPath(); ctx.arc(x, y, r, Math.PI, 0); ctx.quadraticCurveTo(x, y + r * 0.35, x - r, y); ctx.fill();
        ctx.shadowBlur = 0;
        ctx.strokeStyle = 'rgba(244, 114, 182, 0.75)'; ctx.lineWidth = 2;
        for (let i = 0; i < 5; i++) {
            const tx = x - r * 0.7 + i * r * 0.35;
            ctx.beginPath(); ctx.moveTo(tx, y + 2);
            ctx.quadraticCurveTo(tx + Math.sin(G.t * 3 + i) * 6, y + r * 0.9, tx + Math.sin(G.t * 3 + i + 1) * 4, y + r * 1.6);
            ctx.stroke();
        }
        ctx.restore();
    }

    function drawSnag(e) {
        // a sunken branch with algae (lake hazard)
        const x = e.x, y = sy(e.y), len = e.size * 1.8;
        ctx.save();
        ctx.strokeStyle = '#3b2a1a'; ctx.lineWidth = 7; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(x - len / 2, y + 4); ctx.lineTo(x + len / 2, y - 4); ctx.stroke();
        ctx.lineWidth = 4;
        ctx.beginPath(); ctx.moveTo(x - len * 0.1, y + 1); ctx.lineTo(x - len * 0.25, y - 16); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(x + len * 0.2, y - 2); ctx.lineTo(x + len * 0.32, y + 14); ctx.stroke();
        ctx.strokeStyle = 'rgba(110, 160, 60, 0.8)'; ctx.lineWidth = 2;
        for (let i = 0; i < 4; i++) {
            const ax = x - len * 0.35 + i * len * 0.22;
            ctx.beginPath(); ctx.moveTo(ax, y);
            ctx.quadraticCurveTo(ax + Math.sin(G.t * 2 + i) * 5, y + 10, ax + Math.sin(G.t * 2 + i + 1) * 4, y + 20);
            ctx.stroke();
        }
        ctx.restore();
    }

    function drawRing(e) {
        const x = e.x, y = sy(e.y) + Math.sin(G.t * 2.4 + e.x) * 5;
        ctx.save();
        ctx.shadowColor = '#facc15'; ctx.shadowBlur = 18;
        ctx.strokeStyle = '#facc15'; ctx.lineWidth = 4;
        ctx.beginPath(); ctx.ellipse(x, y, 20 + Math.sin(G.t * 5) * 2, 9, 0, 0, 6.28); ctx.stroke();
        ctx.fillStyle = '#fde68a'; ctx.font = '700 12px Inter'; ctx.textAlign = 'center';
        ctx.fillText('+1', x, y + 4);
        ctx.restore();
    }

    function drawHookAndLine() {
        const h = G.hook, hy = sy(h.y), tipY = Math.max(-5, sy(-SKY + 3)), tipX = W / 2;
        ctx.strokeStyle = 'rgba(255, 255, 255, 0.75)'; ctx.lineWidth = 1.4;
        ctx.beginPath(); ctx.moveTo(tipX, tipY);
        ctx.quadraticCurveTo((tipX + h.x) / 2 + (h.tx - h.x) * 0.6, (tipY + hy) / 2, h.x, hy - 14);
        ctx.stroke();
        G.caught.forEach((c, i) => {
            const wig = Math.sin(G.t * 9 + i) * 0.25;
            drawFish(c, h.x + (i % 2 ? 9 : -9), hy + 22 + i * 16, { rot: -Math.PI / 2 + wig, scale: Math.min(1, 70 / c.w) });
        });
        ctx.save();
        ctx.translate(h.x, hy);
        ctx.shadowColor = G.t < G.zapUntil ? '#f472b6' : '#fff'; ctx.shadowBlur = 10;
        ctx.strokeStyle = '#e5e7eb'; ctx.lineWidth = 3.2; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(0, -14); ctx.lineTo(0, 6); ctx.arc(-6, 6, 6, 0, Math.PI * 0.9); ctx.stroke();
        ctx.fillStyle = '#eab308'; ctx.beginPath(); ctx.arc(0, -14, 3.5, 0, 6.28); ctx.fill();
        ctx.restore();
    }

    function drawGauge() {
        const x = W - 24, top = 70, bottom = H - 50, max = G.d.floor || 220;
        const y = (m) => top + (bottom - top) * Math.min(1, m / max);
        ctx.fillStyle = 'rgba(8, 10, 14, 0.6)'; ctx.fillRect(x - 6, top - 10, 18, bottom - top + 20);
        ctx.fillStyle = 'rgba(255, 255, 255, 0.12)'; ctx.fillRect(x, top, 6, bottom - top);
        ctx.fillStyle = 'rgba(234, 179, 8, 0.55)'; ctx.fillRect(x, top, 6, y(G.d.line) - top);
        ctx.fillStyle = 'rgba(255, 255, 255, 0.85)'; ctx.fillRect(x, top, 6, y(G.deepest) - top);
        ctx.font = '600 10px Inter'; ctx.textAlign = 'right'; ctx.fillStyle = 'rgba(255,255,255,0.6)';
        for (let m = 0; m <= max; m += max > 100 ? 50 : 20) ctx.fillText(`${m}`, x - 8, y(m) + 3);
        const cy = y(Math.max(0, G.hook.y));
        ctx.fillStyle = '#facc15';
        ctx.beginPath(); ctx.moveTo(x - 4, cy); ctx.lineTo(x - 12, cy - 6); ctx.lineTo(x - 12, cy + 6); ctx.fill();
        ctx.font = '700 15px Rajdhani'; ctx.fillStyle = '#fff';
        ctx.fillText(`${Math.max(0, Math.floor(G.hook.y))}m`, x - 15, cy + 5);
    }

    function drawPops() {
        ctx.textAlign = 'center';
        for (const p of G.pops) {
            const a = Math.min(1, (1.4 - p.t) * 2), y = sy(p.y) - p.t * 50, x = Math.max(70, Math.min(W - 90, p.x));
            ctx.globalAlpha = a;
            ctx.font = `700 ${Math.round(20 * p.scale)}px Rajdhani`;
            ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(0,0,0,0.55)'; ctx.strokeText(p.text, x, y);
            ctx.fillStyle = p.color; ctx.fillText(p.text, x, y);
        }
        ctx.globalAlpha = 1;
    }

    function draw() {
        ctx.save();
        if (G.shake > 0.3) ctx.translate(rand(-G.shake, G.shake), rand(-G.shake, G.shake));
        drawBackground();
        ctx.strokeStyle = 'rgba(255,255,255,0.5)'; ctx.lineWidth = 1;
        for (const b of G.bubbles) { ctx.beginPath(); ctx.arc(b.x, sy(b.y), b.r, 0, 6.28); ctx.stroke(); }
        for (const e of G.ents) {
            const yPx = sy(e.y);
            if (yPx < -140 || yPx > H + 140 || (e.kind === 'ring' && e.done)) continue;
            if (e.kind === 'fish' && !e.caught) drawFish(e, e.x, yPx + Math.sin(G.t * 2 + e.bob) * 3);
            else if (e.kind === 'jelly') drawJelly(e);
            else if (e.kind === 'snag') drawSnag(e);
            else if (e.kind === 'ring') drawRing(e);
        }
        if (G.phase === 'dive' || G.phase === 'reel' || G.phase === 'surface') drawHookAndLine();
        drawPops();
        ctx.restore();
        drawGauge();
    }

    let looping = false;
    function frame(t) {
        if (!G) { looping = false; return; }
        const dt = Math.max(0, Math.min(0.033, (t - last) / 1000));
        last = t;
        update(dt);
        if (!G) { looping = false; return; }
        draw();
        requestAnimationFrame(frame);
    }
    function startLoop() {
        if (looping) return; // a new drop while the last results card is still up: keep the one loop
        looping = true;
        requestAnimationFrame(frame);
    }

    // ── input ──
    window.addEventListener('keydown', (e) => {
        if (!G) return;
        keys[e.code] = true;
        if (e.code === 'Space') {
            e.preventDefault();
            if (G.phase === 'dive' && !G.auto) startReel('REEL UP');
            else if (G.phase === 'result') close();
        } else if (e.code === 'Escape') abort();
    });
    window.addEventListener('keyup', (e) => { keys[e.code] = false; });
    cv.addEventListener('mousemove', (e) => {
        const r = cv.getBoundingClientRect();
        mouseX = ((e.clientX - r.left) / r.width) * W;
    });
    $('ddResults').addEventListener('click', () => { if (G && G.phase === 'result') close(); });

    return { open, result, close, abort, state: () => G, _tick: (dt) => G && update(dt) }; // _tick: headless tests
})();

window.addEventListener('message', ({ data: m }) => {
    if (m.action === 'drop') DD.open(m.data);
    else if (m.action === 'dropResult') DD.result(m.data);
    else if (m.action === 'stopDrop') DD.close();
});

// ── Browser preview (outside FiveM): ?drop=coast|lake|deep[&auto][&lvl=5] with fake server data ──
if (!inGame && location.search.includes('drop')) {
    const q = new URLSearchParams(location.search);
    const makeFake = (habitat, lvl) => {
    const F = {
        anchovy: ['common', [0.05, 0.2], 40], sardine: ['common', [0.1, 0.3], 35], mackerel: ['common', [0.3, 1.2], 18],
        seabass: ['uncommon', [1, 5], 11], snapper: ['uncommon', [1, 6], 12], halibut: ['rare', [5, 25], 7], stingray: ['rare', [3, 15], 9],
        octopus: ['epic', [2, 9], 30], moray: ['epic', [2, 12], 24], bluegill: ['common', [0.1, 0.5], 30], carp: ['common', [1, 8], 4],
        catfish: ['uncommon', [2, 15], 6], bass: ['uncommon', [1, 5], 12], trout: ['rare', [1, 4], 24], pike: ['rare', [2, 10], 10],
        sturgeon: ['epic', [10, 60], 6], goldcarp: ['legendary', [3, 10], 110], mackerel2: ['common', [2, 10], 6], mahi: ['uncommon', [5, 20], 7],
        tuna: ['uncommon', [20, 120], 3], barracuda: ['rare', [5, 25], 9], swordfish: ['epic', [50, 250], 3], marlin: ['epic', [80, 400], 2],
        hammerhead: ['legendary', [80, 300], 4], greatwhite: ['legendary', [300, 900], 2],
    };
    const itemOf = (id) => (id === 'mackerel2' ? 'fish_kingmackerel' : `fish_${id}`);
    const HAB = {
        coast: { floor: 60, line: Math.min(59, 30 + (lvl - 1) * 4), bands: [[4, 18, 3, 'anchovy sardine mackerel'], [15, 34, 2.8, 'mackerel seabass snapper stingray'], [30, 50, 2.4, 'seabass snapper halibut stingray octopus'], [45, 58, 2.2, 'halibut octopus moray']], junk: ['boot', 'can', 'tire'] },
        lake: { floor: 40, line: Math.min(39, 24 + (lvl - 1) * 3), bands: [[4, 14, 3, 'bluegill carp bass'], [10, 26, 2.8, 'carp catfish bass trout'], [22, 39, 2.4, 'catfish pike trout sturgeon goldcarp']], junk: ['boot', 'tire'] },
        deep: { floor: null, line: 50 + (lvl - 1) * 17, bands: [[4, 30, 2.4, 'mackerel2 mahi'], [25, 80, 2, 'mahi tuna mackerel2 barracuda'], [70, 140, 1.7, 'tuna barracuda swordfish marlin'], [130, 215, 1.3, 'marlin swordfish hammerhead greatwhite']] },
    }[habitat];
    const ents = [];
    const lvlOk = (r) => ({ epic: 4, legendary: 7 }[r] || 1) <= lvl;
    for (const [from, to, dens, mix] of HAB.bands) {
        const ids = mix.split(' ').filter((id) => lvlOk(F[id][0]));
        if (!ids.length) continue; // every fish here is locked at this level
        for (let n = Math.round((to - from) / 10 * dens * 1.35); n > 0; n--) {
            const id = ids[Math.floor(Math.random() * ids.length)], [rarity, kg, price] = F[id];
            const w = Math.round((kg[0] + (kg[1] - kg[0]) * Math.random() ** 2) * 10) / 10;
            ents.push({ i: ents.length + 1, kind: 'fish', id, item: itemOf(id), label: id, rarity, kg: w, value: Math.max(1, Math.floor(w * price)),
                        y: from + Math.random() * (to - from), x: Math.random(), dir: Math.random() < 0.5 ? -1 : 1, speed: 1 + (lvl - 1) * 0.06 });
        }
    }
    for (const id of HAB.junk || []) ents.push({ i: ents.length + 1, kind: 'fish', id, item: `junk_${id}`, label: id, junk: true, rarity: 'junk', kg: 0, value: 2, y: HAB.floor - 0.6, x: Math.random(), dir: 1, speed: 0 });
    for (let n = Math.floor(3 + lvl * 0.8); n > 0; n--) ents.push({ i: ents.length + 1, kind: habitat === 'lake' ? 'snag' : 'jelly', x: 0.08 + Math.random() * 0.8, size: 30 + Math.random() * 14, y: 12 + Math.random() * (HAB.line - 14) });
    for (let n = 2; n > 0; n--) ents.push({ i: ents.length + 1, kind: 'ring', x: 0.12 + Math.random() * 0.68, y: 8 + Math.random() * HAB.line * 0.77 });

        return { habitat, spot: { coast: 'Del Perro Pier', lake: 'Alamo Sea', deep: 'Deep Sea' }[habitat], level: lvl, line: HAB.line, floor: HAB.floor,
                 hooks: 3 + Math.floor(lvl / 3), ents };
    };
    window.__makeFake = makeFake;
    const habitat = q.get('drop') || 'coast', lvl = Number(q.get('lvl') || 3);
    let ents = [];
    document.body.style.background = 'linear-gradient(160deg, #2b4c5c, #183240 60%, #0f222c)';
    const realPost = post;
    post = (name, body) => {
        if (name === 'dropDone' && !body.aborted) {
            const catches = body.caught.map((i) => ents[i - 1]).map((e) => ({ label: e.label, rarity: e.junk ? 'common' : e.rarity, junk: e.junk, weight: e.kg, value: e.value, item: e.item, xp: 7 }));
            setTimeout(() => DD.result({ catches, xp: catches.length * 7 }), 300);
        }
        return realPost(name, body);
    };
    if (!q.has('sim')) {
        const d = makeFake(habitat, lvl);
        ents = d.ents;
        DD.open({ ...d, auto: q.has('auto') });
    }
}
