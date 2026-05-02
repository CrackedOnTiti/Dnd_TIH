let ws = null;
let me = null;
let allPlayers = [];      // full player data from /api/host/players
let selectedCharId = null;
let hostDie = 20;
let pendingRequests = [];
let currentRequestIndex = 0;
let constraintTarget = null; // { character_id, is_host }
let chatTarget = null;       // character_id currently chatting with (null = no one)
let chatLogs = {};           // character_id -> array of {sender, content, mode}
let onlineCharIds = new Set();

// ── Init ──────────────────────────────────────────────────────────────────────

async function init() {
  const r = await fetch('/api/me');
  if (!r.ok) { window.location.href = '/index.html'; return; }
  me = await r.json();
  if (me.role !== 'host') { window.location.href = '/player.html'; return; }

  await loadPlayers();
  await loadPendingRequests();
  connectWs();
}

async function loadPlayers() {
  const r = await fetch('/api/host/players');
  allPlayers = await r.json();
  renderPlayerList();
  renderLiveRolls();
}

async function loadPendingRequests() {
  const r = await fetch('/api/host/change_requests');
  pendingRequests = await r.json();
  updatePendingBadge();
}

// ── WebSocket ─────────────────────────────────────────────────────────────────

function connectWs() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);

  ws.onopen = () => {
    const el = document.getElementById('ws-status');
    if (el) { el.textContent = 'WS: connecte'; el.style.color = 'var(--green)'; }
  };

  ws.onmessage = e => {
    const msg = JSON.parse(e.data);
    handleWsMessage(msg);
  };

  ws.onerror = err => {
    console.error('WS error', err);
    const el = document.getElementById('ws-status');
    if (el) { el.textContent = 'WS: erreur'; el.style.color = 'var(--red)'; }
  };

  ws.onclose = () => {
    const el = document.getElementById('ws-status');
    if (el) { el.textContent = 'WS: deconnecte'; el.style.color = 'var(--red)'; }
    setTimeout(connectWs, 3000);
  };
}

function send(type, data) {
  if (ws && ws.readyState === 1) {
    ws.send(JSON.stringify({ type, data }));
  }
}

function handleWsMessage(msg) {
  switch (msg.type) {

    case 'player_rolled': {
      const p = findPlayer(msg.data.character_id);
      if (p) {
        p.character.last_roll = msg.data.result;
        updatePlayerCardStats(p.character);
        const liveEl = document.getElementById(`roll-live-${msg.data.character_id}`);
        if (liveEl) { liveEl.textContent = msg.data.result; flash_roll(liveEl); }
      }
      break;
    }

    case 'stat_updated': {
      const p = findPlayer(msg.data.character_id);
      if (p) {
        Object.assign(p.character, msg.data);
        updatePlayerCardStats(p.character);
        if (selectedCharId === msg.data.character_id) {
          refreshStatBars(msg.data);
        }
      }
      break;
    }

    case 'message_received': {
      const cid = msg.data.character_id;
      if (!chatLogs[cid]) chatLogs[cid] = [];
      chatLogs[cid].push({ sender: msg.data.sender === 'host' ? 'Vous' : (msg.data.player_name || 'Joueur'), content: msg.data.content, mode: msg.data.mode });
      if (chatTarget === cid) {
        append_chat(document.getElementById('chat-host-log'), msg.data.sender === 'host' ? 'Vous' : (msg.data.player_name || 'Joueur'), msg.data.content, msg.data.mode);
      } else if (msg.data.sender === 'player') {
        markUnread(cid, true);
      }
      break;
    }

    case 'inventory_updated': {
      const p = findPlayer(msg.data.character_id);
      if (p) {
        p.inventory = msg.data.items;
        if (selectedCharId === msg.data.character_id) renderDetailInventory(msg.data.items);
      }
      break;
    }

    case 'money_updated': {
      const p = findPlayer(msg.data.character_id);
      if (p) {
        p.character.copper = msg.data.copper;
        updatePlayerCardStats(p.character);
        if (selectedCharId === msg.data.character_id) {
          render_money(msg.data.copper, document.getElementById('detail-money'));
        }
      }
      break;
    }

    case 'profile_updated': {
      const p = findPlayer(msg.data.id);
      if (p) {
        p.character = { ...p.character, ...msg.data };
        updatePlayerCardStats(p.character);
        if (selectedCharId === msg.data.id) renderDetail(selectedCharId);
      }
      break;
    }

    case 'abilities_updated': {
      // find which player this is by checking abilities
      // We don't have the character_id here; abilities are updated per character
      // Re-fetch all players to stay in sync
      loadPlayers();
      break;
    }

    case 'host_rolled': {
      const el = document.getElementById('host-roll-result');
      el.textContent = msg.data.result;
      flash_roll(el);
      break;
    }

    case 'character_created': {
      allPlayers.push(msg.data);
      renderPlayerList();
      renderLiveRolls();
      break;
    }

    case 'player_online': {
      onlineCharIds.add(msg.data.character_id);
      const card = document.getElementById(`pcard-${msg.data.character_id}`);
      if (card) {
        card.style.borderLeftColor = 'var(--green)';
        card.style.borderLeftWidth = '3px';
      }
      break;
    }

    case 'player_offline': {
      onlineCharIds.delete(msg.data.character_id);
      const card = document.getElementById(`pcard-${msg.data.character_id}`);
      if (card) {
        card.style.borderLeftColor = '';
        card.style.borderLeftWidth = '';
      }
      break;
    }

    case 'change_request_received': {
      pendingRequests.push(msg.data);
      updatePendingBadge();
      break;
    }

    case 'money_transfer_done': {
      const pf = findPlayer(msg.data.from_id);
      const pt = findPlayer(msg.data.to_id);
      if (pf) { pf.character.copper = msg.data.from_copper; updatePlayerCardStats(pf.character); }
      if (pt) { pt.character.copper = msg.data.to_copper; updatePlayerCardStats(pt.character); }
      if (selectedCharId === msg.data.from_id || selectedCharId === msg.data.to_id) {
        const p = findPlayer(selectedCharId);
        if (p) render_money(p.character.copper, document.getElementById('detail-money'));
      }
      break;
    }

    case 'special_updated': {
      const p = findPlayer(msg.data.character_id);
      if (p) {
        if (!p.specials) p.specials = [];
        const spec = p.specials.find(s => s.key === msg.data.key);
        if (spec) spec.value = msg.data.value;
        const el = document.getElementById(`host-special-val-${msg.data.key}-${msg.data.character_id}`);
        if (el) el.textContent = msg.data.value;
      }
      break;
    }
  }
}

