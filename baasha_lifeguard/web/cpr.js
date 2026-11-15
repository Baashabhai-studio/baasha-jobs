// ── CPR minigame ──────────────────────────────────────────────────────────
// 1. Chest compressions: press on every beat of the metronome ring (PERFECT / GOOD / MISS).
// 2. Rescue breaths: hold to fill the lungs, let go in the green zone (too much air is a miss).
// Do the cycles with good rhythm and the heart restarts: the monitor goes from flatline to a normal beat.
// Uses post / $ / sfx from app.js.

const CPR = (() => {
    const cv = $('ecg'), ctx = cv.getContext('2d');
    const EW = cv.width, EH = cv.height, BASE = EH * 0.58;
    let G = null, last = 0, looping = false;
    const keys = { held: false };

    const rand = (a, b) => a + Math.random() * (b - a);

    // ── ECG monitor (sweeping trace like a real defibrillator screen) ──
    const trace = new Float32Array(EW).fill(BASE);
    let sweepX = 0, waveT = 0;
    const artifacts = []; // compression spikes: { t0 }

    function pqrst(phase) {
        // one heartbeat (phase 0..1) → displacement (up is negative on canvas)
        const bump = (c, w, h) => h * Math.exp(-Math.pow((phase - c) / w, 2));
        return -(bump(0.18, 0.035, 10) - bump(0.30, 0.008, 12) + bump(0.32, 0.012, 62) - bump(0.345, 0.01, 22) + bump(0.58, 0.06, 18));
    }

    function sample(t) {
        let y = BASE + rand(-1.2, 1.2);
        if (G && G.heart > 0) {
            const period = 60 / G.heart;
            y += pqrst((t % period) / period);
        }
        for (const a of artifacts) {
            const d = t - a.t0;
            if (d >= 0 && d < 0.22) y -= Math.sin((d / 0.22) * Math.PI) * 48 * (d < 0.06 ? 1.4 : 1);
        }
        return y;
    }

    function drawEcg(dt) {
        const speed = 190; // px per second
        let n = Math.max(1, Math.round(speed * dt));
        while (n-- > 0) {
            waveT += 1 / speed;
            trace[sweepX] = sample(waveT);
            sweepX = (sweepX + 1) % EW;
        }
        while (artifacts.length && waveT - artifacts[0].t0 > 1) artifacts.shift();
        ctx.fillStyle = '#020805';
        ctx.fillRect(0, 0, EW, EH);
        ctx.strokeStyle = 'rgba(74, 222, 128, 0.07)';
        ctx.lineWidth = 1;
        for (let x = 0; x < EW; x += 38) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, EH); ctx.stroke(); }
        for (let y = 0; y < EH; y += 38) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(EW, y); ctx.stroke(); }
        const color = G && G.heart > 0 ? '#4ade80' : '#22c55e';
        ctx.strokeStyle = color; ctx.lineWidth = 2.6; ctx.shadowColor = color; ctx.shadowBlur = 8;
        ctx.beginPath();
        let started = false;
        for (let i = 0; i < EW; i++) {
            const gap = (i - sweepX + EW) % EW; // blank area just ahead of the sweep
            if (gap > 0 && gap < 22) { started = false; continue; }
            if (!started) { ctx.moveTo(i, trace[i]); started = true; } else ctx.lineTo(i, trace[i]);
        }
        ctx.stroke();
        ctx.shadowBlur = 0;
        ctx.fillStyle = color;
        ctx.beginPath(); ctx.arc(sweepX, trace[(sweepX - 1 + EW) % EW], 4, 0, 6.28); ctx.fill();
    }

    // ── flow ──
    function open(p) {
        G = {
            p: { cycles: 2, compressions: 30, bpm: 110, perfect: 0.07, good: 0.15, pass: 0.6, maxExtra: 1, ...p },
            t: 0, phase: 'compress', cycle: 1, count: 0, breaths: 0, samples: [], heart: 0, lung: 0,
            beatStart: 0.8, lastJudged: -1, alarmAt: 0, done: false, extra: 0, auto: !!p.auto, autoHold: null, spo2: rand(68, 74),
        };
        artifacts.length = 0;
        trace.fill(BASE);
        $('cprTitle').textContent = G.p.title || 'Unconscious swimmer';
        $('pressTotal').textContent = G.p.compressions;
        $('monState').textContent = 'NO PULSE';
        $('monState').classList.remove('ok');
        $('monHr').textContent = '--';
        showPhase('compress');
        hud();
        $('cpr').classList.remove('off');
        last = performance.now();
        if (!looping) { looping = true; requestAnimationFrame(frame); }
    }

    function close() { G = null; $('cpr').classList.add('off'); }

    function showPhase(ph) {
        G.phase = ph;
        $('pressView').classList.toggle('off', ph === 'breath');
        $('breathView').classList.toggle('off', ph !== 'breath');
        if (ph === 'compress') { G.count = 0; G.beatStart = G.t + 0.8; G.lastJudged = -1; }
        if (ph === 'breath') { G.breaths = 0; G.lung = 0; }
        post('cprPhase', { phase: ph }); // the game switches the CPR animation
    }

    function accuracy() {
        if (!G.samples.length) return 1;
        return G.samples.reduce((a, b) => a + b, 0) / G.samples.length;
    }

    function hud() {
        $('pressCount').textContent = G.count;
        $('breathCount').textContent = G.breaths;
        const acc = accuracy();
        $('rhythmBar').style.width = `${Math.round(acc * 100)}%`;
        $('rhythmPct').textContent = `${Math.round(acc * 100)}%`;
        $('cprCycle').textContent = `CYCLE ${G.cycle} / ${G.p.cycles + G.extra}`;
        $('monSpo2').textContent = Math.round(G.spo2);
    }

    function flash(text, color, big) {
        const f = $('cprFlash');
        f.className = 'cpr-flash';
        f.textContent = text;
        f.style.color = color;
        void f.offsetWidth;
        f.classList.add(big ? 'big' : 'show');
    }

    // beat index nearest to time t, and the timing error in seconds
    function nearestBeat(t) {
        const iv = 60 / G.p.bpm;
        const k = Math.round((t - G.beatStart) / iv);
        return { k, err: t - (G.beatStart + k * iv) };
    }

    function press() {
        if (!G || G.done || G.phase !== 'compress' || G.t < G.beatStart - 0.3) return;
        const { k, err } = nearestBeat(G.t);
        if (k <= G.lastJudged) return; // one press per beat
        G.lastJudged = k;
        const a = Math.abs(err);
        const q = a <= G.p.perfect ? 'perfect' : a <= G.p.good ? 'good' : 'miss';
        G.samples.push(q === 'perfect' ? 1 : q === 'good' ? 0.75 : 0);
        G.count++;
        artifacts.push({ t0: waveT });
        $('beatCore').classList.add('hit');
        setTimeout(() => $('beatCore').classList.remove('hit'), 90);
        sfx.press(q);
        if (q === 'miss') { flash(err < 0 ? 'TOO EARLY' : 'TOO LATE', '#f87171'); shake(); }
        else if (q === 'perfect' && G.count % 5 === 0) flash('PERFECT', '#facc15');
        G.spo2 = Math.min(90, G.spo2 + (q === 'miss' ? 0 : 0.35));
        post('cprPress', { quality: q });
        hud();
        if (G.count >= G.p.compressions) setTimeout(() => G && showPhase('breath'), 350);
    }

    function shake() {
        const el = $('cpr');
        el.classList.remove('shake'); void el.offsetWidth; el.classList.add('shake');
    }

    function releaseBreath() {
        if (!G || G.phase !== 'breath' || G.lung <= 0.02) return;
        const l = G.lung;
        let q;
        if (l > 1.0) { q = 'over'; flash('TOO MUCH AIR', '#f87171'); sfx.miss(); shake(); G.samples.push(0); }
        else if (l >= 0.6 && l <= 0.85) { q = 'good'; flash('GOOD BREATH', '#38bdf8'); sfx.breathOk(); G.samples.push(1); G.spo2 = Math.min(92, G.spo2 + 3); }
        else { q = 'weak'; flash('NOT ENOUGH AIR', '#facc15'); G.samples.push(0.4); }
        G.breaths++;
        G.lung = 0;
        post('cprBreath', { quality: q });
        hud();
        if (G.breaths >= 2) setTimeout(endCycle, 600);
    }

    function endCycle() {
        if (!G || G.done) return;
        const total = G.p.cycles + G.extra;
        if (G.cycle < total) {
            G.cycle++;
            showPhase('compress');
            hud();
            return;
        }
        if (accuracy() >= G.p.pass) return revive();
        if (G.extra < G.p.maxExtra) { // one more try
            G.extra++;
            G.cycle++;
            flash('NO PULSE · KEEP GOING', '#f87171');
            showPhase('compress');
            hud();
            return;
        }
        fail();
    }

    function revive() {
        G.done = true;
        G.heart = rand(76, 92);
        $('monState').textContent = 'PULSE RESTORED';
        $('monState').classList.add('ok');
        flash('PULSE RESTORED!', '#4ade80', true);
        sfx.revive();
        post('cprDone', { success: true, accuracy: Math.round(accuracy() * 100) / 100, cycles: G.cycle });
        setTimeout(close, 3600);
    }

    function fail() {
        G.done = true;
        flash('NO PULSE', '#f87171', true);
        sfx.fail();
        post('cprDone', { success: false, accuracy: Math.round(accuracy() * 100) / 100, cycles: G.cycle });
        setTimeout(close, 3000);
    }

    // ── update / draw ──
    function update(dt) {
        G.t += dt;
        const iv = 60 / G.p.bpm;
        if (G.phase === 'compress' && G.t >= G.beatStart - 0.3) {
            // ring closes in on the core exactly on each beat
            const k = Math.max(0, (G.t - G.beatStart) / iv);
            const frac = k - Math.floor(k);
            const scale = 1 - 0.47 * frac; // 1 → 0.53 (the core's size) right on the beat
            $('beatRing').style.transform = `scale(${frac < 0.04 ? 0.53 : scale})`;
            $('beatRing').style.borderColor = frac > 0.85 || frac < 0.06 ? '#facc15' : 'rgba(255,255,255,0.85)';
            const beatIdx = Math.floor((G.t - G.beatStart) / iv);
            if (beatIdx !== G.tickIdx) { G.tickIdx = beatIdx; if (!G.done) sfx.tick(); }
            // a beat that went by without a press counts against the rhythm
            const { k: near } = nearestBeat(G.t);
            if (near - 1 > G.lastJudged && G.t - (G.beatStart + (near - 1) * iv) > G.p.good && near - 1 >= 0
                && G.count > 0 && G.count < G.p.compressions) {
                G.lastJudged = near - 1;
                G.samples.push(0);
                hud();
            }
            if (G.auto && !G.done) {
                const { k: kk, err } = nearestBeat(G.t + 0.012);
                if (kk > G.lastJudged && Math.abs(err) < 0.02) press();
            }
        }
        if (G.phase === 'breath' && !G.done) {
            const holding = G.auto ? (G.autoHold = (G.autoHold ?? rand(0.66, 0.8)), G.lung < G.autoHold) : keys.held;
            if (holding) {
                G.lung += dt * 0.62;
                if (G.lung > 1.08) releaseBreath(); // way too much: it lets go by itself
            } else if (G.auto && G.lung > 0) { releaseBreath(); G.autoHold = null; }
            $('lungFill').style.height = `${Math.min(100, G.lung * 100)}%`;
            $('lungFill').classList.toggle('over', G.lung > 1.0);
        }
        if (G.heart === 0 && G.t > G.alarmAt) { sfx.alarm(); G.alarmAt = G.t + 3.5; }
        if (G.heart > 0) {
            const period = 60 / G.heart;
            const beat = Math.floor(waveT / period);
            if (beat !== G.lastBeep) { G.lastBeep = beat; sfx.beep(); }
            $('monHr').textContent = Math.round(G.heart);
            G.spo2 = Math.min(97, G.spo2 + dt * 6);
            $('monSpo2').textContent = Math.round(G.spo2);
        }
    }

    function frame(t) {
        if (!G) { looping = false; return; }
        const dt = Math.max(0, Math.min(0.033, (t - last) / 1000));
        last = t;
        update(dt);
        if (!G) { looping = false; return; }
        drawEcg(dt);
        requestAnimationFrame(frame);
    }

    // ── input ──
    window.addEventListener('keydown', (e) => {
        if (!G || G.auto) return;
        if (e.code === 'Space' || e.code === 'KeyE') {
            e.preventDefault();
            if (e.repeat) return;
            if (G.phase === 'compress') press(); else keys.held = true;
        }
    });
    window.addEventListener('keyup', (e) => {
        if (e.code === 'Space' || e.code === 'KeyE') { keys.held = false; releaseBreath(); }
    });
    window.addEventListener('mousedown', () => { if (G && !G.auto) { if (G.phase === 'compress') press(); else keys.held = true; } });
    window.addEventListener('mouseup', () => { keys.held = false; releaseBreath(); });

    return { open, close, state: () => G };
})();

window.addEventListener('message', ({ data: m }) => {
    if (m.action === 'cpr') CPR.open(m.data);
    else if (m.action === 'closeCpr') CPR.close();
});

// ── Browser preview (outside FiveM): ?cpr[&play] ────────────────────────────
if (!inGame && location.search.includes('cpr')) {
    document.body.style.background = "linear-gradient(160deg, #c9a46a, #7d9fb0 55%, #2f6f8f)";
    setTimeout(() => CPR.open({ title: 'Unconscious swimmer', auto: !location.search.includes('play') }), 400);
}
