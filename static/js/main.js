// Shared utilities used across pages

function copper_to_money(copper) {
  const plat   = Math.floor(copper / 1000000);
  const rest1  = copper % 1000000;
  const gold   = Math.floor(rest1 / 10000);
  const rest2  = rest1 % 10000;
  const silver = Math.floor(rest2 / 100);
  const cop    = rest2 % 100;
  return { plat, gold, silver, copper: cop, total: copper };
}

function render_money(copper, container) {
  const m = copper_to_money(copper);
  container.innerHTML = `
    <div class="money-cell plat"><div class="amount">${m.plat}</div><div class="denom">P</div></div>
    <div class="money-cell gold"><div class="amount">${m.gold}</div><div class="denom">O</div></div>
    <div class="money-cell silver"><div class="amount">${m.silver}</div><div class="denom">A</div></div>
    <div class="money-cell copper"><div class="amount">${m.copper}</div><div class="denom">C</div></div>
  `;
}

function money_inputs_to_copper(plat, gold, silver, copper) {
  return (plat * 1000000) + (gold * 10000) + (silver * 100) + copper;
}

function read_money_inputs(prefix) {
  const p = parseInt(document.getElementById(`${prefix}-plat`)?.value)   || 0;
  const o = parseInt(document.getElementById(`${prefix}-gold`)?.value)   || 0;
  const a = parseInt(document.getElementById(`${prefix}-silver`)?.value) || 0;
  const c = parseInt(document.getElementById(`${prefix}-copper`)?.value) || 0;
  return money_inputs_to_copper(p, o, a, c);
}

function reset_money_inputs(prefix) {
  ['plat','gold','silver','copper'].forEach(d => {
    const el = document.getElementById(`${prefix}-${d}`);
    if (el) el.value = '0';
  });
}

function flash_roll(el) {
  if (!el) return;
  const orig = el.style.color;
  el.style.transition = 'none';
  el.style.color = '#2ecc71';
  void el.offsetWidth; // force reflow so the green registers before transition kicks in
  el.style.transition = 'color 0.7s ease-out';
  el.style.color = orig;
}

function bar_width(curr, max) {
  if (!max) return 0;
  return Math.min(100, Math.round((curr / max) * 100));
}

function update_bar(bar_el, curr, max) {
  const fill = bar_el.querySelector('.bar-fill');
  const label = bar_el.querySelector('.bar-label span:last-child');
  if (fill) fill.style.width = bar_width(curr, max) + '%';
  if (label) label.textContent = `${curr} / ${max}`;
}

function format_mode(mode) {
  if (mode === 'HRP') return 'HRP: ';
  if (mode === '???') return '???: ';
  return '';
}

function chat_class(mode) {
  if (mode === 'HRP') return 'hrp';
  if (mode === '???') return 'lore';
  return 'rp';
}

function append_chat(log_el, sender, content, mode) {
  const div = document.createElement('div');
  div.className = `chat-msg ${chat_class(mode)}`;
  div.innerHTML = `<span class="chat-sender">${sender}</span> ${format_mode(mode)}${escape_html(content)}`;
  log_el.appendChild(div);
  log_el.scrollTop = log_el.scrollHeight;
}

function escape_html(str) {
  const d = document.createElement('div');
  d.textContent = str;
  return d.innerHTML;
}

async function logout() {
  await fetch('/auth/logout', { method: 'POST' });
  window.location.href = '/index.html';
}