// ── Player list (left column) ─────────────────────────────────────────────────

function renderPlayerList() {
  const list = document.getElementById('player-list');
  list.innerHTML = '';
  allPlayers.forEach(p => {
    const c = p.character;
    const card = document.createElement('div');
    card.className = `player-card ${selectedCharId === c.id ? 'selected' : ''}`;
    card.id = `pcard-${c.id}`;
    card.onclick = () => selectPlayer(c.id);
    card.innerHTML = `
      <div class="pc-name">
        <span>${escape_html(c.name)}</span>
        <span class="unread-dot hidden" id="unread-${c.id}"></span>
        <button class="small" style="margin-left:auto; padding:0 0.4rem; font-size:11px; flex-shrink:0"
          onclick="event.stopPropagation(); openProfileEdit(${c.id})">&#9998;</button>
      </div>
      <div class="pc-stats">
        HP ${c.curr_hp}/${c.max_hp} &bull; STM ${c.curr_stam}/${c.max_stam} &bull; ${copper_label(c.copper)}
      </div>
    `;
    if (onlineCharIds.has(c.id)) {
      card.style.borderLeftColor = 'var(--green)';
      card.style.borderLeftWidth = '3px';
    }
    list.appendChild(card);
  });
}

function updatePlayerCardStats(c) {
  const stats = document.querySelector(`#pcard-${c.id} .pc-stats`);
  if (stats) stats.innerHTML = `HP ${c.curr_hp}/${c.max_hp} &bull; STM ${c.curr_stam}/${c.max_stam} &bull; ${copper_label(c.copper)}`;
}

function copper_label(copper) {
  const m = copper_to_money(copper);
  if (m.plat > 0) return `${m.plat}P ${m.gold}G`;
  if (m.gold > 0) return `${m.gold}G ${m.silver}A`;
  if (m.silver > 0) return `${m.silver}A ${m.copper}C`;
  return `${m.copper}C`;
}

function markUnread(cid, on) {
  const dot = document.getElementById(`unread-${cid}`);
  if (dot) dot.classList.toggle('hidden', !on);
}

// ── Player detail (center column) ────────────────────────────────────────────

function selectPlayer(cid) {
  selectedCharId = cid;
  document.querySelectorAll('.player-card').forEach(c => c.classList.remove('selected'));
  const card = document.getElementById(`pcard-${cid}`);
  if (card) card.classList.add('selected');
  renderDetail(cid);
  openChatWith(cid);
}

function findPlayer(cid) {
  return allPlayers.find(p => p.character.id === cid);
}

