// Shared tuning constants. Server and client MUST agree exactly or prediction desyncs.

export const TICK_HZ = 30;
export const DT = 1 / TICK_HZ;
export const SNAPSHOT_EVERY = 1; // ticks between snapshots

export const PROTOCOL_VERSION = 4;

// ---- Character dimensions (metres) ----
export const P_RADIUS = 0.42;
export const P_HEIGHT = 1.45; // total capsule height, feet at pos.y

// ---- Movement ----
export const RUN_SPEED = 7.4;
export const GROUND_ACCEL = 62;
export const AIR_ACCEL = 26;
export const GROUND_DRAG = 11.5;
export const AIR_DRAG = 0.35;
export const GRAVITY = -27.5;
export const JUMP_VEL = 9.9;
export const MAX_FALL = -38;
export const COYOTE_TICKS = 5;
export const JUMP_BUFFER_TICKS = 6;
export const TURN_RATE = 14; // rad/s visual yaw lerp (sim-side, kept deterministic)

// ---- Dive ----
export const DIVE_FWD = 11.2;
export const DIVE_UP = 4.6;
export const DIVE_TICKS = 24; // how long you stay prone
export const DIVE_GET_UP_TICKS = 9;
export const DIVE_DRAG_GROUND = 4.2;
export const DIVE_COOLDOWN_TICKS = 16;

// ---- Tumble (knocked down) ----
export const TUMBLE_TICKS = 34;

// ---- Player vs player ----
export const PUSH_STRENGTH = 26;
export const DIVE_BONK_IMPULSE = 9.5;
export const BONK_MIN_SPEED = 5.0;

// ---- Ground detection ----
export const GROUND_NORMAL_Y = 0.55;
export const STEP_HEIGHT = 0.36;

// ---- Match flow ----
export const STATE_LOBBY = 0;
export const STATE_COUNTDOWN = 1;
export const STATE_PLAYING = 2;
export const STATE_ROUND_END = 3;
export const STATE_MATCH_END = 4;

export const LOBBY_COUNTDOWN_MS = 12000;
export const ROUND_INTRO_MS = 4200;
export const ROUND_END_MS = 5200;
export const MATCH_END_MS = 9000;

export const MAX_PLAYERS = 24;
export const TARGET_LOBBY_SIZE = 8;

// ---- Networking ----
export const INTERP_DELAY_MS = 110;
export const INPUT_SEND_HZ = 30;
