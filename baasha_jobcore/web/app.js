const inGame = typeof GetParentResourceName === 'function';
const resource = inGame ? GetParentResourceName() : 'baasha_jobcore';

const state = { data: null, jobId: null, tab: 'overview' };
const $ = (sel) => document.querySelector(sel);

function post(name, body = {}) {
    if (!inGame) return Promise.resolve(mockPost(name, body));
    return fetch(`https://${resource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body),
    }).then((r) => r.json()).catch(() => ({}));
}

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const money = (n) => '$' + Number(n || 0).toLocaleString('en-US');
const currentJob = () => state.data?.jobs.find((j) => j.id === state.jobId);
const isLeader = () => state.data && state.data.crew.leader === state.data.me;

// ── Render ──────────────────────────────────────────────────────────────
function renderSidebar() {
    const { jobs, crew, nearDepot } = state.data;
    $('#jobList').innerHTML = jobs.map((j) => `
        <div class="job-item ${j.id === state.jobId ? 'active' : ''}" data-job="${esc(j.id)}">
            <div class="job-icon"><i class="${esc(j.icon || 'fa-solid fa-briefcase')}"></i></div>
            <div>
                <div class="job-name">${esc(j.label)}</div>
                <div class="job-meta">Level ${j.level}${j.id === nearDepot ? ' · at depot' : ''}</div>
            </div>
            ${crew.jobId === j.id ? '<span class="dot" title="On shift"></span>' : ''}
        </div>`).join('') || '<div class="empty">No jobs installed.</div>';

    document.querySelectorAll('.job-item').forEach((el) => el.onclick = () => {
        state.jobId = el.dataset.job;
        render();
    });

    const onShift = crew.jobId ? state.data.jobs.find((j) => j.id === crew.jobId) : null;
    $('#crewMini').innerHTML = `
        <div>Crew: <b>${crew.members.length}/${crew.max}</b>${isLeader() ? ' · leader' : ''}</div>
        <div style="margin-top:4px">${onShift ? `On shift: <b style="color:var(--green)">${esc(onShift.label)}</b>` : 'Not on shift'}</div>`;
}

function renderOverview(job) {
    const { crew, nearDepot, maxLevel } = state.data;
    const range = job.levelTo ? job.levelTo - job.levelFrom : 1;
    const pct = job.levelTo ? Math.min(100, ((job.xp - job.levelFrom) / range) * 100) : 100;
    const onThisShift = crew.jobId === job.id;
    const onOtherShift = crew.jobId && !onThisShift;
    const tooBig = crew.members.length > job.maxCrew;

    let action;
    if (onThisShift) {
        action = isLeader()
            ? `<button class="btn btn-red" id="endBtn"><i class="fa-solid fa-flag-checkered"></i> End Shift</button>
               <div class="hint">Bring the work vehicle back to the depot to get your deposit back.</div>`
            : `<div class="hint">You're on shift. Only the crew leader can end it.</div>`;
    } else {
        let reason = '';
        if (onOtherShift) reason = 'Your crew is already on another shift.';
        else if (!isLeader()) reason = 'Only the crew leader can start a shift.';
        else if (tooBig) reason = `This job allows up to ${job.maxCrew} crew members.`;
        else if (nearDepot !== job.id) reason = 'Go to the depot (see map blip) to start this job.';
        action = `
            <div class="deposit"><span>Vehicle deposit</span><b>${job.deposit > 0 ? money(job.deposit) : 'None'}</b></div>
            <button class="btn btn-gold" id="startBtn" ${reason ? 'disabled' : ''}><i class="fa-solid fa-play"></i> Start Shift</button>
            ${reason ? `<div class="hint">${esc(reason)}</div>` : ''}`;
    }

    const perks = (job.perks || []).map((p) => `
        <div class="perk ${job.level >= p.level ? 'unlocked' : ''}">
            <span class="lv">LV ${p.level}</span><span>${esc(p.text)}</span>
        </div>`).join('');

    return `
        <div class="hero">
            <div class="hero-icon"><i class="${esc(job.icon || 'fa-solid fa-briefcase')}"></i></div>
            <div><h1>${esc(job.label)}</h1><p>${esc(job.description || '')}</p></div>
        </div>
        <div class="level-card">
            <div class="level-row">
                <div class="level-big">LEVEL <span>${job.level}</span><small style="color:var(--muted);font-size:14px"> / ${maxLevel}</small></div>
                <div class="level-xp">${job.levelTo ? `${job.xp - job.levelFrom} / ${range} XP` : 'MAX LEVEL'}</div>
            </div>
            <div class="bar"><div style="width:${pct}%"></div></div>
        </div>
        <div class="stats">
            <div class="stat"><div class="k">Total earned</div><div class="v">${money(job.totalEarned)}</div></div>
            <div class="stat"><div class="k">Shifts</div><div class="v">${job.shifts}</div></div>
            <div class="stat"><div class="k">Tasks done</div><div class="v">${job.tasks}</div></div>
            <div class="stat"><div class="k">Max crew</div><div class="v">${job.maxCrew}</div></div>
        </div>
        <div class="two">
            <div class="box"><h3>Level perks</h3>${perks || '<div class="perk">No perks configured.</div>'}</div>
            <div class="box"><h3>Shift</h3>${action}</div>
        </div>`;
}

