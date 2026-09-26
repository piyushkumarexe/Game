// Tiny synthesised SFX — zero assets, zero load time, still feels juicy.

export class Audio {
  constructor() {
    this.ctx = null;
    this.enabled = true;
    this.master = null;
  }

  init() {
    if (this.ctx) return;
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) { this.enabled = false; return; }
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = 0.32;
    // gentle limiter so overlapping hits don't clip
    const comp = this.ctx.createDynamicsCompressor();
    comp.threshold.value = -14; comp.ratio.value = 8; comp.attack.value = 0.003; comp.release.value = 0.2;
    this.master.connect(comp).connect(this.ctx.destination);
  }

  resume() { this.init(); if (this.ctx?.state === 'suspended') this.ctx.resume(); }

  _env(dur, peak = 1, attack = 0.005) {
    const g = this.ctx.createGain();
    const t = this.ctx.currentTime;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(peak, t + attack);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    g.connect(this.master);
    return g;
  }

  tone(freq, dur, type = 'sine', peak = 0.6, glide = 0) {
    if (!this.enabled || !this.ctx) return;
    const o = this.ctx.createOscillator();
    o.type = type;
    const t = this.ctx.currentTime;
    o.frequency.setValueAtTime(freq, t);
    if (glide) o.frequency.exponentialRampToValueAtTime(Math.max(30, freq * glide), t + dur);
    o.connect(this._env(dur, peak));
    o.start(t); o.stop(t + dur + 0.02);
  }

  noise(dur, peak = 0.4, filterFreq = 1200, q = 1) {
    if (!this.enabled || !this.ctx) return;
    const len = Math.max(1, Math.floor(this.ctx.sampleRate * dur));
    const buf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const d = buf.getChannelData(0);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / len);
    const s = this.ctx.createBufferSource();
    s.buffer = buf;
    const f = this.ctx.createBiquadFilter();
    f.type = 'bandpass'; f.frequency.value = filterFreq; f.Q.value = q;
    s.connect(f).connect(this._env(dur, peak, 0.002));
    s.start();
  }

  // ---- game sounds ----
  jump()   { this.tone(430, 0.16, 'triangle', 0.35, 1.9); }
  land(f)  { this.noise(0.13, 0.15 + f * 0.3, 260 + f * 220, 0.8); this.tone(120, 0.1, 'sine', 0.2 + f * 0.2, 0.6); }
  dive()   { this.noise(0.28, 0.2, 900, 0.6); this.tone(600, 0.2, 'sawtooth', 0.12, 0.35); }
  boing()  { this.tone(240, 0.3, 'sine', 0.42, 3.4); this.tone(360, 0.22, 'triangle', 0.18, 3.0); }
  bonk()   { this.tone(170, 0.2, 'square', 0.28, 0.45); this.noise(0.1, 0.24, 500, 0.9); }
  tumble() { this.tone(300, 0.25, 'sawtooth', 0.2, 0.32); this.noise(0.16, 0.2, 400, 0.7); }
  qualify(){ [523, 659, 784, 1046].forEach((f, i) => setTimeout(() => this.tone(f, 0.22, 'triangle', 0.3), i * 85)); }
  out()    { [392, 330, 262].forEach((f, i) => setTimeout(() => this.tone(f, 0.3, 'triangle', 0.26), i * 130)); }
  tick()   { this.tone(880, 0.07, 'square', 0.16); }
  go()     { this.tone(660, 0.12, 'square', 0.3); setTimeout(() => this.tone(990, 0.3, 'square', 0.32), 110); }
  win() {
    [523, 659, 784, 1046, 1318].forEach((f, i) => setTimeout(() => {
      this.tone(f, 0.45, 'triangle', 0.32);
      this.tone(f * 2, 0.3, 'sine', 0.12);
    }, i * 120));
    setTimeout(() => this.noise(1.6, 0.14, 3200, 0.4), 220);
  }
  click()  { this.tone(700, 0.06, 'square', 0.2); }
  emote()  { this.tone(880, 0.1, 'triangle', 0.24, 1.6); setTimeout(() => this.tone(1180, 0.12, 'triangle', 0.2), 80); }
}
