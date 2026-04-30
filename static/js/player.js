let ws = null;
let me = null;
let character = null;
let selectedDie = 20;
let players = [];
let activeDmPartnerId = null;
let dmHistory = {};   // character_id -> messages[]
let hostChatUnread = false;

// ── Init ──────────────────────────────────────────────────────────────────────

async function init() {
  const r = await fetch('/api/me');
  if (!r.ok) { window.location.href = '/index.html'; return; }
  me = await r.json();
  if (me.role !== 'player') { window.location.href = '/host.html'; return; }

  if (!me.character_id) {
    document.getElementById('create-overlay').classList.remove('hidden');
    return;
  }

  document.getElementById('create-overlay').classList.add('hidden');
  await loadAll();
  connectWs();
  document.getElementById('app').style.display = '';
}

async function loadAll() {
  const [charR, msgR, invR, abR, plR] = await Promise.all([
    fetch('/api/character'),
    fetch('/api/messages/host'),
    fetch('/api/inventory'),
    fetch('/api/abilities'),
    fetch('/api/players')
  ]);
  character = await charR.json();
  const msgs = await msgR.json();
  const inv  = await invR.json();
  const abs  = await abR.json();
  players    = await plR.json();

  renderCharacter(character);
  msgs.forEach(m => appendHostMsg(m.sender === 'host' ? 'Maitre du jeu' : character.name, m.content, m.mode));
  renderInventory(inv);
  renderAbilities(abs);
  renderMoneySelect();
}

// ── WebSocket ─────────────────────────────────────────────────────────────────

function connectWs() {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  ws = new WebSocket(`${proto}://${location.host}/ws`);

  ws.onopen = () => {
    const el = document.getElementById('ws-dot');
    if (el) { el.style.background = 'var(--green)'; el.title = 'Connecte'; }
  };

  ws.onmessage = e => {
    const msg = JSON.parse(e.data);
    handleWsMessage(msg);
  };

  ws.onerror = err => console.error('WS error', err);

  ws.onclose = () => {
    const el = document.getElementById('ws-dot');
    if (el) { el.style.background = 'var(--red)'; el.title = 'Deconnecte'; }
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
    case 'stat_updated':
      if (msg.data.character_id === me.character_id) updateStats(msg.data);
      break;
    case 'roll_result':
      if (msg.data.character_id === me.character_id) {
        const rollEl = document.getElementById('my-roll-display');
        rollEl.textContent = msg.data.result;
        flash_roll(rollEl);
      }
      break;
    case 'host_rolled': {
      const hostEl = document.getElementById('host-roll-display');
      hostEl.textContent = msg.data.result;
      flash_roll(hostEl);
      break;
    }
    case 'message_received':
      if (msg.data.sender === 'host') {
        appendHostMsg('Maitre du jeu', msg.data.content, msg.data.mode);
        if (document.getElementById('tab-chat-host').classList.contains('active')) {
          // already visible, no badge
        } else {
          hostChatUnread = true;
          document.getElementById('host-badge').classList.remove('hidden');
        }
      }
      break;
    case 'dm_received':
      handleDmReceived(msg.data);
      break;
    case 'inventory_updated':
      if (msg.data.character_id === me.character_id) renderInventory(msg.data.items);
      break;
    case 'money_updated':
      if (msg.data.character_id === me.character_id) {
        character.copper = msg.data.copper;
        renderMoney(msg.data.copper);
      }
      break;
    case 'profile_updated':
      if (msg.data.id === me.character_id) {
        character = msg.data;
        renderCharacter(character);
      }
      break;
    case 'abilities_updated':
      renderAbilities(msg.data);
      break;
    case 'request_resolved':
      showToast(buildResolvedMsg(msg.data));
      if (msg.data.character && msg.data.req_type === 'profile') {
        character = msg.data.character;
        renderCharacter(character);
      }
      break;
    case 'error':
      showToast(msg.data.message, true);
      break;
  }
}

// ── Render ────────────────────────────────────────────────────────────────────

function renderCharacter(c) {
  character = c;
  document.getElementById('player-name-display').textContent = c.name;
  updateStats({ curr_hp: c.curr_hp, max_hp: c.max_hp, curr_stam: c.curr_stam, max_stam: c.max_stam });
  renderMoney(c.copper);

  document.getElementById('pf-name').textContent  = c.name   || '-';
  document.getElementById('pf-sex').textContent   = c.sex    || '-';
  document.getElementById('pf-age').textContent   = c.age    || '-';
  document.getElementById('pf-p1').textContent    = c.power1 || '-';
  document.getElementById('pf-p2').textContent    = c.power2 || '-';
  document.getElementById('pf-desc').textContent  = c.description || '-';
  document.getElementById('pf-weap').textContent  = c.weapons || '-';

  if (c.last_roll !== null && c.last_roll !== undefined) {
    document.getElementById('my-roll-display').textContent = c.last_roll;
  }
}

