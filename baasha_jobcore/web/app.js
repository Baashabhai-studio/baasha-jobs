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
        <div class="job-item ${j.id === state.jobId && !state.view && !state.premiumId ? 'active' : ''}" data-job="${esc(j.id)}">
            <div class="job-icon"><i class="${esc(j.icon || 'fa-solid fa-briefcase')}"></i></div>
            <div>
                <div class="job-name">${esc(j.label)}</div>
                <div class="job-meta">Level ${j.level}${j.id === nearDepot ? ' · at depot' : ''}</div>
            </div>
            ${crew.jobId === j.id ? '<span class="dot" title="On shift"></span>' : ''}
        </div>`).join('') || '<div class="empty">No jobs installed.</div>';

    // Server poll: shown to everyone while an admin's poll runs
    const poll = state.data.poll;
    $('#pollBlock').classList.toggle('hidden', !(poll && poll.active));
    if (poll && poll.active) {
        $('#pollBlock').innerHTML = `
            <div class="job-item poll ${state.view === 'poll' ? 'active' : ''}" data-poll="1">
                <div class="job-icon"><i class="fa-solid fa-square-poll-vertical"></i></div>
                <div>
                    <div class="job-name">Server poll</div>
                    <div class="job-meta">${poll.myVote ? 'You voted · thanks!' : 'Your opinion counts'}</div>
                </div>
                ${poll.myVote ? '' : '<span class="dot" style="background:var(--gold)"></span>'}
            </div>`;
    }

    // Premium jobs: only in the data for admins (the server decides), never for players
    const premium = state.data.premium || [];
    $('#premiumBlock').classList.toggle('hidden', premium.length === 0);
    $('#premiumList').innerHTML = premium.map((p) => `
        <div class="job-item premium ${state.premiumId === p.id ? 'active' : ''}" data-premium="${esc(p.id)}">
            <div class="job-icon"><i class="${esc(p.icon)}"></i></div>
            <div>
                <div class="job-name">${esc(p.label)}</div>
                <div class="job-meta">${p.status === 'soon' ? 'Coming soon' : esc(p.price || 'Premium')}</div>
            </div>
            <i class="fa-solid fa-lock lock"></i>
        </div>`).join('');

    document.querySelectorAll('.job-item').forEach((el) => el.onclick = () => {
        if (el.dataset.poll) { state.view = 'poll'; state.premiumId = null; }
        else if (el.dataset.premium) { state.premiumId = el.dataset.premium; state.view = null; state.tab = 'overview'; }
        else { state.jobId = el.dataset.job; state.premiumId = null; state.view = null; }
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

function openUrl(url) {
    if (!url) return;
    if (inGame && window.invokeNative) window.invokeNative('openUrl', url); // opens in the player's own browser
    else window.open(url, '_blank');
}

function renderPremium(p) {
    const soon = p.status === 'soon';
    const features = (p.features || []).map((f) => `<div class="pfeat"><i class="fa-solid fa-check"></i><span>${esc(f)}</span></div>`).join('');
    return `
        <div class="padmin">
            <i class="fa-solid fa-user-shield"></i>
            <div><b>Only admins can see this.</b> Your players don't see this card, the price or the store link.
            They only see something if you start a player poll below.</div>
        </div>
        <div class="hero">
            <div class="hero-icon premium"><i class="${esc(p.icon)}"></i></div>
            <div>
                <h1>${esc(p.label)} <span class="pbadge"><i class="fa-solid fa-crown"></i> PREMIUM</span></h1>
                <p>${esc(p.tagline || p.description)}</p>
            </div>
        </div>
        ${p.image ? `<div class="pimage" style="background-image:url('${esc(p.image)}')"></div>` : ''}
        <div class="two">
            <div class="box"><h3>What you get</h3>${features || `<p class="hint" style="text-align:left">${esc(p.description)}</p>`}</div>
            <div class="box">
                <h3>${soon ? 'Coming soon' : 'Get it'}</h3>
                <div class="pprice">${soon ? 'SOON' : esc(p.price || '')}</div>
                <p class="hint" style="text-align:left;margin:0 0 14px">Plugs straight into this Job Center: levels, crews, leaderboard and the tablet just work. ESX, QBCore &amp; Qbox.</p>
                ${p.url ? `<button class="btn btn-gold" data-url="${esc(p.url)}"><i class="fa-solid fa-arrow-up-right-from-square"></i> ${soon ? 'Follow the release' : 'Open store page'}</button>` : ''}
                ${p.video ? `<button class="btn btn-ghost" data-url="${esc(p.video)}" style="margin-top:8px"><i class="fa-brands fa-youtube"></i> Watch the video</button>` : ''}
            </div>
        </div>
        ${state.data.pollsAllowed ? renderPollAdmin(p) : ''}
        <div class="phide">
            <button class="btn btn-ghost" id="hidePremium"><i class="fa-solid fa-eye-slash"></i> Hide premium jobs</button>
            <span>Hides this card for every admin on the server. Bring it back with <b>/jobspremium on</b>, or turn it off for good with <b>Config.PremiumJobs.enabled = false</b>.</span>
        </div>`;
}

const fmtLeft = (s) => s >= 86400 ? `${Math.ceil(s / 86400)} day${s >= 172800 ? 's' : ''}` : s >= 3600 ? `${Math.ceil(s / 3600)} h` : `${Math.max(1, Math.ceil(s / 60))} min`;

function results(poll) {
    const total = poll.yes + poll.no;
    const pct = total ? Math.round((poll.yes / total) * 100) : 0;
    return `
        <div class="presult">
            <div class="presult-row"><span><b>${poll.yes}</b> Yes</span><span>${pct}%</span><span><b>${poll.no}</b> No</span></div>
            <div class="presult-bar"><div style="width:${pct}%"></div></div>
            <div class="hint" style="text-align:left">${total} vote${total === 1 ? '' : 's'}</div>
        </div>`;
}

// Admin: read what a poll does, then decide. Nothing reaches players until "Start".
function renderPollAdmin(p) {
    const poll = state.data.poll;
    if (poll && poll.job.id === p.id) {
        return `
            <div class="box ppoll">
                <h3><i class="fa-solid fa-square-poll-vertical"></i> Player poll ${poll.active ? `· ends in ${fmtLeft(poll.endsIn)}` : '· ended'}</h3>
                ${results(poll)}
                ${poll.active
                    ? '<button class="btn btn-ghost" data-premium-act="end"><i class="fa-solid fa-stop"></i> End the poll now</button>'
                    : '<button class="btn btn-ghost" data-premium-act="clear"><i class="fa-solid fa-broom"></i> Clear the results</button>'}
            </div>`;
    }
    if (poll && poll.active) {
        return `<div class="box ppoll"><h3><i class="fa-solid fa-square-poll-vertical"></i> Player poll</h3>
            <p class="hint" style="text-align:left;margin:0">A poll about <b>${esc(poll.job.label)}</b> is running. One poll at a time.</p></div>`;
    }
    return `
        <div class="box ppoll">
            <h3><i class="fa-solid fa-square-poll-vertical"></i> Ask your players (optional)</h3>
            <p class="pintro">Not sure if your players would like this job? Ask them. <b>Until you press start, players see nothing.</b></p>
            <div class="pinfo">
                <div><i class="fa-solid fa-eye"></i><span>Players see a <b>Server poll</b> card in the Job Center: this job, its video and <b>Yes / No</b>. No price, no store link.</span></div>
                <div><i class="fa-solid fa-bell"></i><span>Everyone online gets <b>one</b> small notification when you start it. Players who join later get one reminder.</span></div>
                <div><i class="fa-solid fa-user-check"></i><span>One vote per character. They can change it while the poll runs.</span></div>
                <div><i class="fa-solid fa-chart-simple"></i><span>Results show here, live. Only admins see the numbers before voting.</span></div>
                <div><i class="fa-solid fa-lock"></i><span>Votes stay on <b>your server</b>. Nothing is sent to Baasha Bhai Studio or anyone else.</span></div>
                <div><i class="fa-solid fa-hourglass-end"></i><span>It ends by itself after the time you pick, or end it any time here.</span></div>
            </div>
            <div class="pstart">
                <select id="pollDays">
                    <option value="1">1 day</option>
                    <option value="3" selected>3 days</option>
                    <option value="7">7 days</option>
                </select>
                <button class="btn btn-gold" id="pollStart"><i class="fa-solid fa-play"></i> Ask my players</button>
            </div>
        </div>`;
}

// Player: the poll card (no price, no link)
function youtubeEmbed(url) {
    const m = String(url || '').match(/(?:youtu\.be\/|v=|\/embed\/|\/shorts\/)([\w-]{11})/);
    return m ? `https://www.youtube-nocookie.com/embed/${m[1]}?rel=0&modestbranding=1` : null;
}

