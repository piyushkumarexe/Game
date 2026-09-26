const $ = (s) => document.querySelector(s);

export class HUD {
  constructor() {
    this.el = {
      hud: $('#hud'),
      roundNum: $('#round-num'),
      roundName: $('#round-name'),
      qHave: $('#q-have'),
      qNeed: $('#q-need'),
      qBar: $('#qualify-bar i'),
      qualifyBox: $('#qualify-box'),
      alive: $('#alive-count'),
      standings: $('#standings'),
      center: $('#center-msg'),
      sub: $('#sub-msg'),
      toasts: $('#toasts'),
      fps: $('#fps'),
      ping: $('#ping'),
      results: $('#results'),
      resTitle: $('#res-title'),
      resQ: $('#res-q'),
      resO: $('#res-o'),
      resNext: $('#res-next'),
      winner: $('#winner'),
      winName: $('#win-name'),
      winSub: $('#win-sub'),
      winNext: $('#win-next'),
      menu: $('#menu'),
      conn: $('#conn-state'),
      loading: $('#loading'),
    };
    this._msgTimer = 0;
    this._lastStandings = '';
  }

  show() { this.el.hud.classList.remove('hidden'); }
  hideMenu() { this.el.menu.style.display = 'none'; }
  showMenu() { this.el.menu.style.display = 'flex'; }
  hideLoading() {
    this.el.loading.style.opacity = '0';
    setTimeout(() => this.el.loading.classList.add('hidden'), 420);
  }

  setConn(text, cls) {
    this.el.conn.textContent = text;
    this.el.conn.className = cls || '';
  }

  setRound(idx, total, name) {
    this.el.roundNum.textContent = idx >= 0 ? `ROUND ${idx + 1} / ${total}` : 'WARM-UP';
    this.el.roundName.textContent = name;
  }

  setQualify(have, need, mode) {
    this.el.qualifyBox.style.display = need > 0 ? '' : 'none';
    this.el.qHave.textContent = have;
    this.el.qNeed.textContent = need;
    this.el.qBar.style.width = `${Math.min(100, (have / Math.max(1, need)) * 100)}%`;
    this.el.qualifyBox.querySelector('#qualify-label').textContent =
      mode === 'survive' ? 'SURVIVORS LEFT' : mode === 'crown' ? 'FINAL' : 'QUALIFIED';
  }

  setAlive(n) { this.el.alive.textContent = n; }

  setStandings(rows) {
    const key = rows.map((r) => `${r.id}${r.status}${r.place}${r.you ? 1 : 0}`).join('|');
    if (key === this._lastStandings) return;
    this._lastStandings = key;
    this.el.standings.innerHTML = rows.map((r) => {
      const cls = ['srow'];
      if (r.you) cls.push('you');
      if (r.status === 2) cls.push('q');
      if (r.status === 3) cls.push('out');
      const hex = '#' + r.color.toString(16).padStart(6, '0');
      const badge = r.status === 2 ? `#${r.place}` : r.status === 3 ? 'OUT' : (r.place ? `#${r.place}` : '');
      return `<div class="${cls.join(' ')}"><i class="dot" style="background:${hex}"></i>
        <span class="nm">${esc(r.name)}</span>${r.bot ? '<span class="bot">CPU</span>' : ''}
        <span class="pl">${badge}</span></div>`;
    }).join('');
  }

  big(text, sub = '', color = '#fff') {
    const c = this.el.center, s = this.el.sub;
    c.style.opacity = ''; s.style.opacity = '';
    c.textContent = text;
    c.style.color = color;
    c.classList.remove('pop', 'fade');
    void c.offsetWidth;
    c.classList.add('pop');
    s.textContent = sub;
    s.classList.remove('pop', 'fade');
    void s.offsetWidth;
    if (sub) s.classList.add('pop');
    clearTimeout(this._msgTimer);
    this._msgTimer = setTimeout(() => {
      c.classList.remove('pop'); c.classList.add('fade');
      s.classList.remove('pop'); s.classList.add('fade');
    }, 1600);
  }

  bigPersist(text, color = '#fff') {
    const c = this.el.center, s = this.el.sub;
    clearTimeout(this._msgTimer);
    c.textContent = text;
    c.style.color = color;
    c.classList.remove('fade', 'pop');
    s.classList.remove('fade', 'pop');
    c.style.opacity = '1';
    s.style.opacity = '1';
  }

  clearBig() {
    clearTimeout(this._msgTimer);
    this.el.center.style.opacity = '';
    this.el.sub.style.opacity = '';
    this.el.center.classList.remove('pop');
    this.el.center.classList.add('fade');
    this.el.sub.classList.remove('pop');
    this.el.sub.classList.add('fade');
  }

  toast(text, kind = '') {
    const d = document.createElement('div');
    d.className = 'toast ' + kind;
    d.innerHTML = text;
    this.el.toasts.appendChild(d);
    while (this.el.toasts.children.length > 5) this.el.toasts.firstChild.remove();
    setTimeout(() => {
      d.style.transition = 'opacity .4s, transform .4s';
      d.style.opacity = '0';
      d.style.transform = 'translateX(-20px)';
      setTimeout(() => d.remove(), 420);
    }, 3600);
  }

  showResults(res, selfId) {
    if (!res) return;
    const li = (p, dim) => {
      const hex = '#' + p.color.toString(16).padStart(6, '0');
      return `<li class="${dim ? 'dim' : ''}"><i class="dot" style="background:${hex}"></i>
        ${esc(p.name)}${p.id === selfId ? ' <b>(you)</b>' : ''}${p.place ? ` <span style="margin-left:auto;opacity:.6">#${p.place}</span>` : ''}</li>`;
    };
    this.el.resQ.innerHTML = (res.qualified || []).map((p) => li(p, false)).join('') || '<li class="dim">nobody</li>';
    this.el.resO.innerHTML = (res.out || []).map((p) => li(p, true)).join('') || '<li class="dim">nobody</li>';
    const you = (res.qualified || []).some((p) => p.id === selfId);
    this.el.resTitle.textContent = you ? 'YOU QUALIFIED!' : ((res.out || []).some((p) => p.id === selfId) ? 'ELIMINATED' : 'ROUND COMPLETE');
    this.el.resTitle.style.color = you ? '#3ee08b' : '#fff';
    this.el.results.classList.remove('hidden');
  }

  hideResults() { this.el.results.classList.add('hidden'); }

  showWinner(name, isYou, color) {
    this.el.winName.textContent = isYou ? 'YOU WIN!' : `${name} WINS!`;
    this.el.winSub.textContent = isYou ? 'Absolute legend. Crown secured.' : 'Better luck next round…';
    this.el.winner.classList.remove('hidden');
  }

  hideWinner() { this.el.winner.classList.add('hidden'); }

  countdown(el, secs) { el.querySelector('b').textContent = Math.max(0, Math.ceil(secs)); }

  setStats(fps, ping) {
    this.el.fps.textContent = fps | 0;
    this.el.ping.textContent = ping | 0;
  }
}

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
}