function updateStats(data) {
  const hpBar   = document.querySelector('.bar-hp');
  const stamBar = document.querySelector('.bar-stam');
  update_bar(hpBar,   data.curr_hp,   data.max_hp);
  update_bar(stamBar, data.curr_stam, data.max_stam);
  document.getElementById('hp-text').textContent   = `${data.curr_hp} / ${data.max_hp}`;
  document.getElementById('stam-text').textContent = `${data.curr_stam} / ${data.max_stam}`;
  if (character) {
    character.curr_hp = data.curr_hp; character.max_hp = data.max_hp;
    character.curr_stam = data.curr_stam; character.max_stam = data.max_stam;
  }
}

function renderMoney(copper) {
  render_money(copper, document.getElementById('money-display'));
}

function renderAbilities(abs) {
  const list = document.getElementById('abilities-list');
  list.innerHTML = '';
  if (!abs.length) {
    list.innerHTML = '<p class="dim" style="font-size:12px">Aucune capacite.</p>';
    return;
  }
  abs.forEach(ab => {
    const div = document.createElement('div');
    div.className = `ability-card ${ab.confirmed ? '' : 'pending'}`;
    div.innerHTML = `
      <div class="ability-name">${escape_html(ab.name)} ${ab.confirmed ? '' : '<span class="badge" style="background:var(--orange)">en attente</span>'}</div>
      <div class="ability-meta">${drain_label(ab)} &mdash; ${escape_html(ab.description || '')}</div>
      ${ab.confirmed ? `<button class="small" style="margin-top:0.4rem" onclick="openCast(${ab.id})">Afficher</button>` : ''}
    `;
    list.appendChild(div);
  });
}

function drain_label(ab) {
  if (!ab.drain_type) return 'Pas de drainage';
  const type = ab.drain_type === 'hp' ? 'HP' : ab.drain_type === 'stam' ? 'Stamina' : 'HP + Stamina';
  return `Drainage ${type}: ${ab.drain_value || 0}`;
}

function renderMoneySelect() {
  const sel = document.getElementById('money-to');
  sel.innerHTML = players.map(p => `<option value="${p.id}">${escape_html(p.name)}</option>`).join('');
}

// ── Tabs ──────────────────────────────────────────────────────────────────────

