// Unified input: keyboard + mouse for desktop, dual-thumb touch for phones.
// Both produce the same {moveX, moveY, jump, dive, camYaw, camPitch} shape.

export class Input {
  constructor(canvas, hud) {
    this.canvas = canvas;
    this.keys = new Set();
    this.moveX = 0; this.moveY = 0;
    this.jumpQueued = false;
    this.diveQueued = false;
    this.jumpHeld = false;
    this.camYaw = Math.PI;
    this.camPitch = 0.28;
    this.zoom = 1;
    this.touch = /Android|iPhone|iPad|iPod|Mobile|Touch/i.test(navigator.userAgent) || 'ontouchstart' in window;
    this.pointerLocked = false;
    this.sensitivity = 0.0027;
    this.enabled = true;

    this._bindKeyboard();
    this._bindMouse();
    if (this.touch) this._bindTouch(hud);
  }

  _bindKeyboard() {
    addEventListener('keydown', (e) => {
      if (e.repeat) return;
      const k = e.code;
      this.keys.add(k);
      if (k === 'Space') { this.jumpQueued = true; this.jumpHeld = true; e.preventDefault(); }
      if (k === 'ShiftLeft' || k === 'ShiftRight' || k === 'KeyE' || k === 'ControlLeft') { this.diveQueued = true; e.preventDefault(); }
      if (k === 'Tab') e.preventDefault();
    });
    addEventListener('keyup', (e) => {
      this.keys.delete(e.code);
      if (e.code === 'Space') this.jumpHeld = false;
    });
    addEventListener('blur', () => { this.keys.clear(); this.jumpHeld = false; });
  }

  _bindMouse() {
    const c = this.canvas;
    let dragging = false;
    c.addEventListener('mousedown', (e) => {
      if (this.touch) return;
      dragging = true;
      if (!this.pointerLocked && e.button === 0) { try { const r = c.requestPointerLock?.(); if (r?.catch) r.catch(() => {}); } catch {} }
    });
    addEventListener('mouseup', () => { dragging = false; });
    document.addEventListener('pointerlockchange', () => {
      this.pointerLocked = document.pointerLockElement === c;
    });
    addEventListener('mousemove', (e) => {
      if (!this.enabled) return;
      if (this.pointerLocked) {
        this.camYaw -= e.movementX * this.sensitivity;
        this.camPitch = clamp(this.camPitch + e.movementY * this.sensitivity, -0.55, 1.15);
      } else if (dragging) {
        this.camYaw -= e.movementX * this.sensitivity * 1.4;
        this.camPitch = clamp(this.camPitch + e.movementY * this.sensitivity * 1.4, -0.55, 1.15);
      }
    });
    c.addEventListener('wheel', (e) => {
      this.zoom = clamp(this.zoom + e.deltaY * 0.0012, 0.6, 2.2);
      e.preventDefault();
    }, { passive: false });
    c.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  _bindTouch(hud) {
    const stick = hud.querySelector('#stick');
    const knob = hud.querySelector('#knob');
    const btnJump = hud.querySelector('#btn-jump');
    const btnDive = hud.querySelector('#btn-dive');
    hud.querySelector('#touch-controls').style.display = 'block';

    let stickId = null, sx = 0, sy = 0;
    const R = 62;

    const startStick = (t) => {
      stickId = t.identifier;
      const r = stick.getBoundingClientRect();
      sx = r.left + r.width / 2; sy = r.top + r.height / 2;
      moveStick(t);
    };
    const moveStick = (t) => {
      let dx = t.clientX - sx, dy = t.clientY - sy;
      const d = Math.hypot(dx, dy);
      if (d > R) { dx = (dx / d) * R; dy = (dy / d) * R; }
      knob.style.transform = `translate(${dx}px, ${dy}px)`;
      this.moveX = dx / R;
      this.moveY = dy / R;
    };
    const endStick = () => {
      stickId = null;
      knob.style.transform = 'translate(0px, 0px)';
      this.moveX = 0; this.moveY = 0;
    };

    stick.addEventListener('touchstart', (e) => { e.preventDefault(); startStick(e.changedTouches[0]); }, { passive: false });

    const lookTouches = new Map();
    const onStart = (e) => {
      for (const t of e.changedTouches) {
        const el = document.elementFromPoint(t.clientX, t.clientY);
        if (el && (el.closest('#stick') || el.closest('.tbtn'))) continue;
        if (t.clientX < innerWidth * 0.32 && t.clientY > innerHeight * 0.45 && stickId === null) { startStick(t); continue; }
        lookTouches.set(t.identifier, { x: t.clientX, y: t.clientY });
      }
    };
    const onMove = (e) => {
      for (const t of e.changedTouches) {
        if (t.identifier === stickId) { moveStick(t); e.preventDefault(); continue; }
        const p = lookTouches.get(t.identifier);
        if (!p) continue;
        this.camYaw -= (t.clientX - p.x) * 0.0062;
        this.camPitch = clamp(this.camPitch + (t.clientY - p.y) * 0.0052, -0.5, 1.1);
        p.x = t.clientX; p.y = t.clientY;
        e.preventDefault();
      }
    };
    const onEnd = (e) => {
      for (const t of e.changedTouches) {
        if (t.identifier === stickId) endStick();
        lookTouches.delete(t.identifier);
      }
    };
    addEventListener('touchstart', onStart, { passive: false });
    addEventListener('touchmove', onMove, { passive: false });
    addEventListener('touchend', onEnd);
    addEventListener('touchcancel', onEnd);

    const hook = (btn, fn) => {
      btn.addEventListener('touchstart', (e) => { e.preventDefault(); e.stopPropagation(); fn(); btn.classList.add('hit'); }, { passive: false });
      btn.addEventListener('touchend', (e) => { e.preventDefault(); btn.classList.remove('hit'); });
    };
    hook(btnJump, () => { this.jumpQueued = true; this.jumpHeld = true; setTimeout(() => { this.jumpHeld = false; }, 120); });
    hook(btnDive, () => { this.diveQueued = true; });
  }

  /** Read and clear one tick's worth of intent. */
  consume() {
    let mx = this.moveX, my = this.moveY;
    if (!this.touch) {
      mx = (this.keys.has('KeyD') || this.keys.has('ArrowRight') ? 1 : 0) - (this.keys.has('KeyA') || this.keys.has('ArrowLeft') ? 1 : 0);
      my = (this.keys.has('KeyS') || this.keys.has('ArrowDown') ? 1 : 0) - (this.keys.has('KeyW') || this.keys.has('ArrowUp') ? 1 : 0);
    }
    const jump = this.jumpQueued;
    const dive = this.diveQueued;
    this.jumpQueued = false;
    this.diveQueued = false;
    return { mx, my, jump, dive };
  }
}

const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