function renderPoll(poll) {
    const j = poll.job;
    const embed = youtubeEmbed(j.video);
    const media = embed ? `<div class="pvideo"><iframe src="${esc(embed)}" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></div>`
        : j.image ? `<div class="pimage" style="background-image:url('${esc(j.image)}')"></div>` : '';
    const features = (j.features || []).map((f) => `<div class="pfeat"><i class="fa-solid fa-check"></i><span>${esc(f)}</span></div>`).join('');
    const btn = (choice, icon, label) => `<button class="btn ${poll.myVote === choice ? 'btn-gold' : 'btn-ghost'}" data-vote="${choice}"><i class="fa-solid ${icon}"></i> ${label}</button>`;
    return `
        <div class="hero">
            <div class="hero-icon"><i class="fa-solid fa-square-poll-vertical"></i></div>
            <div>
                <div class="pkicker">YOUR SERVER WANTS TO KNOW</div>
                <h1>Would you like a ${esc(j.label)} job?</h1>
                <p>${esc(j.tagline || j.description)}</p>
            </div>
        </div>
        ${media}
        <div class="two">
            <div class="box"><h3>The job</h3>${features || `<p class="hint" style="text-align:left">${esc(j.description)}</p>`}</div>
            <div class="box">
                <h3>Your vote</h3>
                <div class="pvote">${btn('yes', 'fa-thumbs-up', 'Yes, add it')}${btn('no', 'fa-thumbs-down', 'No thanks')}</div>
                ${poll.myVote ? results(poll) + '<div class="hint" style="text-align:left">You can change your vote until the poll ends.</div>' : ''}
                <div class="hint" style="text-align:left">Ends in ${fmtLeft(poll.endsIn)} · asked by this server's staff</div>
            </div>
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

    const premium = state.premiumId && (state.data.premium || []).find((p) => p.id === state.premiumId);
    document.querySelector('.tabs').style.visibility = premium ? 'hidden' : ''; // keeps the close button in place
    const poll = state.view === 'poll' && state.data.poll && state.data.poll.active ? state.data.poll : null;
    if (poll) {
        document.querySelector('.tabs').style.visibility = 'hidden';
        $('#view').innerHTML = renderPoll(poll);
        document.querySelectorAll('[data-vote]').forEach((b) => b.onclick = () => post('pollVote', { choice: b.dataset.vote }));
        return;
    }
    if (premium) {
        $('#view').innerHTML = renderPremium(premium);
        document.querySelectorAll('[data-url]').forEach((b) => b.onclick = () => openUrl(b.dataset.url));
        document.querySelectorAll('[data-premium-act]').forEach((b) => b.onclick = () => post('premium', { action: b.dataset.premiumAct }));
        const start = $('#pollStart');
        if (start) start.onclick = () => {
            // second click confirms: nothing reaches players before that
            if (!start.dataset.sure) {
                start.dataset.sure = '1';
                start.innerHTML = '<i class="fa-solid fa-check"></i> Confirm: show it to players';
                start.classList.add('btn-green');
                return;
            }
            post('premium', { action: 'start', jobId: premium.id, days: Number($('#pollDays').value) });
        };
        const hide = $('#hidePremium');
        if (hide) hide.onclick = () => {
            if (!hide.dataset.sure) { hide.dataset.sure = '1'; hide.innerHTML = '<i class="fa-solid fa-check"></i> Click again to hide'; return; }
            state.premiumId = null;
            post('premium', { action: 'hide' });
        };
        return;
    }

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
        state.premiumId = null;
        state.view = null;
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
            // ?player = what a normal player gets (no premium list)
            pollsAllowed: true,
            poll: location.search.includes('poll') ? {
                active: true, endsIn: 2 * 86400 + 3000, yes: 23, no: 4, myVote: location.search.includes('voted') ? 'yes' : null,
                job: { id: 'lifeguard', label: 'Lifeguard', tagline: 'Keep Vespucci Beach safe: tower watch, water rescues, CPR, first aid and shark alerts.',
                       features: ['Binoculars tower-watch minigame', 'Jet ski and swim rescues', 'CPR minigame with heart monitor', 'Jellyfish first aid, shark alerts'],
                       video: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ' },
            } : null,
            premium: location.search.includes('player') ? null : [{
                id: 'lifeguard', label: 'Lifeguard', icon: 'fa-solid fa-life-ring', status: 'available', price: '€24.99',
                tagline: 'Keep Vespucci Beach safe: tower watch, water rescues, CPR, first aid and shark alerts.',
                features: ['Binoculars tower-watch minigame', 'Jet ski and swim rescues', 'CPR minigame with heart monitor', 'Jellyfish first aid, shark alerts'],
                url: 'https://www.baashabhai.com/scripts', video: null,
            }],
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