function renderDetail(cid) {
  const p = findPlayer(cid);
  if (!p) return;
  const c = p.character;
  const detail = document.getElementById('player-detail');

  detail.innerHTML = `
    <div class="row" style="justify-content:space-between; align-items:center">
      <h2 style="color:var(--accent2)">${escape_html(c.name)}</h2>
      <button class="small" onclick="openConstraintPlayer(${c.id})">Contrainte de</button>
    </div>

    <!-- Stats bars + controls -->
    <div class="panel">
      <div class="panel-title">Stats</div>
      <div class="stat-block">
        <div class="bar-wrap bar-hp" id="detail-hp-wrap">
          <div class="bar-label"><span>HP</span><span id="detail-hp-text">${c.curr_hp} / ${c.max_hp}</span></div>
          <div class="bar-track"><div class="bar-fill" id="detail-hp-bar" style="width:${bar_width(c.curr_hp, c.max_hp)}%"></div></div>
        </div>
        <div class="row" style="flex-wrap:wrap; gap:0.3rem; margin-bottom:0.5rem">
          <span class="dim" style="font-size:11px; width:30px">HP</span>
          <div class="quick-btns">
            <button class="small" onclick="quickDmg(${c.id},'curr_hp',1)">-1</button>
            <button class="small" onclick="quickDmg(${c.id},'curr_hp',5)">-5</button>
            <button class="small" onclick="quickDmg(${c.id},'curr_hp',15)">-15</button>
            <button class="small" onclick="quickDmg(${c.id},'curr_hp',30)">-30</button>
          </div>
          <input type="number" id="set-hp" class="inline-input" placeholder="Set" onkeydown="if(event.key==='Enter') setStatVal(${c.id},'curr_hp','set-hp')">
          <button class="small" onclick="setStatVal(${c.id},'curr_hp','set-hp')">Set</button>
          <input type="number" id="ded-hp" class="inline-input" placeholder="Ded" onkeydown="if(event.key==='Enter') deductStat(${c.id},'curr_hp','ded-hp')">
          <button class="small" onclick="deductStat(${c.id},'curr_hp','ded-hp')">Ded</button>
          <input type="number" id="set-maxhp" class="inline-input" placeholder="Max" onkeydown="if(event.key==='Enter') setStatVal(${c.id},'max_hp','set-maxhp')">
          <button class="small" onclick="setStatVal(${c.id},'max_hp','set-maxhp')">Max</button>
        </div>

        <div class="bar-wrap bar-stam" id="detail-stam-wrap">
          <div class="bar-label"><span>Stamina</span><span id="detail-stam-text">${c.curr_stam} / ${c.max_stam}</span></div>
          <div class="bar-track"><div class="bar-fill" id="detail-stam-bar" style="width:${bar_width(c.curr_stam, c.max_stam)}%"></div></div>
        </div>
        <div class="row" style="flex-wrap:wrap; gap:0.3rem">
          <span class="dim" style="font-size:11px; width:30px">STM</span>
          <div class="quick-btns">
            <button class="small" onclick="quickDmg(${c.id},'curr_stam',1)">-1</button>
            <button class="small" onclick="quickDmg(${c.id},'curr_stam',5)">-5</button>
            <button class="small" onclick="quickDmg(${c.id},'curr_stam',15)">-15</button>
            <button class="small" onclick="quickDmg(${c.id},'curr_stam',30)">-30</button>
          </div>
          <input type="number" id="set-stam" class="inline-input" placeholder="Set" onkeydown="if(event.key==='Enter') setStatVal(${c.id},'curr_stam','set-stam')">
          <button class="small" onclick="setStatVal(${c.id},'curr_stam','set-stam')">Set</button>
          <input type="number" id="ded-stam" class="inline-input" placeholder="Ded" onkeydown="if(event.key==='Enter') deductStat(${c.id},'curr_stam','ded-stam')">
          <button class="small" onclick="deductStat(${c.id},'curr_stam','ded-stam')">Ded</button>
          <input type="number" id="set-maxstam" class="inline-input" placeholder="Max" onkeydown="if(event.key==='Enter') setStatVal(${c.id},'max_stam','set-maxstam')">
          <button class="small" onclick="setStatVal(${c.id},'max_stam','set-maxstam')">Max</button>
        </div>
      </div>

    </div>

    <!-- Specials (only rendered if character has them) -->
    <div id="detail-specials"></div>

    <!-- Abilities -->
    <div class="panel">
      <div class="panel-title">Capacites</div>
      <div id="detail-abilities"></div>
    </div>

    <!-- Inventory -->
    <div class="panel">
      <div class="panel-title">Inventaire</div>
      <table>
        <thead><tr><th>Objet</th><th>Qte</th><th></th></tr></thead>
        <tbody id="detail-inventory"></tbody>
      </table>
      <div class="row" style="margin-top:0.5rem; gap:0.4rem">
        <input type="text" id="inv-name" placeholder="Objet" style="flex:2">
        <input type="number" id="inv-amt" placeholder="Qte" min="1" value="1" style="width:60px">
        <button class="small" onclick="hostAddItem(${c.id})">+</button>
      </div>
    </div>

    <!-- Money -->
    <div class="panel">
      <div class="panel-title">Argent</div>
      <div class="money-grid" id="detail-money"></div>
      <div class="money-input-grid" style="margin-top:0.5rem">
        <div class="money-input-cell plat"><span>P</span><input id="md-plat" type="number" min="0" value="0"></div>
        <div class="money-input-cell gold"><span>O</span><input id="md-gold" type="number" min="0" value="0"></div>
        <div class="money-input-cell silver"><span>A</span><input id="md-silver" type="number" min="0" value="0"></div>
        <div class="money-input-cell copper"><span>C</span><input id="md-copper" type="number" min="0" value="0"></div>
      </div>
      <div class="row" style="margin-top:0.3rem; gap:0.4rem">
        <button class="small primary w100" onclick="hostMoneyUpdate(${c.id}, 1)">Ajouter</button>
        <button class="small danger w100"  onclick="hostMoneyUpdate(${c.id}, -1)">Retirer</button>
      </div>
    </div>
  `;

  renderDetailInventory(p.inventory);
  render_money(c.copper, document.getElementById('detail-money'));
  renderDetailAbilities(p.abilities || []);
  renderDetailSpecials(p.specials || [], c.id);
}

