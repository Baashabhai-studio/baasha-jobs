const inGame = typeof GetParentResourceName === 'function';
const resource = inGame ? GetParentResourceName() : 'baasha_lifeguard';
const $ = (id) => document.getElementById(id);

let post = function (name, body = {}) {
    if (!inGame) { console.log('[post]', name, body); return Promise.resolve({}); }
    return fetch(`https://${resource}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(body),
    }).then((r) => r.json()).catch(() => ({}));
};

// ── Sounds (tiny WebAudio) ───────────────────────────────────────────────
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
function thump(vol = 0.25) { tone(90, 0.14, 'sine', vol, -40); }

const sfx = {
    tick: () => tone(1800, 0.03, 'square', 0.015),
    press: (q) => { thump(q === 'miss' ? 0.12 : 0.25); if (q === 'perfect') tone(1320, 0.06, 'sine', 0.03); },
    miss: () => tone(200, 0.18, 'sawtooth', 0.035, -60),
    alarm: () => { tone(960, 0.12, 'square', 0.025); setTimeout(() => tone(960, 0.12, 'square', 0.025), 180); },
    beep: () => tone(1046, 0.08, 'sine', 0.05),
    breathOk: () => tone(520, 0.25, 'sine', 0.05, 200),
    revive: () => [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => tone(f, 0.2, 'triangle', 0.06), i * 110)),
    fail: () => tone(440, 1.4, 'sine', 0.05),
    // lifeguard whistle: two shrill trilled blasts
    whistle: () => {
        const ac = audio(); if (!ac) return;
        [0, 0.55].forEach((at, i) => {
            const o = ac.createOscillator(), lfo = ac.createOscillator(), lg = ac.createGain(), g = ac.createGain();
            const t0 = ac.currentTime + at, len = i ? 0.9 : 0.4;
            o.type = 'sine'; o.frequency.value = 2900;
            lfo.frequency.value = 38; lg.gain.value = 140; // the pea rattling inside
            lfo.connect(lg).connect(o.frequency);
            g.gain.setValueAtTime(0.0001, t0);
            g.gain.exponentialRampToValueAtTime(0.09, t0 + 0.03);
            g.gain.setValueAtTime(0.09, t0 + len - 0.06);
            g.gain.exponentialRampToValueAtTime(0.0001, t0 + len);
            o.connect(g).connect(ac.destination);
            o.start(t0); lfo.start(t0); o.stop(t0 + len); lfo.stop(t0 + len);
        });
    },
    spot: () => [880, 1320].forEach((f, i) => setTimeout(() => tone(f, 0.16, 'triangle', 0.06), i * 120)),
    buzz: () => tone(140, 0.3, 'square', 0.04, -40),
    radio: () => { tone(1400, 0.07, 'square', 0.03); setTimeout(() => tone(1800, 0.09, 'square', 0.03), 110); },
};

// ── Call card (top right): what's going on, where, how long is left ──────
const CallCard = (() => {
    let left = 0, timer = null;
    const fmt = (s) => `${Math.floor(Math.max(0, s) / 60)}:${String(Math.max(0, s) % 60).padStart(2, '0')}`;
    const stageText = { open: 'GET THERE', rescuing: 'BRING THEM TO A TOWER', cpr: 'CPR IN PROGRESS', treat: 'FIRST AID', alarm: 'CLEARING THE WATER' };
    function show(d) {
        clearInterval(timer);
        const el = $('callCard');
        if (!d) { el.classList.add('off'); return; }
        el.className = `call ${d.type}`;
        $('callIcon').className = d.icon || 'fa-solid fa-life-ring';
        $('callTitle').textContent = d.label;
        $('callWhere').textContent = d.where;
        $('callSpotted').classList.toggle('off', !d.spotted);
        $('callStage').textContent = stageText.open;
        left = d.left;
        $('callTimer').textContent = fmt(left);
        $('callDist').textContent = '';
        timer = setInterval(() => { left = Math.max(0, left - 1); $('callTimer').textContent = fmt(left); }, 1000);
        sfx.radio();
    }
    function result(r) {
        clearInterval(timer);
        const el = $('callCard');
        if (!r) { el.classList.add('off'); return; }
        el.classList.remove('off');
        el.classList.add(r.ok ? 'done' : 'failed');
        $('callStage').textContent = r.ok ? 'COMPLETE' : 'CALL CLOSED';
        $('callTimer').textContent = r.pay ? `+$${r.pay}` : '';
        $('callDist').textContent = r.xp ? `+${r.xp} XP` : '';
        setTimeout(() => el.classList.add('off'), 4500);
    }
    window.addEventListener('message', ({ data: m }) => {
        if (m.action === 'callCard') show(m.data);
        else if (m.action === 'callTick') { left = m.left; $('callTimer').textContent = fmt(left); $('callDist').textContent = `${m.dist} m`; }
        else if (m.action === 'callStage') $('callStage').textContent = stageText[m.stage] || '';
        else if (m.action === 'callResult') result(m.data);
        else if (m.action === 'whistle') sfx.whistle();
    });
    return { show, result };
})();

// Browser preview: ?call
if (!inGame && location.search.includes('call')) {
    document.body.style.background = 'linear-gradient(160deg, #c9a46a, #7d9fb0 55%, #2f6f8f)';
    setTimeout(() => CallCard.show({ type: 'drowning', label: 'Drowning swimmer', icon: 'fa-solid fa-person-swimming', where: 'Tower 3', left: 205, spotted: true }), 300);
}