function renderCrew() {
    const { crew, me } = state.data;
    const leader = isLeader();
    const members = crew.members.map((m) => `
        <div class="member">
            <div class="avatar">${esc(m.name.charAt(0))}</div>
            <div>
                <div class="name">${esc(m.name)}${m.id === me ? ' (you)' : ''}</div>
                <div class="role">${m.id === crew.leader ? 'Crew leader' : 'Member'} · ID ${m.id}</div>
            </div>
            ${leader && m.id !== me ? `<button class="kick" data-kick="${m.id}" title="Remove"><i class="fa-solid fa-user-minus"></i></button>` : ''}
        </div>`).join('');
    const empty = Array.from({ length: Math.max(0, crew.max - crew.members.length) }, () => '<div class="slot">Empty slot</div>').join('');

    return `
        <div class="two">
            <div class="box">
                <h3>Your crew</h3>
                ${members}${empty}
                ${crew.members.length > 1 ? '<button class="btn btn-ghost" id="leaveBtn" style="margin-top:6px"><i class="fa-solid fa-right-from-bracket"></i> Leave crew</button>' : ''}
            </div>
            <div class="box">
                <h3>Invite a worker</h3>
                <p class="hint" style="text-align:left;margin:0">Work together to finish routes faster. Crews share pay with a bonus of up to +20%, and everyone earns XP.</p>
                ${leader && !crew.jobId ? `
                <div class="invite">
                    <input id="inviteId" type="number" placeholder="Player ID (nearby)">
                    <button class="btn btn-gold" id="inviteBtn"><i class="fa-solid fa-user-plus"></i></button>
                </div>` : `<p class="hint" style="text-align:left">${crew.jobId ? 'You can\'t invite while on a shift.' : 'Only the crew leader can invite.'}</p>`}
            </div>
        </div>`;
}

function renderLeaderboard(job) {
    $('#view').innerHTML = `<div class="box"><h3>${esc(job.label)} · top earners this week</h3><div class="empty">Loading…</div></div>`;
    post('leaderboard', { jobId: job.id }).then((rows) => {
        if (state.tab !== 'leaderboard' || state.jobId !== job.id) return;
        const body = (rows || []).map((r, i) => `
            <tr><td class="rank">#${i + 1}</td><td>${esc(r.name || 'Unknown')}</td><td>Lv.${r.level}</td><td class="money">${money(r.weekly_earned)}</td></tr>`).join('');
        $('#view').innerHTML = `
            <div class="box"><h3>${esc(job.label)} · top earners this week</h3>
            ${body ? `<table><thead><tr><th>Rank</th><th>Worker</th><th>Level</th><th style="text-align:right">Earned</th></tr></thead><tbody>${body}</tbody></table>`
                   : '<div class="empty">Nobody has worked this week yet. Be the first!</div>'}
            </div>`;
    });
}