function refreshStatBars(data) {
  const hp   = document.getElementById('detail-hp-text');
  const stam = document.getElementById('detail-stam-text');
  const hpb  = document.getElementById('detail-hp-bar');
  const stb  = document.getElementById('detail-stam-bar');
  if (hp)   hp.textContent   = `${data.curr_hp} / ${data.max_hp}`;
  if (stam) stam.textContent = `${data.curr_stam} / ${data.max_stam}`;
  if (hpb)  hpb.style.width  = bar_width(data.curr_hp, data.max_hp) + '%';
  if (stb)  stb.style.width  = bar_width(data.curr_stam, data.max_stam) + '%';
}

function renderDetailInventory(items) {
  const tbody = document.getElementById('detail-inventory');
  if (!tbody) return;
  tbody.innerHTML = '';
  items.forEach(item => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td><input type="text" value="${escape_html(item.item_name)}" id="inv-edit-name-${item.id}" style="width:100%"
        onchange="hostEditItem(${item.character_id}, ${item.id})"></td>
      <td><input type="number" value="${item.amount}" id="inv-edit-amt-${item.id}" style="width:60px" min="1"
        oninput="hostEditItem(${item.character_id}, ${item.id})"></td>
      <td><button class="small danger" onclick="hostRemoveItem(${item.character_id}, ${item.id})">X</button></td>
    `;
    tbody.appendChild(tr);
  });
}

// ── Stat operations ───────────────────────────────────────────────────────────

function quickDmg(cid, field, amount) {
  const p = findPlayer(cid);
  if (!p) return;
  const current = p.character[field];
  send('stat_update', { character_id: cid, field, value: current - amount });
}

function setStatVal(cid, field, inputId) {
  const v = parseInt(document.getElementById(inputId).value);
  if (isNaN(v)) return;
  send('stat_update', { character_id: cid, field, value: v });
  document.getElementById(inputId).value = '';
}

function deductStat(cid, field, inputId) {
  const p = findPlayer(cid);
  if (!p) return;
  const v = parseInt(document.getElementById(inputId).value);
  if (isNaN(v)) return;
  const current = p.character[field];
  send('stat_update', { character_id: cid, field, value: current - v });
  document.getElementById(inputId).value = '';
}

// ── Profile edit popup ────────────────────────────────────────────────────────

let profileEditCid = null;

function openProfileEdit(cid) {
  const p = findPlayer(cid);
  if (!p) return;
  const c = p.character;
  profileEditCid = cid;
  document.getElementById('profile-overlay-title').textContent = `Profil — ${c.name}`;
  document.getElementById('pop-pf-name').value  = c.name        || '';
  document.getElementById('pop-pf-sex').value   = c.sex         || '';
  document.getElementById('pop-pf-age').value   = c.age         || '';
  document.getElementById('pop-pf-p1').value       = c.power1       || '';
  document.getElementById('pop-pf-p1desc').value   = c.power1_desc  || '';
  document.getElementById('pop-pf-p2').value       = c.power2       || '';
  document.getElementById('pop-pf-physdesc').value = c.physical_desc || '';
  document.getElementById('pop-pf-weap').value     = c.weapons      || '';
  document.getElementById('profile-overlay').classList.remove('hidden');
}

function closeProfileEdit() {
  document.getElementById('profile-overlay').classList.add('hidden');
  profileEditCid = null;
}

function submitProfileEdit() {
  if (!profileEditCid) return;
  const changes = {
    name:        document.getElementById('pop-pf-name').value.trim(),
    sex:         document.getElementById('pop-pf-sex').value.trim() || null,
    age:         parseInt(document.getElementById('pop-pf-age').value) || null,
    power1:        document.getElementById('pop-pf-p1').value.trim() || null,
    power1_desc:   document.getElementById('pop-pf-p1desc').value.trim() || null,
    power2:        document.getElementById('pop-pf-p2').value.trim() || null,
    physical_desc: document.getElementById('pop-pf-physdesc').value.trim() || null,
    weapons:       document.getElementById('pop-pf-weap').value.trim() || null,
  };
  send('profile_update', { character_id: profileEditCid, changes });
  closeProfileEdit();
}

// ── Specials (detail panel) ──────────────────────────────────────────────────

function renderDetailSpecials(specials, charId) {
  const container = document.getElementById('detail-specials');
  if (!container) return;
  if (!specials || !specials.length) { container.innerHTML = ''; return; }

  container.innerHTML = specials.map(s => {
    if (s.key === 'stored_damage') {
      return `<div class="panel">
        <div class="panel-title">Degats stockes de ${escape_html(findPlayer(charId)?.character?.name || '')}</div>
        <div style="font-size:1.6rem; color:var(--accent2); margin-bottom:0.5rem" id="host-special-val-stored_damage-${charId}">${s.value}</div>
        <div class="row" style="gap:0.4rem; align-items:center">
          <input type="number" id="host-special-input-${charId}" min="1" placeholder="Deduire"
            style="flex:1"
            onkeydown="if(event.key==='Enter') deductSpecial(${charId},'stored_damage')">
          <button class="small danger" onclick="clearSpecial(${charId},'stored_damage')">Vider</button>
        </div>
      </div>`;
    }
    return '';
  }).join('');
}

function deductSpecial(charId, key) {
  const input = document.getElementById(`host-special-input-${charId}`);
  const amount = parseInt(input.value);
  if (!amount || amount <= 0) return;
  send('special_deduct', { character_id: charId, key, amount });
  input.value = '';
}

function clearSpecial(charId, key) {
  send('special_clear', { character_id: charId, key });
}

// ── Abilities (detail panel) ──────────────────────────────────────────────────

function renderDetailAbilities(abilities) {
  const container = document.getElementById('detail-abilities');
  if (!container) return;
  if (!abilities.length) {
    container.innerHTML = '<p class="dim" style="font-size:12px">Aucune capacite.</p>';
    return;
  }
  container.innerHTML = abilities.map(ab => {
    const clickable = ab.confirmed && ab.drain_type;
    const onclick   = clickable ? `onclick="applyAbilityDrain(${selectedCharId},'${ab.drain_type}',${ab.drain_value||0})"` : '';
    const cursor    = clickable ? 'cursor:pointer' : '';
    return `<div class="ability-card ${ab.confirmed ? '' : 'pending'}" ${onclick} style="${cursor}">
      <div class="ability-name">${escape_html(ab.name)}${ab.confirmed ? '' : ' <span class="badge" style="background:var(--orange)">en attente</span>'}</div>
      <div class="ability-meta">${drain_label_raw(ab)} &mdash; ${escape_html(ab.description || '')}</div>
    </div>`;
  }).join('');
}

function applyAbilityDrain(cid, drain_type, drain_value) {
  if (!drain_type || drain_value <= 0) return;
  const p = findPlayer(cid);
  if (!p) return;
  if (drain_type === 'hp' || drain_type === 'both')
    send('stat_update', { character_id: cid, field: 'curr_hp',   value: p.character.curr_hp   - drain_value });
  if (drain_type === 'stam' || drain_type === 'both')
    send('stat_update', { character_id: cid, field: 'curr_stam', value: p.character.curr_stam - drain_value });
}

// ── Live dice rolls panel ─────────────────────────────────────────────────────

function renderLiveRolls() {
  const container = document.getElementById('live-rolls-panel');
  if (!container) return;
  if (!allPlayers.length) {
    container.innerHTML = '<span class="dim" style="font-size:12px">Aucun joueur.</span>';
    return;
  }
  container.innerHTML = `<div style="display:flex; flex-wrap:wrap; gap:0.4rem">` +
    allPlayers.map(p => {
      const c = p.character;
      const roll = c.last_roll !== null && c.last_roll !== undefined ? c.last_roll : '-';
      return `<div style="background:#111; border:1px solid var(--border); padding:0.2rem 0.6rem; font-size:12px">` +
        `<span class="dim">${escape_html(c.name)}</span>` +
        `<span id="roll-live-${c.id}" style="margin-left:0.5rem; font-weight:bold; color:var(--accent2)">${roll}</span>` +
        `</div>`;
    }).join('') + `</div>`;
}

// ── Inventory (host) ──────────────────────────────────────────────────────────

function hostAddItem(cid) {
  const name   = document.getElementById('inv-name').value.trim();
  const amount = parseInt(document.getElementById('inv-amt').value) || 1;
  if (!name) return;
  send('inventory_add', { character_id: cid, item_name: name, amount });
  document.getElementById('inv-name').value  = '';
  document.getElementById('inv-amt').value   = '1';
}

function hostRemoveItem(cid, itemId) {
  send('inventory_remove', { character_id: cid, item_id: itemId });
}

function hostEditItem(cid, itemId) {
  const name   = document.getElementById(`inv-edit-name-${itemId}`)?.value.trim();
  const amount = parseInt(document.getElementById(`inv-edit-amt-${itemId}`)?.value) || 1;
  if (!name) return;
  send('inventory_edit', { character_id: cid, item_id: itemId, item_name: name, amount });
}

// ── Money (host) ──────────────────────────────────────────────────────────────

function hostMoneyUpdate(cid, sign) {
  const amount = read_money_inputs('md');
  if (amount <= 0) return;
  send('money_update', { character_id: cid, amount: sign * amount });
  reset_money_inputs('md');
}

// ── Host dice ─────────────────────────────────────────────────────────────────

function setHostDie(n) {
  hostDie = n;
  [6, 10, 20, 100].forEach(d => {
    document.getElementById(`h-die-${d}`).classList.toggle('primary', d === n);
  });
}

function hostRoll() {
  send('host_roll', { die_type: hostDie });
}

// ── Dice constraints ──────────────────────────────────────────────────────────

function openConstraintPlayer(cid) {
  constraintTarget = { character_id: cid, is_host: false };
  document.getElementById('constraint-title').textContent = 'Contrainte joueur';
  resetConstraintForm();
  const p = findPlayer(cid);
  if (p && p.dice_constraint) fillConstraintForm(p.dice_constraint);
  document.getElementById('constraint-overlay').classList.remove('hidden');
}

function openConstraintSelf() {
  constraintTarget = { character_id: null, is_host: true };
  document.getElementById('constraint-title').textContent = 'Contrainte mon de';
  resetConstraintForm();
  fetch('/api/host/constraint/self').then(r => r.json()).then(c => {
    if (c) fillConstraintForm(c);
  });
  document.getElementById('constraint-overlay').classList.remove('hidden');
}

function closeConstraint() { document.getElementById('constraint-overlay').classList.add('hidden'); }

function resetConstraintForm() {
  document.getElementById('con-die').value   = '';
  document.getElementById('con-min').value   = '';
  document.getElementById('con-max').value   = '';
  document.getElementById('con-fixed').value = '';
  document.getElementById('con-half').checked = false;
}

function fillConstraintForm(c) {
  if (c.allowed_die)      document.getElementById('con-die').value   = c.allowed_die;
  if (c.range_min != null) document.getElementById('con-min').value  = c.range_min;
  if (c.range_max != null) document.getElementById('con-max').value  = c.range_max;
  if (c.fixed_value != null) document.getElementById('con-fixed').value = c.fixed_value;
  document.getElementById('con-half').checked = !!c.always_over_half;
}

function applyConstraint() {
  if (!constraintTarget) return;
  const data = {
    character_id:     constraintTarget.character_id,
    is_host:          constraintTarget.is_host,
    allowed_die:      parseInt(document.getElementById('con-die').value) || null,
    range_min:        parseInt(document.getElementById('con-min').value)  || null,
    range_max:        parseInt(document.getElementById('con-max').value)  || null,
    fixed_value:      parseInt(document.getElementById('con-fixed').value) || null,
    always_over_half: document.getElementById('con-half').checked,
  };
  send('dice_constraint_set', data);
  if (!constraintTarget.is_host) {
    const p = findPlayer(constraintTarget.character_id);
    if (p) p.dice_constraint = data;
  }
  closeConstraint();
}

function clearConstraint() {
  if (!constraintTarget) return;
  send('dice_constraint_clear', {
    character_id: constraintTarget.character_id,
    is_host:      constraintTarget.is_host
  });
  if (!constraintTarget.is_host) {
    const p = findPlayer(constraintTarget.character_id);
    if (p) p.dice_constraint = null;
  }
  closeConstraint();
}

// ── Broadcast message ─────────────────────────────────────────────────────────

function openBroadcast() {
  const list = document.getElementById('broadcast-player-list');
  list.innerHTML = '';
  allPlayers.forEach(p => {
    const label = document.createElement('label');
    label.style.cssText = 'display:flex; align-items:center; gap:0.4rem; cursor:pointer; font-size:13px';
    label.innerHTML = `<input type="checkbox" value="${p.character.id}" checked> ${escape_html(p.character.name)}`;
    list.appendChild(label);
  });
  document.getElementById('broadcast-overlay').classList.remove('hidden');
}
function closeBroadcast() { document.getElementById('broadcast-overlay').classList.add('hidden'); }

function sendBroadcast() {
  const content = document.getElementById('broadcast-content').value.trim();
  const mode    = document.getElementById('broadcast-mode').value;
  if (!content) return;

  const ids = [...document.querySelectorAll('#broadcast-player-list input:checked')]
    .map(cb => parseInt(cb.value));
  if (!ids.length) return;

  send('host_message', { character_ids: ids, content, mode });

  ids.forEach(cid => {
    if (!chatLogs[cid]) chatLogs[cid] = [];
    chatLogs[cid].push({ sender: 'Vous', content, mode });
    if (chatTarget === cid) {
      append_chat(document.getElementById('chat-host-log'), 'Vous', content, mode);
    }
  });

  document.getElementById('broadcast-content').value = '';
  closeBroadcast();
}

// ── Chat panel ────────────────────────────────────────────────────────────────

function openChatWith(cid) {
  chatTarget = cid;
  markUnread(cid, false);

  const log = document.getElementById('chat-host-log');
  log.innerHTML = '';
  const p = findPlayer(cid);
  if (p) {
    document.getElementById('chat-panel-title').textContent = `Chat — ${p.character.name}`;
  }

  if (!chatLogs[cid]) {
    fetch(`/api/host/messages/${cid}`)
      .then(r => r.json())
      .then(msgs => {
        chatLogs[cid] = msgs.map(m => ({
          sender: m.sender === 'host' ? 'Vous' : (findPlayer(cid)?.character.name || 'Joueur'),
          content: m.content,
          mode: m.mode
        }));
        chatLogs[cid].forEach(m => append_chat(log, m.sender, m.content, m.mode));
      });
  } else {
    chatLogs[cid].forEach(m => append_chat(log, m.sender, m.content, m.mode));
  }
}

function switchChatTab(tab) {
  // only one chat tab for now; kept for future expansion
}

function sendChatMsg() {
  if (!chatTarget) return;
  const content = document.getElementById('chat-input').value.trim();
  const mode    = document.getElementById('chat-mode').value;
  if (!content) return;

  send('host_message', { character_ids: [chatTarget], content, mode });

  if (!chatLogs[chatTarget]) chatLogs[chatTarget] = [];
  chatLogs[chatTarget].push({ sender: 'Vous', content, mode });
  append_chat(document.getElementById('chat-host-log'), 'Vous', content, mode);
  document.getElementById('chat-input').value = '';
}

function appendSystemMsg(text) {
  if (!chatTarget) return;
  const div = document.createElement('div');
  div.className = 'chat-msg system';
  div.textContent = text;
  const log = document.getElementById('chat-host-log');
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}

// ── Change requests ───────────────────────────────────────────────────────────

function updatePendingBadge() {
  const badge = document.getElementById('pending-count');
  if (pendingRequests.length > 0) {
    badge.textContent = `Demandes: ${pendingRequests.length}`;
    badge.classList.remove('hidden');
  } else {
    badge.classList.add('hidden');
  }
}

function openNextRequest() {
  if (!pendingRequests.length) return;
  currentRequestIndex = 0;
  showRequest(pendingRequests[0]);
}

function showRequest(req) {
  let payload;
  try { payload = JSON.parse(req.payload); } catch { payload = {}; }

  const content = document.getElementById('req-content');
  let html = `<strong>Joueur:</strong> ${escape_html(req.player_name || `#${req.character_id}`)}<br>`;
  html += `<strong>Type:</strong> ${req.req_type === 'profile' ? 'Modification de profil' : 'Nouvelle capacite'}<br><br>`;

  if (req.req_type === 'profile') {
    const labels = { name:'Nom', sex:'Sexe', age:'Age', power1:'Pouvoir 1', power2:'Pouvoir 2', description:'Description', weapons:'Armes' };
    html += '<table>';
    for (const [k, v] of Object.entries(payload)) {
      if (v !== null && v !== undefined && v !== '') {
        html += `<tr><th>${labels[k] || k}</th><td>${escape_html(String(v))}</td></tr>`;
      }
    }
    html += '</table>';
  } else {
    html += `<strong>${escape_html(payload.name || '')}</strong><br>`;
    html += `${drain_label_raw(payload)}<br>`;
    html += `<span class="dim">${escape_html(payload.description || '')}</span>`;
  }

  content.innerHTML = html;
  document.getElementById('req-note').value = '';
  document.getElementById('req-note-row').classList.add('hidden');
  document.getElementById('req-edit-fields').classList.add('hidden');
  document.getElementById('req-edit-body').innerHTML = '';
  document.getElementById('req-modify-btn').textContent = 'Modifier';
  document.getElementById('req-overlay').classList.remove('hidden');
}

function drain_label_raw(ab) {
  if (!ab.drain_type) return 'Pas de drainage';
  const type = ab.drain_type === 'hp' ? 'HP' : ab.drain_type === 'stam' ? 'Stamina' : 'HP + Stamina';
  return `Drainage ${type}: ${ab.drain_value || 0}`;
}

function toggleModify() {
  const editFields = document.getElementById('req-edit-fields');
  const noteRow    = document.getElementById('req-note-row');
  const isOpen     = !editFields.classList.contains('hidden');

  if (isOpen) {
    editFields.classList.add('hidden');
    noteRow.classList.add('hidden');
    document.getElementById('req-modify-btn').textContent = 'Modifier';
    return;
  }

  const req = pendingRequests[currentRequestIndex];
  if (!req) return;
  let payload;
  try { payload = JSON.parse(req.payload); } catch { payload = {}; }

  const body = document.getElementById('req-edit-body');
  body.innerHTML = '';

  if (req.req_type === 'ability') {
    body.innerHTML = `
      <div class="form-row"><label>Nom</label><input id="mod-name" type="text" value="${escape_html(payload.name||'')}"></div>
      <div class="form-row"><label>Description</label><textarea id="mod-desc" rows="2">${escape_html(payload.description||'')}</textarea></div>
      <div class="row">
        <div class="form-row" style="flex:1">
          <label>Type de drainage</label>
          <select id="mod-drain-type">
            <option value="">Aucun</option>
            <option value="hp" ${payload.drain_type==='hp'?'selected':''}>HP</option>
            <option value="stam" ${payload.drain_type==='stam'?'selected':''}>Stamina</option>
            <option value="both" ${payload.drain_type==='both'?'selected':''}>Les deux</option>
          </select>
        </div>
        <div class="form-row" style="flex:1"><label>Valeur</label><input id="mod-drain-val" type="number" min="0" value="${payload.drain_value||0}" style="width:100%"></div>
      </div>
    `;
  } else {
    body.innerHTML = `
      <div class="form-row"><label>Nom</label><input id="mod-pf-name" type="text" value="${escape_html(payload.name||'')}"></div>
      <div class="row">
        <div class="form-row" style="flex:1"><label>Sexe</label><input id="mod-pf-sex" type="text" value="${escape_html(payload.sex||'')}"></div>
        <div class="form-row" style="flex:1"><label>Age</label><input id="mod-pf-age" type="number" value="${payload.age||''}" style="width:100%"></div>
      </div>
      <div class="form-row"><label>Pouvoir 1</label><input id="mod-pf-p1" type="text" value="${escape_html(payload.power1||'')}"></div>
      <div class="form-row"><label>Pouvoir 2</label><input id="mod-pf-p2" type="text" value="${escape_html(payload.power2||'')}"></div>
      <div class="form-row"><label>Description</label><textarea id="mod-pf-desc" rows="2">${escape_html(payload.description||'')}</textarea></div>
      <div class="form-row"><label>Armes</label><input id="mod-pf-weap" type="text" value="${escape_html(payload.weapons||'')}"></div>
    `;
  }

  editFields.classList.remove('hidden');
  noteRow.classList.remove('hidden');
  document.getElementById('req-modify-btn').textContent = 'Annuler modif';
}

function respondRequest(action) {
  const req = pendingRequests[currentRequestIndex];
  if (!req) return;

  const host_note = document.getElementById('req-note').value.trim() || null;
  const editOpen  = !document.getElementById('req-edit-fields').classList.contains('hidden');

  let payload_override = null;
  if (editOpen) {
    let payload;
    try { payload = JSON.parse(req.payload); } catch { payload = {}; }

    if (req.req_type === 'ability') {
      payload_override = {
        name:        document.getElementById('mod-name')?.value.trim() || payload.name,
        description: document.getElementById('mod-desc')?.value.trim() || '',
        drain_type:  document.getElementById('mod-drain-type')?.value || null,
        drain_value: parseInt(document.getElementById('mod-drain-val')?.value) || 0,
      };
    } else {
      payload_override = {
        name:        document.getElementById('mod-pf-name')?.value.trim() || payload.name,
        sex:         document.getElementById('mod-pf-sex')?.value.trim() || null,
        age:         parseInt(document.getElementById('mod-pf-age')?.value) || null,
        power1:      document.getElementById('mod-pf-p1')?.value.trim() || null,
        power2:      document.getElementById('mod-pf-p2')?.value.trim() || null,
        description: document.getElementById('mod-pf-desc')?.value.trim() || null,
        weapons:     document.getElementById('mod-pf-weap')?.value.trim() || null,
      };
    }
    action = 'modified';
  }

  send('request_response', {
    request_id: req.id,
    action,
    host_note,
    payload: payload_override
  });

  pendingRequests.splice(currentRequestIndex, 1);
  document.getElementById('req-overlay').classList.add('hidden');
  updatePendingBadge();

  if (pendingRequests.length > 0) {
    currentRequestIndex = Math.min(currentRequestIndex, pendingRequests.length - 1);
    showRequest(pendingRequests[currentRequestIndex]);
  }
}

init();
