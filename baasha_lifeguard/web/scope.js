// ── Tower watch: binoculars ────────────────────────────────────────────────
// Scan the beach panorama through the binoculars and mark the swimmer in trouble (both arms flailing,
// going under) or the shark fin. Friendly wavers (one arm, calm) are NOT in trouble: marking the wrong
// person costs time. Uses post / $ / sfx from app.js.

const Scope = (() => {
    const cv = $('scopeCv'), ctx = cv.getContext('2d');
    const ZOOM = 2.3;
    let W = 0, H = 0, PW = 0, HZ = 0, SH = 0, U = 16;
    let S = null, looping = false, last = 0;

    const rand = (a, b) => a + Math.random() * (b - a);
    const pick = (a) => a[Math.floor(Math.random() * a.length)];
    const SKIN = ['#f1c7a5', '#d9a27c', '#a86f4c', '#7a4a2e', '#f5d2b8'];
    const HAIR = ['#2b1d14', '#5a3a22', '#d9b36c', '#141414', '#8a4b2a'];
    const CAPS = ['#ef4444', '#facc15', '#22c55e', '#3b82f6', '#f472b6', null, null, null];
    const RINGS = ['#f472b6', '#facc15', '#fb923c', '#38bdf8'];

    // depth d: 0 = near the shore, 1 = the horizon
    const yOf = (d) => HZ + (SH - HZ) * Math.pow(1 - d, 1.7);
    const sOf = (d) => 0.18 + 0.82 * Math.pow(1 - d, 1.5);

    function resize() {
        W = cv.width = window.innerWidth;
        H = cv.height = window.innerHeight;
        PW = Math.max(W, H * 1.6) * 2.6; HZ = H * 0.34; SH = H * 0.86; U = H / 62;
    }

    // ── scene ──
    function look() { return { skin: pick(SKIN), hair: pick(HAIR), cap: pick(CAPS), ring: pick(RINGS) }; }

    function place(objs, minGap) {
        for (let tries = 0; tries < 40; tries++) {
            const x = rand(0.03, 0.97) * PW, d = rand(0.05, 0.82);
            if (objs.every((o) => !o.person || Math.abs(o.x - x) > minGap || Math.abs(o.d - d) > 0.16)) return { x, d };
        }
        return { x: rand(0.03, 0.97) * PW, d: rand(0.05, 0.82) };
    }

    function build() {
        const p = S.p, objs = [];
        const shark = p.target === 'shark';
        S.tgt = { kind: shark ? 'shark' : 'drown', person: !shark, target: true, x: rand(0.12, 0.88) * PW, d: rand(0.22, 0.6), ph: rand(0, 6.28), vx: 0, ...look() };
        objs.push(S.tgt);
        for (let i = 0; i < p.swimmers; i++) {
            const r = Math.random();
            const kind = r < 0.6 ? 'swim' : r < 0.85 ? 'float' : 'surf';
            objs.push({ kind, person: true, ...place(objs, PW * 0.035), ph: rand(0, 6.28), vx: rand(-7, 7), ...look() });
        }
        for (let i = 0; i < p.decoys; i++) objs.push({ kind: 'wave', person: true, decoy: true, ...place(objs, PW * 0.05), ph: rand(0, 6.28), vx: 0, ...look() });
        for (let i = 0; i < 6; i++) objs.push({ kind: 'buoy', x: (i + rand(0.2, 0.8)) / 6 * PW, d: 0.5 + rand(-0.03, 0.03), ph: rand(0, 6.28), vx: 0 });
        objs.push({ kind: 'boat', x: rand(0.1, 0.9) * PW, d: rand(0.9, 0.96), ph: 0, vx: rand(8, 16) * (Math.random() < 0.5 ? -1 : 1) });
        S.objs = objs.sort((a, b) => b.d - a.d);
        S.gulls = Array.from({ length: 6 }, () => ({ x: rand(0, PW), y: rand(H * 0.08, HZ * 0.85), sp: rand(18, 40) * (Math.random() < 0.5 ? -1 : 1), ph: rand(0, 6.28) }));
        S.clouds = Array.from({ length: 7 }, () => ({ x: rand(0, PW), y: rand(H * 0.05, HZ * 0.7), w: rand(120, 260) }));
    }

    function open(p) {
        resize();
        S = {
            p: { time: 25, swimmers: 8, decoys: 0, target: 'drowning', falseAlarm: 3, towerLabel: 'Tower 1', bonus: 25, ...p },
            t: 0, penalty: 0, falseAlarms: 0, found: false, done: false, splashes: [], auto: !!p.auto,
            cam: { x: PW / 2, y: H * 0.62 }, mouse: { x: W / 2, y: H * 0.62 }, lastMark: 0, autoT: 0, autoAim: null, lockFor: 0,
        };
        build();
        $('scopeTower').textContent = `${S.p.towerLabel.toUpperCase()} · SCAN THE WATER`;
        $('scopeBonus').textContent = `SPOT IT YOURSELF: +${S.p.bonus}% PAY`;
        $('scopeMsg').className = 'scope-msg';
        $('scope').classList.remove('off');
        last = performance.now();
        if (!looping) { looping = true; requestAnimationFrame(frame); }
    }

    function close() { S = null; $('scope').classList.add('off'); }

    function finish(found) {
        if (!S || S.done) return;
        S.done = true;
        const res = { found, falseAlarms: S.falseAlarms, time: Math.round(S.t * 10) / 10 };
        setTimeout(() => { post('watchDone', res); close(); }, found ? 1700 : 1400);
    }

    function msg(text, cls) {
        const m = $('scopeMsg');
        m.className = 'scope-msg';
        m.textContent = text;
        void m.offsetWidth;
        m.classList.add('show', cls);
    }

    // ── marking what's in the reticle ──
    function headPos(o) {
        const u = U * sOf(o.d), y = yOf(o.d);
        return { x: o.sx ?? o.x, y: o.kind === 'shark' ? y - u * 0.5 : y - u * 0.6, u };
    }

    function mark() {
        if (!S || S.done || S.t - S.lastMark < 0.35) return;
        S.lastMark = S.t;
        const c = S.cam, R = 46 / ZOOM;
        let best = null, bestD = 1e9;
        for (const o of S.objs) {
            if (!o.person && o.kind !== 'shark') continue;
            const h = headPos(o);
            const d = Math.hypot(h.x - c.x, h.y - c.y);
            if (d < R + h.u * 0.9 && d < bestD) { best = o; bestD = d; }
        }
        if (best && best.target) {
            S.found = true;
            sfx.spot();
            msg(best.kind === 'shark' ? 'SHARK SPOTTED!' : 'SWIMMER IN TROUBLE!', 'good');
            finish(true);
        } else if (best) {
            S.falseAlarms++;
            S.penalty += S.p.falseAlarm;
            sfx.buzz();
            msg(`FALSE ALARM  -${S.p.falseAlarm}s`, 'bad');
        } else {
            msg('NOTHING THERE', 'meh');
        }
    }

    // ── drawing ──
    function circle(x, y, r, color) { ctx.fillStyle = color; ctx.beginPath(); ctx.arc(x, y, r, 0, 6.2832); ctx.fill(); }

    function arm(x0, y0, x1, y1, u, skin) {
        ctx.strokeStyle = skin; ctx.lineWidth = u * 0.24; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
        circle(x1, y1, u * 0.16, skin);
    }

    function head(x, y, u, o) {
        circle(x, y, u * 0.5, o.skin);
        ctx.fillStyle = o.cap || o.hair;
        ctx.beginPath(); ctx.arc(x, y - u * 0.04, u * 0.52, Math.PI * 1.02, Math.PI * 1.98); ctx.fill();
    }

    function ripple(x, y, u, a = 0.55) {
        ctx.strokeStyle = `rgba(255,255,255,${a})`; ctx.lineWidth = Math.max(1, u * 0.09);
        ctx.beginPath(); ctx.ellipse(x, y, u * 1.25, u * 0.26, 0, 0, 6.2832); ctx.stroke();
    }

    function splash(x, y, u, n) {
        for (let i = 0; i < n; i++) S.splashes.push({ x: x + rand(-u, u), y, y0: y, vx: rand(-u, u) * 1.6, vy: -rand(u * 2, u * 4.5), life: rand(0.35, 0.7), r: u * rand(0.07, 0.16) });
    }

    function drawPerson(o, t) {
        const u = U * sOf(o.d), y = yOf(o.d), x = o.sx;
        let bob = Math.sin(t * 2 + o.ph) * u * 0.1;
        ctx.save();
        ctx.beginPath(); ctx.rect(x - u * 6, y - u * 8, u * 12, u * 8); ctx.clip(); // only what's above the water
        if (o.kind === 'drown') {
            // flailing: both arms up, head bobbing hard, going under every few seconds
            const cyc = (t + o.ph) % 2.7;
            const under = cyc > 1.8 ? Math.sin(((cyc - 1.8) / 0.9) * Math.PI) : 0;
            bob = Math.sin(t * 7.5 + o.ph) * u * 0.22 + under * u * 0.95;
            const hy = y - u * 0.42 + bob;
            for (const s of [-1, 1]) {
                const hx = x + s * u * (0.75 + 0.35 * Math.sin(t * 9 + s * 1.7 + o.ph));
                const hyy = y - u * (1.5 + 0.4 * Math.sin(t * 11 + s * 2.3)) + under * u * 0.6;
                arm(x + s * u * 0.35, y - u * 0.05 + bob * 0.4, hx, hyy, u, o.skin);
            }
            head(x, hy, u, o);
            if (Math.random() < 0.35) splash(x, y, u, 1);
        } else if (o.kind === 'wave') {
            // friendly wave: one arm up, calm head, no splashing
            const hy = y - u * 0.45 + bob;
            const ang = -1.35 + Math.sin(t * 3.2 + o.ph) * 0.45;
            arm(x + u * 0.35, y - u * 0.1, x + u * 0.35 + Math.cos(ang) * u * 1.35, y - u * 0.1 + Math.sin(ang) * u * 1.35, u, o.skin);
            head(x, hy, u, o);
        } else if (o.kind === 'float') {
            head(x, y - u * 0.55 + bob, u, o);
        } else if (o.kind === 'surf') {
            // lying on the board, paddling
            ctx.restore(); ctx.save();
            ctx.fillStyle = o.ring; ctx.beginPath(); ctx.ellipse(x, y - u * 0.05 + bob * 0.3, u * 1.9, u * 0.26, 0, 0, 6.2832); ctx.fill();
            ctx.fillStyle = '#1f2937'; ctx.beginPath(); ctx.ellipse(x - u * 0.2, y - u * 0.3 + bob * 0.3, u * 0.95, u * 0.22, 0, 0, 6.2832); ctx.fill();
            head(x + u * 0.85, y - u * 0.45 + bob * 0.3, u * 0.85, o);
        } else {
            // swimming: an arm comes over now and then
            const hy = y - u * 0.4 + bob;
            const st = (t * 0.8 + o.ph) % 2.4;
            if (st < 0.8) {
                const a = Math.PI + (st / 0.8) * Math.PI, s = Math.floor((t * 0.8 + o.ph) / 2.4) % 2 ? 1 : -1;
                arm(x + s * u * 0.4, y - u * 0.05, x + s * u * 0.4 + Math.cos(a) * u * 0.9 * s, y - u * 0.05 + Math.sin(a) * u * 0.9, u, o.skin);
            }
            head(x, hy, u, o);
        }
        ctx.restore();
        if (o.kind === 'float') {
            ctx.strokeStyle = o.ring; ctx.lineWidth = u * 0.42;
            ctx.beginPath(); ctx.ellipse(x, y - u * 0.02 + bob * 0.3, u * 1.05, u * 0.32, 0, 0, 6.2832); ctx.stroke();
        } else if (o.kind !== 'surf') ripple(x, y + bob * 0.2, u, o.kind === 'drown' ? 0.85 : 0.5);
    }

    function drawShark(o, t) {
        const u = U * sOf(o.d), y = yOf(o.d);
        const ph = t * 0.35 + o.ph;
        o.sx = o.x + Math.sin(ph) * PW * 0.06;
        const dir = Math.cos(ph) >= 0 ? 1 : -1;
        const vis = 0.55 + 0.45 * Math.max(0, Math.sin(t * 0.9 + o.ph)); // the fin dips and comes back up
        const x = o.sx, hgt = u * 1.5 * vis;
        // wake
        ctx.strokeStyle = 'rgba(255,255,255,0.55)'; ctx.lineWidth = Math.max(1, u * 0.08);
        ctx.beginPath(); ctx.moveTo(x + dir * u * 0.6, y); ctx.lineTo(x - dir * u * 2.6, y - u * 0.25);
        ctx.moveTo(x + dir * u * 0.6, y); ctx.lineTo(x - dir * u * 2.6, y + u * 0.25); ctx.stroke();
        ctx.fillStyle = '#3f4a57';
        ctx.beginPath();
        ctx.moveTo(x - dir * u * 0.55, y);
        ctx.quadraticCurveTo(x - dir * u * 0.1, y - hgt * 0.7, x - dir * u * 0.55, y - hgt);
        ctx.quadraticCurveTo(x + dir * u * 0.25, y - hgt * 0.45, x + dir * u * 0.6, y);
        ctx.closePath(); ctx.fill();
    }

    function drawThing(o, t) {
        const u = U * sOf(o.d), y = yOf(o.d);
        if (o.kind === 'buoy') {
            const by = y + Math.sin(t * 1.6 + o.ph) * u * 0.08;
            ctx.save(); ctx.beginPath(); ctx.rect(o.x - u * 2, by - u * 2, u * 4, u * 2); ctx.clip();
            circle(o.x, by, u * 0.45, '#f97316'); ctx.restore();
            ripple(o.x, by, u * 0.6, 0.4);
        } else if (o.kind === 'boat') {
            const x = o.sx;
            ctx.fillStyle = '#f8fafc';
            ctx.beginPath(); ctx.moveTo(x - u * 3, y - u * 0.6); ctx.lineTo(x + u * 3.4, y - u * 0.6); ctx.lineTo(x + u * 2.6, y); ctx.lineTo(x - u * 2.6, y); ctx.closePath(); ctx.fill();
            ctx.fillStyle = '#cbd5e1'; ctx.fillRect(x - u * 1.2, y - u * 1.3, u * 2, u * 0.7);
        }
    }

    function drawWorld(t) {
        const vw = W / ZOOM, x0 = S.cam.x - vw / 2 - 40, x1 = S.cam.x + vw / 2 + 40;
        // sky
        let g = ctx.createLinearGradient(0, 0, 0, HZ);
        g.addColorStop(0, '#5fb2e6'); g.addColorStop(1, '#d6edf7');
        ctx.fillStyle = g; ctx.fillRect(x0, -H, x1 - x0, HZ + H);
        const sunX = PW * 0.7;
        g = ctx.createRadialGradient(sunX, HZ * 0.35, 4, sunX, HZ * 0.35, 120);
        g.addColorStop(0, 'rgba(255,253,230,1)'); g.addColorStop(0.25, 'rgba(255,245,200,0.7)'); g.addColorStop(1, 'rgba(255,245,200,0)');
        ctx.fillStyle = g; ctx.fillRect(sunX - 120, HZ * 0.35 - 120, 240, 240);
        for (const c of S.clouds) {
            const cx = ((c.x + t * 6) % (PW + 300)) - 150;
            ctx.fillStyle = 'rgba(255,255,255,0.75)';
            ctx.beginPath(); ctx.ellipse(cx, c.y, c.w * 0.5, c.w * 0.12, 0, 0, 6.2832); ctx.fill();
            ctx.beginPath(); ctx.ellipse(cx + c.w * 0.12, c.y - c.w * 0.07, c.w * 0.25, c.w * 0.1, 0, 0, 6.2832); ctx.fill();
        }
        ctx.strokeStyle = 'rgba(30,41,59,0.75)'; ctx.lineWidth = 1.4;
        for (const b of S.gulls) {
            const gx = ((b.x + t * b.sp) % PW + PW) % PW, gy = b.y + Math.sin(t + b.ph) * 6, f = Math.sin(t * 7 + b.ph) * 3;
            ctx.beginPath(); ctx.moveTo(gx - 6, gy - f); ctx.quadraticCurveTo(gx - 3, gy - 3, gx, gy); ctx.quadraticCurveTo(gx + 3, gy - 3, gx + 6, gy - f); ctx.stroke();
        }
        // sea
        g = ctx.createLinearGradient(0, HZ, 0, SH);
        g.addColorStop(0, '#2d7fa8'); g.addColorStop(0.55, '#1f6f99'); g.addColorStop(1, '#35a9b9');
        ctx.fillStyle = g; ctx.fillRect(x0, HZ, x1 - x0, SH - HZ);
        ctx.fillStyle = 'rgba(255,250,220,0.25)'; ctx.fillRect(sunX - 60, HZ, 120, 2); // sun glint
        for (let i = 1; i < 46; i++) {
            const d = 1 - i / 46, y = yOf(d), s = sOf(d);
            ctx.strokeStyle = `rgba(255,255,255,${0.05 + 0.12 * (1 - d)})`;
            ctx.lineWidth = Math.max(0.6, 1.6 * s);
            ctx.beginPath();
            const k = 0.012 / s, off = t * (0.8 + i * 0.03) + i * 1.7;
            for (let x = x0; x <= x1; x += 14) {
                const yy = y + Math.sin(x * k + off) * 2.2 * s;
                if (x === x0) ctx.moveTo(x, yy); else ctx.lineTo(x, yy);
            }
            ctx.stroke();
        }
        // things in the water, far to near
        for (const o of S.objs) {
            if (o.kind === 'boat') o.sx = ((o.x + t * o.vx) % PW + PW) % PW;
            else if (o.kind !== 'shark') o.sx = o.x + Math.sin(t * 0.15 + o.ph) * 10 + o.vx * t;
            if ((o.sx ?? o.x) < x0 - 300 || (o.sx ?? o.x) > x1 + 300) { if (o.kind === 'shark') drawShark(o, t); continue; }
            if (o.kind === 'shark') drawShark(o, t);
            else if (o.person) drawPerson(o, t);
            else drawThing(o, t);
        }
        // splashes
        ctx.fillStyle = 'rgba(255,255,255,0.9)';
        for (const s of S.splashes) { ctx.beginPath(); ctx.arc(s.x, s.y, s.r, 0, 6.2832); ctx.fill(); }
        // foam + sand
        const fy = SH + Math.sin(t * 0.7) * 6;
        g = ctx.createLinearGradient(0, fy, 0, H * 1.3);
        g.addColorStop(0, '#eadbb0'); g.addColorStop(1, '#d4b97f');
        ctx.fillStyle = g; ctx.fillRect(x0, fy, x1 - x0, H * 1.3 - fy);
        ctx.strokeStyle = 'rgba(255,255,255,0.9)'; ctx.lineWidth = 5;
        ctx.beginPath();
        for (let x = x0; x <= x1; x += 12) {
            const yy = fy + Math.sin(x * 0.03 + t * 1.3) * 3;
            if (x === x0) ctx.moveTo(x, yy); else ctx.lineTo(x, yy);
        }
        ctx.stroke();
        // found: a pulsing ring on the target
        if (S.found) {
            const h = headPos(S.tgt), r = h.u * 2.2 + Math.sin(t * 10) * 3;
            ctx.strokeStyle = '#4ade80'; ctx.lineWidth = 2.5;
            ctx.beginPath(); ctx.arc(h.x, h.y, r, 0, 6.2832); ctx.stroke();
        }
    }

    function drawLens(t) {
        const R = Math.min(H * 0.44, W * 0.27), off = R * 0.66, cx = W / 2, cy = H / 2;
        ctx.fillStyle = '#000'; ctx.fillRect(0, 0, W, H);
        ctx.save();
        ctx.beginPath(); ctx.arc(cx - off, cy, R, 0, 6.2832); ctx.arc(cx + off, cy, R, 0, 6.2832); ctx.clip();
        ctx.save();
        ctx.translate(W / 2, H / 2); ctx.scale(ZOOM, ZOOM); ctx.translate(-S.cam.x, -S.cam.y);
        drawWorld(t);
        ctx.restore();
        // lens darkening at the edges (one stretched gradient over both eyepieces)
        ctx.save();
        ctx.translate(cx, cy); ctx.scale((R + off) / R, 1);
        const g = ctx.createRadialGradient(0, 0, R * 0.55, 0, 0, R * 1.02);
        g.addColorStop(0, 'rgba(0,0,0,0)'); g.addColorStop(1, 'rgba(0,0,0,0.6)');
        ctx.fillStyle = g; ctx.fillRect(-R * 1.1, -R * 1.1, R * 2.2, R * 2.2);
        ctx.restore();
        // reticle
        ctx.strokeStyle = 'rgba(10,15,20,0.6)'; ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.moveTo(cx - R * 1.4, cy); ctx.lineTo(cx - 52, cy); ctx.moveTo(cx + 52, cy); ctx.lineTo(cx + R * 1.4, cy);
        ctx.moveTo(cx, cy - R); ctx.lineTo(cx, cy - 52); ctx.moveTo(cx, cy + 52); ctx.lineTo(cx, cy + R); ctx.stroke();
        for (let i = -6; i <= 6; i++) { if (!i) continue; ctx.beginPath(); ctx.moveTo(cx + i * 40, cy - 5); ctx.lineTo(cx + i * 40, cy + 5); ctx.stroke(); }
        ctx.strokeStyle = S.found ? '#4ade80' : 'rgba(239,68,68,0.85)'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(cx, cy, 46, 0, 6.2832); ctx.stroke();
        ctx.restore();
        // a thin rim
        ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.arc(cx - off, cy, R, 0, 6.2832); ctx.stroke();
        ctx.beginPath(); ctx.arc(cx + off, cy, R, 0, 6.2832); ctx.stroke();
    }

    // ── update ──
    function autoAim(dt) {
        const vw = W / ZOOM, h = headPos(S.tgt);
        S.autoT += dt;
        if (!S.autoAim) S.autoAim = { x: S.cam.x, y: yOf(0.42), phase: 'sweep', dir: h.x > S.cam.x ? 1 : -1 };
        const a = S.autoAim;
        if (a.phase === 'sweep') {
            a.x += a.dir * vw * 0.85 * dt;
            if (a.x > PW - vw / 2) a.dir = -1;
            if (a.x < vw / 2) a.dir = 1;
            a.y = yOf(0.42) + Math.sin(S.autoT * 0.8) * 30;
            if (Math.abs(h.x - S.cam.x) < vw * 0.28 && S.autoT > 1.2) a.phase = 'lock';
        } else {
            a.x = h.x; a.y = h.y;
            const close = Math.hypot(h.x - S.cam.x, h.y - S.cam.y) < 8;
            S.lockFor = close ? S.lockFor + dt : 0;
            if (S.lockFor > 0.45 && !S.p.peek) mark();
        }
        return a;
    }

    function update(dt) {
        S.t += dt;
        const vw = W / ZOOM, vh = H / ZOOM;
        let aim;
        if (S.auto) aim = autoAim(dt);
        else {
            const mx = S.mouse.x / W, my = S.mouse.y / H;
            aim = { x: vw / 2 + mx * (PW - vw), y: (HZ - H * 0.08 + vh / 2) + my * ((SH + H * 0.04 - vh / 2) - (HZ - H * 0.08 + vh / 2)) };
        }
        const k = Math.min(1, dt * (S.auto ? 3.2 : 7));
        S.cam.x += (aim.x - S.cam.x) * k;
        S.cam.y += (aim.y - S.cam.y) * k;
        if (!S.done) { // hands are never perfectly still
            S.cam.x += Math.sin(S.t * 1.3) * 0.25;
            S.cam.y += Math.cos(S.t * 1.7) * 0.18;
        }
        for (const s of S.splashes) { s.x += s.vx * dt; s.y += s.vy * dt; s.vy += 260 * dt; s.life -= dt; }
        S.splashes = S.splashes.filter((s) => s.life > 0 && !(s.vy > 0 && s.y > s.y0)); // drops vanish back into the water
        const left = Math.max(0, S.p.time - S.t - S.penalty);
        $('scopeTime').style.width = `${(left / S.p.time) * 100}%`;
        $('scopeTime').classList.toggle('low', left < 6);
        if (S.auto && !S.done && left < 3) {
            // autoplay (test / showcase) never runs out of time: lock straight onto the target
            const h = headPos(S.tgt);
            S.cam.x = h.x; S.cam.y = h.y; S.lastMark = -1;
            mark();
        }
        if (left <= 0 && !S.done) { msg('NOTHING SPOTTED', 'meh'); finish(false); }
    }

    function frame(now) {
        if (!S) { looping = false; return; }
        const dt = Math.max(0, Math.min(0.05, (now - last) / 1000));
        last = now;
        update(dt);
        drawLens(S.t);
        requestAnimationFrame(frame);
    }

    // ── input ──
    window.addEventListener('mousemove', (e) => { if (S) { S.mouse.x = e.clientX; S.mouse.y = e.clientY; } });
    window.addEventListener('mousedown', (e) => { if (S && !S.auto && e.button === 0) mark(); });
    window.addEventListener('keydown', (e) => {
        if (!S || S.auto) return;
        if (e.code === 'Space' || e.code === 'KeyE') { e.preventDefault(); mark(); }
        if (e.code === 'Escape' || e.code === 'Backspace') { msg('WATCH ENDED', 'meh'); finish(false); }
    });
    window.addEventListener('resize', () => { if (S) { const cx = S.cam.x / PW; resize(); S.cam.x = cx * PW; } });

    return { open, close, state: () => S };
})();

window.addEventListener('message', ({ data: m }) => {
    if (m.action === 'scope') Scope.open(m.data);
    else if (m.action === 'closeScope') Scope.close();
});

// ── Browser preview (outside FiveM): ?scope[&play][&shark][&lvl=N] ─────────
if (!inGame && location.search.includes('scope')) {
    const q = new URLSearchParams(location.search);
    const lvl = Number(q.get('lvl') || 2);
    setTimeout(() => Scope.open({
        towerLabel: 'Tower 2', auto: !q.has('play'), peek: q.has('peek'), target: q.has('shark') ? 'shark' : 'drowning',
        time: q.has('peek') ? 999 : Math.max(15, 26 - (lvl - 1)), swimmers: Math.min(16, 8 + lvl - 1), decoys: lvl >= 2 ? Math.min(4, lvl - 1) : 0, bonus: lvl >= 4 ? 50 : 25,
    }), 300);
}