function render() {
    if (!state.data) return;
    if (!state.data.jobs.find((j) => j.id === state.jobId)) state.jobId = state.data.jobs[0]?.id;
    renderSidebar();
    document.querySelectorAll('.tab').forEach((t) => t.classList.toggle('active', t.dataset.tab === state.tab));

    const job = currentJob();
    if (!job && state.tab !== 'crew') { $('#view').innerHTML = '<div class="empty">No jobs installed yet.</div>'; return; }

    if (state.tab === 'leaderboard') return renderLeaderboard(job);
    $('#view').innerHTML = state.tab === 'crew' ? renderCrew() : renderOverview(job);
    bindView();
}

function bindView() {
    const start = $('#startBtn');
    if (start) start.onclick = () => { start.disabled = true; post('startShift', { jobId: state.jobId }).then(() => { start.disabled = false; }); };
    const end = $('#endBtn');
    if (end) end.onclick = () => post('endShift');
    const leave = $('#leaveBtn');
    if (leave) leave.onclick = () => post('leave');
    const invite = $('#inviteBtn');
    if (invite) invite.onclick = () => {
        const id = parseInt($('#inviteId').value, 10);
        if (id) post('invite', { id }).then(() => { $('#inviteId').value = ''; });
    };
    document.querySelectorAll('[data-kick]').forEach((b) => b.onclick = () => post('kick', { id: parseInt(b.dataset.kick, 10) }));
}

// ── Events ──────────────────────────────────────────────────────────────
document.querySelectorAll('.tab').forEach((t) => t.onclick = () => { state.tab = t.dataset.tab; render(); });
$('#closeBtn').onclick = () => post('close');
document.addEventListener('keyup', (e) => { if (e.key === 'Escape') post('close'); });

window.addEventListener('message', ({ data: msg }) => {
    if (msg.action === 'open') {
        state.data = msg.data;
        state.jobId = msg.focus || msg.data.crew.jobId || msg.data.nearDepot || state.jobId;
        state.tab = 'overview';
        $('#tablet').classList.remove('hidden');
        render();
    } else if (msg.action === 'update') {
        state.data = msg.data;
        if (state.tab !== 'leaderboard') render();
    } else if (msg.action === 'close') {
        $('#tablet').classList.add('hidden');
    } else if (msg.action === 'paid' && state.data) {
        const job = state.data.jobs.find((j) => j.id === msg.jobId);
        if (job) Object.assign(job, { level: msg.level, xp: msg.xp, levelFrom: msg.from, levelTo: msg.to });
        if (!$('#tablet').classList.contains('hidden') && state.tab === 'overview') render();
    }
});

// ── Browser preview (outside FiveM) ─────────────────────────────────────
function mockPost(name) {
    if (name === 'leaderboard') return [
        { name: 'Tony Baasha', weekly_earned: 18420, level: 7 },
        { name: 'Ali Khan', weekly_earned: 12950, level: 5 },
        { name: 'Sara Lee', weekly_earned: 8310, level: 4 },
    ];
    return { ok: true };
}

if (!inGame) {
    document.body.style.background = '#2a2d33';
    window.postMessage({
        action: 'open',
        focus: 'garbage',
        data: {
            me: 1, nearDepot: 'garbage', maxLevel: 10,
            crew: { leader: 1, max: 4, jobId: null, members: [{ id: 1, name: 'Baasha Bhai' }, { id: 7, name: 'Ali Khan' }] },
            jobs: [
                {
                    id: 'garbage', label: 'Garbage Collector', icon: 'fa-solid fa-trash-can', maxCrew: 4, deposit: 250,
                    description: 'Run city routes in a garbage truck: collect bags, run the compactor and bring the truck home. Find recyclables on the way.',
                    level: 3, xp: 1650, levelFrom: 1200, levelTo: 2200, totalEarned: 48210, shifts: 23, tasks: 612,
                    perks: [{ level: 1, text: '4-stop routes' }, { level: 3, text: '6-stop routes, more recyclables' }, { level: 5, text: '8-stop routes' }, { level: 8, text: 'Rare finds in bins' }],
                },
                { id: 'delivery', label: 'Delivery Driver', icon: 'fa-solid fa-box', maxCrew: 2, deposit: 150, description: 'Deliver packages around the city.', level: 1, xp: 0, levelFrom: 0, levelTo: 500, totalEarned: 0, shifts: 0, tasks: 0, perks: [] },
            ],
        },
    }, '*');
}