function switchTab(name) {
  document.querySelectorAll('.tab-btn').forEach((b, i) => b.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
  const btn = [...document.querySelectorAll('.tab-btn')].find(b => b.getAttribute('onclick').includes(name));
  if (btn) btn.classList.add('active');
  document.getElementById(`tab-${name}`).classList.add('active');

  if (name === 'chat-host') {
    hostChatUnread = false;
    document.getElementById('host-badge').classList.add('hidden');
  }
}

// ── Dice ──────────────────────────────────────────────────────────────────────

function setDie(n) {
  selectedDie = n;
  [6, 10, 20, 100].forEach(d => {
    document.getElementById(`die-${d}`).classList.toggle('primary', d === n);
  });
}

function roll() {
  send('roll', { die_type: selectedDie });
}

// ── Chat (host) ───────────────────────────────────────────────────────────────

function appendHostMsg(sender, content, mode) {
  append_chat(document.getElementById('chat-host-log'), sender, content, mode);
}

function sendHostChat() {
  const input = document.getElementById('chat-host-input');
  const mode  = document.getElementById('chat-mode').value;
  const content = input.value.trim();
  if (!content) return;
  send('player_message', { content, mode });
  appendHostMsg(character.name, content, mode);
  input.value = '';
}

// ── DM (player-to-player) ─────────────────────────────────────────────────────

function openDmSelect() {
  const list = document.getElementById('dm-player-list');
  list.innerHTML = '';
  players.forEach(p => {
    const btn = document.createElement('button');
    btn.textContent = p.name;
    btn.className = 'w100';
    btn.style.marginBottom = '0.3rem';
    btn.onclick = () => { openDmWith(p); closeDmSelect(); };
    list.appendChild(btn);
  });
  document.getElementById('dm-select-overlay').classList.remove('hidden');
}
function closeDmSelect() { document.getElementById('dm-select-overlay').classList.add('hidden'); }

async function openDmWith(player) {
  activeDmPartnerId = player.id;
  document.getElementById('dm-partner-name').textContent = player.name;
  document.getElementById('dm-area').classList.remove('hidden');
  document.getElementById('dm-empty').classList.add('hidden');

  if (!dmHistory[player.id]) {
    const r = await fetch(`/api/messages/player/${player.id}`);
    dmHistory[player.id] = await r.json();
  }

  const log = document.getElementById('chat-dm-log');
  log.innerHTML = '';
  dmHistory[player.id].forEach(m => {
    const senderName = m.sender_id === me.character_id ? character.name : player.name;
    append_chat(log, senderName, m.content, 'RP');
  });
}

function closeDmConversation() {
  activeDmPartnerId = null;
  document.getElementById('dm-area').classList.add('hidden');
  document.getElementById('dm-empty').classList.remove('hidden');
}

function sendDm() {
  if (!activeDmPartnerId) return;
  const input = document.getElementById('chat-dm-input');
  const content = input.value.trim();
  if (!content) return;
  send('player_dm', { receiver_id: activeDmPartnerId, content });
  input.value = '';
}

function handleDmReceived(data) {
  const partnerId = data.sender_id === me.character_id ? data.receiver_id : data.sender_id;
  if (!dmHistory[partnerId]) dmHistory[partnerId] = [];
  dmHistory[partnerId].push(data);

  if (activeDmPartnerId === partnerId) {
    const log = document.getElementById('chat-dm-log');
    const senderName = data.sender_id === me.character_id ? character.name : data.sender_name;
    append_chat(log, senderName, data.content, 'RP');
  }
}

// ── Abilities ─────────────────────────────────────────────────────────────────

let abilitiesCache = [];

function openAbility() { document.getElementById('ability-overlay').classList.remove('hidden'); }
function closeAbility() {
  document.getElementById('ability-overlay').classList.add('hidden');
  ['ab-name','ab-desc','ab-drain-val'].forEach(id => document.getElementById(id).value = '');
  document.getElementById('ab-drain-type').value = '';
}

function submitAbilityRequest() {
  const name = document.getElementById('ab-name').value.trim();
  if (!name) return;
  const description = document.getElementById('ab-desc').value.trim();
  const drain_type  = document.getElementById('ab-drain-type').value || null;
  const drain_value = parseInt(document.getElementById('ab-drain-val').value) || 0;
  send('change_request', {
    req_type: 'ability',
    payload: { name, description, drain_type, drain_value }
  });
  showToast('Demande de capacite envoyee.');
  closeAbility();
}

let currentCastAbilityId = null;
function openCast(id) {
  // find ability by id in the DOM is tricky; re-fetch abilities if needed
  // We store them in a cache after renderAbilities
  currentCastAbilityId = id;
  fetch('/api/abilities').then(r => r.json()).then(abs => {
    const ab = abs.find(a => a.id === id);
    if (!ab) return;
    const div = document.getElementById('cast-content');
    div.innerHTML = `
      <h2>${escape_html(ab.name)}</h2>
      <p style="margin:0.5rem 0; color:var(--text-dim)">${drain_label(ab)}</p>
      <p style="margin:0.5rem 0; white-space:pre-wrap">${escape_html(ab.description || '')}</p>
    `;
    document.getElementById('cast-overlay').classList.remove('hidden');
  });
}
function closeCast() { document.getElementById('cast-overlay').classList.add('hidden'); }

// ── Inventory ─────────────────────────────────────────────────────────────────

let inventoryCache = {};

function renderInventory(items) {
  inventoryCache = {};
  const tbody = document.getElementById('inventory-body');
  tbody.innerHTML = '';
  items.forEach(item => {
    inventoryCache[item.id] = item;
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${escape_html(item.item_name)}</td>
      <td><input type="number" id="inv-qty-${item.id}" value="${item.amount}" min="1" style="width:55px"
        oninput="editItem(${item.id})"></td>
      <td><button class="small danger" onclick="removeItem(${item.id})">X</button></td>
    `;
    tbody.appendChild(tr);
  });
}

function editItem(id) {
  const item   = inventoryCache[id];
  const amount = parseInt(document.getElementById(`inv-qty-${id}`)?.value) || 1;
  if (!item) return;
  send('inventory_edit', { item_id: id, item_name: item.item_name, amount });
}

function addInventoryItem() {
  const name   = document.getElementById('new-item-name').value.trim();
  const amount = parseInt(document.getElementById('new-item-amount').value) || 1;
  if (!name) return;
  send('inventory_add', { item_name: name, amount });
  document.getElementById('new-item-name').value   = '';
  document.getElementById('new-item-amount').value = '1';
}

function removeItem(id) {
  send('inventory_remove', { item_id: id });
}

// ── Money ─────────────────────────────────────────────────────────────────────

function openMoney() {
  reset_money_inputs('money');
  document.getElementById('money-overlay').classList.remove('hidden');
}
function closeMoney() { document.getElementById('money-overlay').classList.add('hidden'); }

function submitMoneyTransfer() {
  const to     = parseInt(document.getElementById('money-to').value);
  const amount = read_money_inputs('money');
  if (!to || amount < 1) return;
  send('money_transfer', { to_character_id: to, amount });
  closeMoney();
}

// ── Notes ─────────────────────────────────────────────────────────────────────

async function openNotes() {
  const r = await fetch('/api/notes');
  const d = await r.json();
  document.getElementById('notes-area').value = d.content || '';
  document.getElementById('notes-overlay').classList.remove('hidden');
}
function closeNotes() { document.getElementById('notes-overlay').classList.add('hidden'); }

async function saveNotes() {
  const content = document.getElementById('notes-area').value;
  await fetch('/api/notes', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ content })
  });
  closeNotes();
}

// ── Edit request ──────────────────────────────────────────────────────────────

function openEdit() {
  if (!character) return;
  const fields = document.getElementById('edit-fields');
  fields.innerHTML = `
    <div class="form-row"><label>Nom</label><input id="ef-name" type="text" value="${escape_html(character.name || '')}"></div>
    <div class="form-row"><label>Sexe</label><input id="ef-sex" type="text" value="${escape_html(character.sex || '')}"></div>
    <div class="form-row"><label>Age</label><input id="ef-age" type="number" value="${character.age || ''}"></div>
    <div class="form-row"><label>Pouvoir 1</label><input id="ef-p1" type="text" value="${escape_html(character.power1 || '')}"></div>
    <div class="form-row"><label>Pouvoir 2</label><input id="ef-p2" type="text" value="${escape_html(character.power2 || '')}"></div>
    <div class="form-row"><label>Description</label><textarea id="ef-desc" rows="3">${escape_html(character.description || '')}</textarea></div>
    <div class="form-row"><label>Armes</label><input id="ef-weap" type="text" value="${escape_html(character.weapons || '')}"></div>
  `;
  document.getElementById('edit-overlay').classList.remove('hidden');
}
function closeEdit() { document.getElementById('edit-overlay').classList.add('hidden'); }

function submitEditRequest() {
  const payload = {
    name:        document.getElementById('ef-name').value.trim(),
    sex:         document.getElementById('ef-sex').value.trim(),
    age:         parseInt(document.getElementById('ef-age').value) || null,
    power1:      document.getElementById('ef-p1').value.trim(),
    power2:      document.getElementById('ef-p2').value.trim(),
    description: document.getElementById('ef-desc').value.trim(),
    weapons:     document.getElementById('ef-weap').value.trim(),
  };
  send('change_request', { req_type: 'profile', payload });
  showToast('Demande de modification envoyee.');
  closeEdit();
}

// ── Character creation ────────────────────────────────────────────────────────

async function submitCreateCharacter() {
  const name = document.getElementById('c-name').value.trim();
  if (!name) { document.getElementById('create-error').textContent = 'Le nom est requis.'; return; }

  const payload = {
    name,
    sex:         document.getElementById('c-sex').value.trim() || null,
    age:         parseInt(document.getElementById('c-age').value) || null,
    power1:      document.getElementById('c-p1').value.trim() || null,
    power2:      document.getElementById('c-p2').value.trim() || null,
    description: document.getElementById('c-desc').value.trim() || null,
    weapons:     document.getElementById('c-weap').value.trim() || null,
  };

  const r = await fetch('/api/character/create', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });

  if (!r.ok) {
    const d = await r.json();
    document.getElementById('create-error').textContent = d.error || 'Erreur';
    return;
  }

  character = await r.json();
  me.character_id = character.id;
  document.getElementById('create-overlay').classList.add('hidden');

  await loadAll();
  connectWs();
  document.getElementById('app').style.display = '';
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function buildResolvedMsg(data) {
  const actions = { approved: 'approuvee', rejected: 'rejetee', modified: 'modifiee' };
  const label = actions[data.action] || data.action;
  let msg = `Demande ${label}`;
  if (data.host_note) msg += ` : ${data.host_note}`;
  return msg;
}

let toastTimeout = null;
function showToast(msg, isError = false) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.style.borderColor = isError ? 'var(--red)' : 'var(--accent)';
  t.classList.remove('hidden');
  clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => t.classList.add('hidden'), 4000);
}

init();
