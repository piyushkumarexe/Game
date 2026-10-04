export class AudioBus {
  private context?: AudioContext;
  private master?: GainNode;
  private engine?: OscillatorNode;
  private engineGain?: GainNode;
  private muted = localStorage.getItem('dustbound-muted') === 'true';

  unlock(): void {
    if (!this.context) {
      this.context = new AudioContext();
      this.master = this.context.createGain();
      this.master.gain.value = this.muted ? 0 : 0.28;
      this.master.connect(this.context.destination);
    }
    if (this.context.state === 'suspended') void this.context.resume();
  }

  setMuted(value: boolean): void {
    this.muted = value;
    localStorage.setItem('dustbound-muted', String(value));
    if (this.master && this.context) {
      this.master.gain.setTargetAtTime(value ? 0 : 0.28, this.context.currentTime, 0.03);
    }
  }

  isMuted(): boolean {
    return this.muted;
  }

  startEngine(): void {
    this.unlock();
    if (!this.context || !this.master || this.engine) return;
    const oscillator = this.context.createOscillator();
    const gain = this.context.createGain();
    const filter = this.context.createBiquadFilter();
    oscillator.type = 'sawtooth';
    oscillator.frequency.value = 42;
    gain.gain.value = 0;
    filter.type = 'lowpass';
    filter.frequency.value = 210;
    oscillator.connect(filter);
    filter.connect(gain);
    gain.connect(this.master);
    oscillator.start();
    this.engine = oscillator;
    this.engineGain = gain;
  }

  updateEngine(speed: number, throttle: number): void {
    if (!this.context || !this.engine || !this.engineGain) return;
    const now = this.context.currentTime;
    const targetHz = 40 + Math.abs(speed) * 0.7 + throttle * 40;
    this.engine.frequency.setTargetAtTime(targetHz, now, 0.07);
    this.engineGain.gain.setTargetAtTime(0.045 + throttle * 0.06, now, 0.08);
  }

  stopEngine(): void {
    if (!this.context || !this.engine || !this.engineGain) return;
    const engine = this.engine;
    const gain = this.engineGain;
    gain.gain.setTargetAtTime(0, this.context.currentTime, 0.08);
    window.setTimeout(() => {
      try { engine.stop(); } catch { /* already stopped */ }
      engine.disconnect();
      gain.disconnect();
    }, 300);
    this.engine = undefined;
    this.engineGain = undefined;
  }

  pickup(): void {
    this.tone(520, 0.06, 'sine', 0.16, 1.45);
    window.setTimeout(() => this.tone(760, 0.09, 'sine', 0.12, 1.15), 55);
  }

  click(): void {
    this.tone(240, 0.035, 'square', 0.08, 0.85);
  }

  checkpoint(): void {
    this.tone(330, 0.12, 'triangle', 0.13, 1.5);
    window.setTimeout(() => this.tone(495, 0.15, 'triangle', 0.13, 1.35), 100);
    window.setTimeout(() => this.tone(660, 0.2, 'triangle', 0.11, 1), 190);
  }

  winch(): void {
    this.noise(0.34, 0.12);
    this.tone(95, 0.34, 'sawtooth', 0.1, 1.8);
  }

  crash(intensity = 1): void {
    this.noise(0.16 + intensity * 0.1, 0.11 * intensity);
    this.tone(72, 0.18, 'square', 0.08 * intensity, 0.45);
  }

  private tone(frequency: number, duration: number, type: OscillatorType, volume: number, endRatio: number): void {
    this.unlock();
    if (!this.context || !this.master) return;
    const now = this.context.currentTime;
    const oscillator = this.context.createOscillator();
    const gain = this.context.createGain();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, now);
    oscillator.frequency.exponentialRampToValueAtTime(Math.max(20, frequency * endRatio), now + duration);
    gain.gain.setValueAtTime(volume, now);
    gain.gain.exponentialRampToValueAtTime(0.001, now + duration);
    oscillator.connect(gain);
    gain.connect(this.master);
    oscillator.start(now);
    oscillator.stop(now + duration + 0.02);
  }

  private noise(duration: number, volume: number): void {
    this.unlock();
    if (!this.context || !this.master) return;
    const frameCount = Math.floor(this.context.sampleRate * duration);
    const buffer = this.context.createBuffer(1, frameCount, this.context.sampleRate);
    const channel = buffer.getChannelData(0);
    for (let i = 0; i < frameCount; i += 1) channel[i] = Math.random() * 2 - 1;
    const source = this.context.createBufferSource();
    const filter = this.context.createBiquadFilter();
    const gain = this.context.createGain();
    filter.type = 'lowpass';
    filter.frequency.value = 650;
    gain.gain.setValueAtTime(volume, this.context.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, this.context.currentTime + duration);
    source.buffer = buffer;
    source.connect(filter);
    filter.connect(gain);
    gain.connect(this.master);
    source.start();
  }
}

export const audioBus = new AudioBus();
