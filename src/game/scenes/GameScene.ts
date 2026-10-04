import Phaser from 'phaser';
import { COLORS, FONT_BODY, FONT_HEAD, GAME_HEIGHT, GAME_WIDTH, ROUTE_LENGTH, type RunResult } from '../constants';
import { audioBus } from '../systems/AudioBus';
import { vibrate } from '../systems/NativeShell';
import { biomeAt, buildTerrainPoints, routeNameAt, terrainHeight, terrainSlope } from '../systems/Terrain';

type PickupType = 'fuel' | 'scrap';
type Pickup = { x: number; type: PickupType; sprite: Phaser.GameObjects.Image; collected: boolean };
type Obstacle = { x: number; sprite: Phaser.GameObjects.Image; hit: boolean };
type ControlName = 'gas' | 'brake' | 'left' | 'right';
type ControlState = Record<ControlName, boolean>;
type KeyMap = Record<'W' | 'A' | 'S' | 'D' | 'UP' | 'LEFT' | 'DOWN' | 'RIGHT' | 'SPACE' | 'P', Phaser.Input.Keyboard.Key>;

export class GameScene extends Phaser.Scene {
  private vehicle!: Phaser.GameObjects.Container;
  private frontWheel!: Phaser.GameObjects.Container;
  private rearWheel!: Phaser.GameObjects.Container;
  private cableGraphics!: Phaser.GameObjects.Graphics;
  private sky!: Phaser.GameObjects.Rectangle;
  private routeLabel!: Phaser.GameObjects.Text;
  private objectiveLabel!: Phaser.GameObjects.Text;
  private speedLabel!: Phaser.GameObjects.Text;
  private scrapLabel!: Phaser.GameObjects.Text;
  private progressFill!: Phaser.GameObjects.Rectangle;
  private healthFill!: Phaser.GameObjects.Rectangle;
  private fuelFill!: Phaser.GameObjects.Rectangle;
  private winchFill!: Phaser.GameObjects.Rectangle;
  private winchLabel!: Phaser.GameObjects.Text;
  private patchLabel!: Phaser.GameObjects.Text;
  private toastContainer!: Phaser.GameObjects.Container;
  private toastTitle!: Phaser.GameObjects.Text;
  private toastCopy!: Phaser.GameObjects.Text;
  private keys!: KeyMap;

  private x = 260;
  private y = 440;
  private velocityX = 0;
  private velocityY = 0;
  private rotation = 0;
  private angularVelocity = 0;
  private wheelRotation = 0;
  private fuel = 100;
  private health = 100;
  private scrap = 0;
  private elapsed = 0;
  private grounded = true;
  private lastDust = 0;
  private lastDamageAt = -10;
  private lastRoute = '';
  private nextCheckpoint = 0;
  private winchCooldown = 0;
  private winchTimer = 0;
  private runEnded = false;
  private paused = false;
  private controls: ControlState = { gas: false, brake: false, left: false, right: false };
  private pickups: Pickup[] = [];
  private obstacles: Obstacle[] = [];
  private checkpoints = [4_720, 9_620];
  private scenery: Phaser.GameObjects.Image[] = [];

  constructor() {
    super('GameScene');
  }

  create(): void {
    this.resetRun();
    this.drawWorld();
    this.createPickupsAndHazards();
    this.createVehicle();
    this.createHud();
    this.createControls();
    this.bindKeys();

    this.cameras.main.setBounds(0, 0, ROUTE_LENGTH + 900, GAME_HEIGHT);
    this.cameras.main.startFollow(this.vehicle, true, 0.085, 0.12, -250, 52);
    this.cameras.main.setDeadzone(180, 70);
    this.cameras.main.fadeIn(300, 23, 26, 37);

    audioBus.startEngine();
    this.showToast('SUNDOWN WASH', 'Hold DRIVE and keep the old rig level.', 2800);
    this.input.on('pointerdown', () => audioBus.unlock());
    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => audioBus.stopEngine());
  }

  update(time: number, rawDelta: number): void {
    if (this.paused || this.runEnded) return;
    const delta = Math.min(rawDelta / 1000, 0.034);
    this.elapsed += delta;
    this.readKeyboard();
    this.simulateVehicle(delta);
    this.updateVehicleVisuals();
    this.updateCollectibles(time);
    this.updateHud();
    this.updateAtmosphere();
    this.checkRouteEvents();
    this.checkEndState();
  }

  private resetRun(): void {
    this.x = 260;
    this.y = terrainHeight(this.x) - 68;
    this.velocityX = 0;
    this.velocityY = 0;
    this.rotation = terrainSlope(this.x);
    this.angularVelocity = 0;
    this.fuel = 100;
    this.health = 100;
    this.scrap = 0;
    this.elapsed = 0;
    this.nextCheckpoint = 0;
    this.winchCooldown = 0;
    this.winchTimer = 0;
    this.runEnded = false;
    this.paused = false;
    this.lastRoute = '';
    this.pickups = [];
    this.obstacles = [];
    this.scenery = [];
    this.controls = { gas: false, brake: false, left: false, right: false };
  }

  private drawWorld(): void {
    this.sky = this.add.rectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, 0x7597a3).setOrigin(0).setScrollFactor(0).setDepth(-20);
    this.add.circle(1040, 132, 54, 0xf4c875, 0.8).setScrollFactor(0).setDepth(-19);

    const clouds = this.add.container(0, 0).setScrollFactor(0.08).setDepth(-17);
    for (let i = 0; i < 12; i += 1) {
      clouds.add(this.add.image(i * 520 + 90, 85 + (i % 3) * 58, 'cloud').setScale(0.45 + (i % 4) * 0.11).setAlpha(0.35));
    }

    const far = this.add.graphics().setScrollFactor(0.12).setDepth(-15);
    far.fillStyle(0x686a69, 0.72);
    const farPoints = [new Phaser.Math.Vector2(-500, 560)];
    for (let x = -500; x <= 4_700; x += 170) {
      farPoints.push(new Phaser.Math.Vector2(x, 330 + Math.sin(x * 0.0061) * 62 + Math.sin(x * 0.013) * 31));
    }
    farPoints.push(new Phaser.Math.Vector2(4_700, 720), new Phaser.Math.Vector2(-500, 720));
    far.fillPoints(farPoints, true);

    const mid = this.add.graphics().setScrollFactor(0.28).setDepth(-13);
    mid.fillStyle(0x505655, 0.88);
    const midPoints = [new Phaser.Math.Vector2(-400, 620)];
    for (let x = -400; x <= 8_200; x += 130) {
      midPoints.push(new Phaser.Math.Vector2(x, 405 + Math.sin(x * 0.0048 + 1) * 53 + Math.sin(x * 0.011) * 20));
    }
    midPoints.push(new Phaser.Math.Vector2(8_200, 720), new Phaser.Math.Vector2(-400, 720));
    mid.fillPoints(midPoints, true);

    const terrainPoints = buildTerrainPoints();
    const ground = this.add.graphics().setDepth(-3);
    const fillPoints = [...terrainPoints, new Phaser.Math.Vector2(ROUTE_LENGTH + 1_100, 760), new Phaser.Math.Vector2(-400, 760)];
    ground.fillStyle(0x5e453b).fillPoints(fillPoints, true);
    ground.lineStyle(24, 0x8b664d, 1).strokePoints(terrainPoints, false);
    ground.lineStyle(5, 0xc19368, 1).strokePoints(terrainPoints, false);

    // Layered soil makes the route feel hand cut rather than a flat polygon.
    const strata = this.add.graphics().setDepth(-2);
    strata.lineStyle(4, 0x3c3030, 0.32);
    for (let x = 0; x < ROUTE_LENGTH; x += 300) {
      const y = terrainHeight(x) + 43 + (x % 4) * 4;
      strata.beginPath().moveTo(x, y).lineTo(x + 185, y + Math.sin(x) * 7).strokePath();
    }

    this.placeScenery();

    this.checkpoints.forEach((x) => {
      this.add.image(x, terrainHeight(x) - 62, 'camp-flag').setOrigin(0.5, 1).setDepth(-1);
      const ring = this.add.ellipse(x, terrainHeight(x) - 12, 250, 38, COLORS.teal, 0.12).setDepth(-1);
      this.tweens.add({ targets: ring, scaleX: 1.25, alpha: 0.02, duration: 1300, yoyo: true, repeat: -1 });
    });

    const finish = this.add.graphics().setDepth(-1);
    const finishY = terrainHeight(ROUTE_LENGTH);
    finish.fillStyle(0x2f2928).fillRect(ROUTE_LENGTH - 10, finishY - 210, 14, 210);
    finish.fillStyle(COLORS.orange).fillTriangle(ROUTE_LENGTH + 4, finishY - 207, ROUTE_LENGTH + 126, finishY - 171, ROUTE_LENGTH + 4, finishY - 136);
    this.add.text(ROUTE_LENGTH + 17, finishY - 190, 'HOME', {
      fontFamily: FONT_HEAD, fontSize: '24px', fontStyle: '800', color: '#fff4da'
    }).setRotation(0.27).setDepth(0);
  }

  private placeScenery(): void {
    for (let x = 620; x < ROUTE_LENGTH; x += 235) {
      const biome = biomeAt(x);
      const jitter = Math.sin(x * 12.43) * 64;
      const px = x + jitter;
      if (biome === 'pine') {
        const tree = this.add.image(px, terrainHeight(px) + 6, 'pine').setOrigin(0.5, 1).setScale(0.55 + ((x / 235) % 3) * 0.11).setDepth(-4);
        tree.setTint(x % 470 === 0 ? 0x89a279 : 0xffffff);
        this.scenery.push(tree);
      } else if (x % 470 < 236) {
        const cactus = this.add.image(px, terrainHeight(px) + 2, 'cactus').setOrigin(0.5, 1).setScale(0.52 + ((x / 235) % 2) * 0.13).setDepth(-4);
        if (biome === 'badlands') cactus.setTint(0x9e8565);
        this.scenery.push(cactus);
      }
    }
    [920, 3_760, 5_090, 7_860, 10_520, 12_880].forEach((x) => {
      this.add.image(x, terrainHeight(x) - 3, 'route-sign').setOrigin(0.5, 1).setScale(0.67).setDepth(-1);
    });
  }

  private createPickupsAndHazards(): void {
    const fuelPositions = [1_720, 3_790, 6_080, 8_430, 10_780, 12_950];
    const scrapPositions = [920, 2_430, 3_250, 5_180, 6_950, 7_760, 9_360, 10_140, 11_650, 13_520];
    fuelPositions.forEach((x) => this.addPickup(x, 'fuel'));
    scrapPositions.forEach((x) => this.addPickup(x, 'scrap'));

    [2_060, 3_470, 4_230, 5_680, 7_320, 8_880, 10_020, 11_230, 12_570, 13_720].forEach((x, index) => {
      const scale = 0.38 + (index % 3) * 0.08;
      const sprite = this.add.image(x, terrainHeight(x) + 1, 'boulder').setOrigin(0.5, 1).setScale(scale).setDepth(-1);
      this.obstacles.push({ x, sprite, hit: false });
    });
  }

  private addPickup(x: number, type: PickupType): void {
    const sprite = this.add.image(x, terrainHeight(x) - 74, type).setScale(type === 'fuel' ? 0.55 : 0.46).setDepth(1);
    this.pickups.push({ x, type, sprite, collected: false });
    this.tweens.add({ targets: sprite, y: sprite.y - 11, duration: 850 + (x % 300), yoyo: true, repeat: -1, ease: 'Sine.inOut' });
  }

  private createVehicle(): void {
    this.vehicle = this.add.container(this.x, this.y).setDepth(4);
    const shadow = this.add.ellipse(0, 65, 210, 28, 0x171a25, 0.22);
    const body = this.add.graphics();
    body.fillStyle(0xe6dfc7).fillRoundedRect(-118, -66, 220, 111, 15);
    body.fillStyle(COLORS.rust).fillRoundedRect(-118, 17, 220, 25, 2);
    body.fillStyle(0x40575c).fillRoundedRect(27, -51, 58, 42, 6);
    body.fillStyle(0x5f7a7c).fillRoundedRect(-91, -49, 49, 38, 5).fillRoundedRect(-31, -49, 44, 38, 5);
    body.fillStyle(0x303338).fillRoundedRect(-28, -2, 45, 14, 4);
    body.fillStyle(COLORS.orange).fillCircle(100, 23, 7);
    body.fillStyle(0xffffff, 0.26).fillTriangle(34, -46, 80, -46, 80, -15);
    body.lineStyle(5, 0x37383a).strokeRoundedRect(-118, -66, 220, 111, 15);
    body.lineBetween(-112, -1, 97, -1);

    const roof = this.add.graphics();
    roof.fillStyle(0x6f4635).fillRoundedRect(-62, -87, 61, 21, 5);
    roof.fillStyle(0x2f4c48).fillRoundedRect(7, -83, 47, 17, 4);
    roof.lineStyle(4, 0x383433).lineBetween(-74, -66, 68, -66);

    this.rearWheel = this.createWheel(-70, 43);
    this.frontWheel = this.createWheel(66, 43);
    this.vehicle.add([shadow, body, roof, this.rearWheel, this.frontWheel]);

    this.cableGraphics = this.add.graphics().setDepth(3);
  }

  private createWheel(x: number, y: number): Phaser.GameObjects.Container {
    const tire = this.add.graphics();
    tire.fillStyle(0x191b1f).fillCircle(0, 0, 27);
    tire.lineStyle(5, 0x4a4844).strokeCircle(0, 0, 19);
    tire.fillStyle(0xbebaa9).fillCircle(0, 0, 10);
    tire.lineStyle(3, 0x5b5a57);
    tire.lineBetween(-18, 0, 18, 0).lineBetween(0, -18, 0, 18);
    return this.add.container(x, y, [tire]);
  }

  private createHud(): void {
    const hud = this.add.container(0, 0).setScrollFactor(0).setDepth(30);
    const top = this.add.graphics();
    top.fillStyle(0x12151c, 0.82).fillRoundedRect(24, 20, 458, 86, 17);
    top.fillStyle(0x12151c, 0.82).fillRoundedRect(500, 20, 328, 60, 17);
    top.fillStyle(0x12151c, 0.82).fillRoundedRect(846, 20, 410, 60, 17);
    top.lineStyle(2, 0xffffff, 0.08).strokeRoundedRect(24, 20, 458, 86, 17);
    hud.add(top);

    hud.add(this.add.text(46, 33, 'RIG', { fontFamily: FONT_HEAD, fontSize: '15px', fontStyle: '800', color: '#d9cdb6' }));
    hud.add(this.add.text(46, 69, 'FUEL', { fontFamily: FONT_HEAD, fontSize: '15px', fontStyle: '800', color: '#d9cdb6' }));
    hud.add(this.add.rectangle(98, 42, 215, 14, 0x3e4145).setOrigin(0, 0.5));
    this.healthFill = this.add.rectangle(98, 42, 215, 14, COLORS.success).setOrigin(0, 0.5);
    hud.add(this.healthFill);
    hud.add(this.add.rectangle(98, 78, 215, 14, 0x3e4145).setOrigin(0, 0.5));
    this.fuelFill = this.add.rectangle(98, 78, 215, 14, COLORS.orange).setOrigin(0, 0.5);
    hud.add(this.fuelFill);
    this.speedLabel = this.add.text(454, 61, '0', { fontFamily: FONT_HEAD, fontSize: '35px', fontStyle: '800', color: '#fff4da' }).setOrigin(1, 0.5);
    hud.add(this.speedLabel);
    hud.add(this.add.text(456, 84, 'MPH', { fontFamily: FONT_HEAD, fontSize: '11px', fontStyle: '800', color: '#d9cdb6' }).setOrigin(1, 0.5));

    this.routeLabel = this.add.text(520, 30, 'SUNDOWN WASH', { fontFamily: FONT_HEAD, fontSize: '20px', fontStyle: '800', color: '#fff4da', letterSpacing: 1 });
    this.objectiveLabel = this.add.text(520, 55, 'CAMP  4.4 KM', { fontFamily: FONT_BODY, fontSize: '11px', fontStyle: '800', color: '#9faaa5', letterSpacing: 1 });
    hud.add([this.routeLabel, this.objectiveLabel]);

    hud.add(this.add.text(866, 31, 'HOME', { fontFamily: FONT_HEAD, fontSize: '15px', fontStyle: '800', color: '#d9cdb6' }));
    hud.add(this.add.rectangle(922, 43, 213, 11, 0x3e4145).setOrigin(0, 0.5));
    this.progressFill = this.add.rectangle(922, 43, 1, 11, COLORS.teal).setOrigin(0, 0.5);
    hud.add(this.progressFill);
    this.scrapLabel = this.add.text(1165, 30, '⚙ 0', { fontFamily: FONT_HEAD, fontSize: '22px', fontStyle: '800', color: '#fff4da' });
    hud.add(this.scrapLabel);

    const pause = this.add.container(1224, 99).setSize(46, 46).setInteractive({ useHandCursor: true });
    const pauseBg = this.add.circle(0, 0, 23, 0x171a25, 0.76).setStrokeStyle(2, 0xffffff, 0.15);
    const pauseIcon = this.add.graphics().fillStyle(0xfff4da).fillRoundedRect(-8, -10, 5, 20, 2).fillRoundedRect(3, -10, 5, 20, 2);
    pause.add([pauseBg, pauseIcon]).on('pointerdown', () => this.togglePause());
    hud.add(pause);

    this.toastContainer = this.add.container(GAME_WIDTH / 2, 142).setScrollFactor(0).setDepth(35).setAlpha(0);
    const toastBg = this.add.graphics().fillStyle(0x171a25, 0.86).fillRoundedRect(-220, -36, 440, 74, 16);
    toastBg.lineStyle(2, COLORS.orange, 0.75).strokeRoundedRect(-220, -36, 440, 74, 16);
    this.toastTitle = this.add.text(0, -22, '', { fontFamily: FONT_HEAD, fontSize: '23px', fontStyle: '800', color: '#fff4da', letterSpacing: 1 }).setOrigin(0.5, 0);
    this.toastCopy = this.add.text(0, 7, '', { fontFamily: FONT_BODY, fontSize: '12px', fontStyle: '800', color: '#d8cbb4' }).setOrigin(0.5, 0);
    this.toastContainer.add([toastBg, this.toastTitle, this.toastCopy]);
  }

  private createControls(): void {
    this.makeHoldControl(84, 610, 72, '↶', 'TILT', COLORS.teal, 'left');
    this.makeHoldControl(236, 610, 72, '↷', 'TILT', COLORS.teal, 'right');
    this.makeActionControl(690, 625, 64, 'PATCH', COLORS.rust, () => this.patchRig(), (label) => { this.patchLabel = label; });
    this.makeActionControl(824, 625, 64, 'CABLE', 0x6b7476, () => this.startWinch(), (label, fill) => {
      this.winchLabel = label;
      this.winchFill = fill;
    });
    this.makeHoldControl(1000, 610, 76, '■', 'BRAKE', 0x596068, 'brake');
    this.makeHoldControl(1164, 600, 91, '▶', 'DRIVE', COLORS.orange, 'gas');
  }

  private makeHoldControl(x: number, y: number, radius: number, icon: string, copy: string, color: number, control: ControlName): void {
    const bg = this.add.circle(0, 0, radius, 0x11141a, 0.55).setStrokeStyle(3, 0xffffff, 0.12);
    const inner = this.add.circle(0, 0, radius - 9, color, 0.9);
    const iconText = this.add.text(0, -10, icon, { fontFamily: FONT_HEAD, fontSize: `${radius * 0.62}px`, fontStyle: '800', color: '#fff9e8' }).setOrigin(0.5);
    const label = this.add.text(0, radius * 0.48, copy, { fontFamily: FONT_HEAD, fontSize: '13px', fontStyle: '800', color: '#fff9e8', letterSpacing: 1 }).setOrigin(0.5);
    const button = this.add.container(x, y, [bg, inner, iconText, label]).setSize(radius * 2, radius * 2).setScrollFactor(0).setDepth(40).setInteractive();
    let activePointerId: number | undefined;
    const release = (pointer?: Phaser.Input.Pointer): void => {
      if (pointer && activePointerId !== pointer.id) return;
      activePointerId = undefined;
      this.controls[control] = false;
      button.setScale(1);
      inner.setAlpha(0.9);
    };
    button.on('pointerdown', (pointer: Phaser.Input.Pointer) => {
      pointer.event.preventDefault();
      activePointerId = pointer.id;
      this.controls[control] = true;
      button.setScale(0.94);
      inner.setAlpha(1);
      audioBus.unlock();
    });
    button.on('pointerup', release).on('pointerout', release);
    this.input.on('pointerup', release);
  }

  private makeActionControl(
    x: number,
    y: number,
    radius: number,
    copy: string,
    color: number,
    action: () => void,
    expose: (label: Phaser.GameObjects.Text, fill: Phaser.GameObjects.Rectangle) => void
  ): void {
    const bg = this.add.circle(0, 0, radius, 0x11141a, 0.64).setStrokeStyle(3, 0xffffff, 0.12);
    const fill = this.add.rectangle(-radius + 8, radius - 15, (radius - 8) * 2, 7, COLORS.orange).setOrigin(0, 0.5);
    const icon = copy === 'CABLE' ? '⌁' : '+';
    const iconText = this.add.text(0, -10, icon, { fontFamily: FONT_HEAD, fontSize: '42px', fontStyle: '800', color: '#fff9e8' }).setOrigin(0.5);
    const label = this.add.text(0, 28, copy, { fontFamily: FONT_HEAD, fontSize: '13px', fontStyle: '800', color: '#fff9e8', letterSpacing: 1 }).setOrigin(0.5);
    const button = this.add.container(x, y, [bg, this.add.circle(0, 0, radius - 9, color, 0.92), iconText, label, fill])
      .setSize(radius * 2, radius * 2).setScrollFactor(0).setDepth(40).setInteractive();
    button.on('pointerdown', () => {
      button.setScale(0.93);
      action();
    });
    button.on('pointerup', () => button.setScale(1)).on('pointerout', () => button.setScale(1));
    expose(label, fill);
  }

  private bindKeys(): void {
    this.keys = this.input.keyboard!.addKeys({
      W: Phaser.Input.Keyboard.KeyCodes.W,
      A: Phaser.Input.Keyboard.KeyCodes.A,
      S: Phaser.Input.Keyboard.KeyCodes.S,
      D: Phaser.Input.Keyboard.KeyCodes.D,
      UP: Phaser.Input.Keyboard.KeyCodes.UP,
      LEFT: Phaser.Input.Keyboard.KeyCodes.LEFT,
      DOWN: Phaser.Input.Keyboard.KeyCodes.DOWN,
      RIGHT: Phaser.Input.Keyboard.KeyCodes.RIGHT,
      SPACE: Phaser.Input.Keyboard.KeyCodes.SPACE,
      P: Phaser.Input.Keyboard.KeyCodes.P
    }) as KeyMap;
  }

  private readKeyboard(): void {
    if (Phaser.Input.Keyboard.JustDown(this.keys.SPACE)) this.startWinch();
    if (Phaser.Input.Keyboard.JustDown(this.keys.P)) this.togglePause();
  }

  private simulateVehicle(delta: number): void {
    const leftSurface = terrainHeight(this.x - 66);
    const rightSurface = terrainHeight(this.x + 66);
    const targetY = (leftSurface + rightSurface) * 0.5 - 69;
    const targetRotation = Math.atan2(rightSurface - leftSurface, 132);
    const previousGrounded = this.grounded;
    const gap = targetY - this.y;

    if (this.y >= targetY) {
      const impact = Math.max(0, this.velocityY) + Math.abs(Phaser.Math.Angle.Wrap(this.rotation - targetRotation)) * 130;
      this.y = targetY;
      this.grounded = true;
      if (!previousGrounded && impact > 235) {
        this.damageRig(Math.min(18, (impact - 210) * 0.055), 'HARD LANDING');
        this.velocityY = -Math.min(80, impact * 0.12);
      } else {
        this.velocityY = Math.min(0, this.velocityY * -0.08);
      }
    } else if (gap < 16 && this.velocityY > -15) {
      this.grounded = true;
      this.y = Phaser.Math.Linear(this.y, targetY, Math.min(1, delta * 14));
      this.velocityY *= 0.72;
    } else {
      this.grounded = false;
    }

    const gasPressed = this.controls.gas || this.keys.W.isDown || this.keys.UP.isDown;
    const brakePressed = this.controls.brake || this.keys.S.isDown || this.keys.DOWN.isDown;
    const leftPressed = this.controls.left || this.keys.A.isDown || this.keys.LEFT.isDown;
    const rightPressed = this.controls.right || this.keys.D.isDown || this.keys.RIGHT.isDown;
    const throttle = gasPressed && this.fuel > 0 ? 1 : 0;
    if (this.grounded) {
      const traction = 1 - Math.min(0.55, Math.abs(targetRotation) * 0.65);
      this.velocityX += throttle * 128 * traction * delta;
      this.velocityX += Math.sin(targetRotation) * 124 * delta;
      if (brakePressed) {
        if (this.velocityX > 14) this.velocityX -= 290 * delta;
        else this.velocityX -= 56 * delta;
      }
      this.velocityX *= Math.pow(0.988, delta * 60);
      const rotationError = Phaser.Math.Angle.Wrap(targetRotation - this.rotation);
      this.angularVelocity += rotationError * 22 * delta;
      this.angularVelocity *= Math.pow(0.67, delta * 60);
      this.rotation += this.angularVelocity * delta;
      if (Math.abs(this.velocityX) > 18 && this.elapsed - this.lastDust > 0.1) {
        this.spawnDust();
        this.lastDust = this.elapsed;
      }
    } else {
      this.velocityY += 515 * delta;
      const tilt = (rightPressed ? 1 : 0) - (leftPressed ? 1 : 0);
      this.angularVelocity += tilt * 2.25 * delta;
      this.angularVelocity *= Math.pow(0.985, delta * 60);
      this.rotation += this.angularVelocity * delta;
      this.velocityX *= Math.pow(0.998, delta * 60);
    }

    if (this.winchTimer > 0) {
      this.winchTimer -= delta;
      this.velocityX += 265 * delta;
      this.velocityY -= 80 * delta;
    }
    this.winchCooldown = Math.max(0, this.winchCooldown - delta);

    this.velocityX = Phaser.Math.Clamp(this.velocityX, -62, 238);
    this.x = Phaser.Math.Clamp(this.x + this.velocityX * delta, 120, ROUTE_LENGTH + 120);
    this.y += this.velocityY * delta;
    this.fuel = Math.max(0, this.fuel - throttle * delta * (0.33 + Math.abs(this.velocityX) * 0.0012));
    this.wheelRotation += this.velocityX * delta * 0.038;

    this.obstacles.forEach((obstacle) => {
      if (!obstacle.hit && Math.abs(this.x - obstacle.x) < 64 && this.y > terrainHeight(obstacle.x) - 125) {
        obstacle.hit = true;
        const force = Math.max(0.4, Math.abs(this.velocityX) / 180);
        this.velocityX *= 0.54;
        this.velocityY = -115 * force;
        this.angularVelocity -= 0.75 * force;
        this.damageRig(5 + force * 8, 'TRAIL DAMAGE');
        this.tweens.add({ targets: obstacle.sprite, angle: obstacle.x % 2 ? 19 : -19, x: obstacle.sprite.x + 22, duration: 240, yoyo: true });
      }
    });

    audioBus.updateEngine(this.velocityX, throttle);
  }

  private updateVehicleVisuals(): void {
    this.vehicle.setPosition(this.x, this.y).setRotation(this.rotation);
    this.frontWheel.setRotation(this.wheelRotation);
    this.rearWheel.setRotation(this.wheelRotation);
    this.cableGraphics.clear();
    if (this.winchTimer > 0) {
      const anchorX = this.x + 238;
      const anchorY = terrainHeight(anchorX) - 37;
      this.cableGraphics.lineStyle(5, 0xd8c4a0, 0.9).lineBetween(this.x + 96, this.y + 9, anchorX, anchorY);
      this.cableGraphics.fillStyle(COLORS.orange).fillCircle(anchorX, anchorY, 9);
    }
  }

  private updateCollectibles(time: number): void {
    this.pickups.forEach((pickup) => {
      if (pickup.collected) return;
      pickup.sprite.setRotation(Math.sin(time * 0.002 + pickup.x) * 0.08);
      if (Math.abs(this.x - pickup.x) < 75 && Math.abs(this.y - pickup.sprite.y) < 125) {
        pickup.collected = true;
        if (pickup.type === 'fuel') {
          this.fuel = Math.min(100, this.fuel + 28);
          this.showToast('FUEL FOUND', '+28 fuel — keep rolling.', 1350);
        } else {
          this.scrap += 1;
          this.showToast('SPARE PART', 'Two parts can patch the rig.', 1200);
        }
        audioBus.pickup();
        vibrate(35);
        this.tweens.add({ targets: pickup.sprite, scale: 1.2, alpha: 0, y: pickup.sprite.y - 55, duration: 260, onComplete: () => pickup.sprite.destroy() });
      }
    });
  }

  private updateHud(): void {
    this.healthFill.setScale(Math.max(0.001, this.health / 100), 1).setFillStyle(this.health < 30 ? COLORS.danger : COLORS.success);
    this.fuelFill.setScale(Math.max(0.001, this.fuel / 100), 1).setFillStyle(this.fuel < 24 ? COLORS.danger : COLORS.orange);
    this.progressFill.displayWidth = 213 * Phaser.Math.Clamp(this.x / ROUTE_LENGTH, 0, 1);
    this.speedLabel.setText(String(Math.max(0, Math.round(this.velocityX * 0.22))));
    this.scrapLabel.setText(`⚙ ${this.scrap}`);
    this.routeLabel.setText(routeNameAt(this.x));
    const target = this.nextCheckpoint < this.checkpoints.length ? this.checkpoints[this.nextCheckpoint] : ROUTE_LENGTH;
    const targetName = this.nextCheckpoint < this.checkpoints.length ? 'CAMP' : 'HOME';
    this.objectiveLabel.setText(`${targetName}  ${Math.max(0, (target - this.x) / 1000).toFixed(1)} KM`);
    const winchReady = 1 - this.winchCooldown / 9;
    this.winchFill.setScale(Math.max(0.01, winchReady), 1).setFillStyle(winchReady >= 1 ? COLORS.orange : 0x71777a);
    this.winchLabel.setText(this.winchCooldown > 0 ? `${Math.ceil(this.winchCooldown)}S` : 'CABLE');
    this.patchLabel.setText(this.scrap >= 2 ? 'PATCH' : 'NEED 2');
  }

  private updateAtmosphere(): void {
    const progress = Phaser.Math.Clamp(this.x / ROUTE_LENGTH, 0, 1);
    let start = Phaser.Display.Color.ValueToColor(0x7699a3);
    let end = Phaser.Display.Color.ValueToColor(0xc27658);
    if (progress > 0.6) {
      start = Phaser.Display.Color.ValueToColor(0xc27658);
      end = Phaser.Display.Color.ValueToColor(0x4d5269);
    }
    const local = progress <= 0.6 ? progress / 0.6 : (progress - 0.6) / 0.4;
    const color = Phaser.Display.Color.Interpolate.ColorWithColor(start, end, 100, local * 100);
    this.sky.setFillStyle(Phaser.Display.Color.GetColor(color.r, color.g, color.b));
  }

  private checkRouteEvents(): void {
    const route = routeNameAt(this.x);
    if (route !== this.lastRoute) {
      if (this.lastRoute) this.showToast(route, this.routeFlavor(route), 1900);
      this.lastRoute = route;
    }
    if (this.nextCheckpoint < this.checkpoints.length && this.x >= this.checkpoints[this.nextCheckpoint]) {
      this.health = Math.min(100, this.health + 26);
      this.fuel = Math.min(100, this.fuel + 18);
      this.nextCheckpoint += 1;
      audioBus.checkpoint();
      vibrate([50, 40, 80]);
      this.showToast('TRAIL CAMP', 'Rig patched. Tank topped. Take a breath.', 2400);
    }
  }

  private checkEndState(): void {
    if (this.x >= ROUTE_LENGTH) {
      this.finishRun(true);
    } else if (this.health <= 0 || this.y > GAME_HEIGHT + 180) {
      this.finishRun(false);
    } else if (this.fuel <= 0 && Math.abs(this.velocityX) < 2 && this.winchCooldown > 0) {
      this.finishRun(false);
    }
  }

  private damageRig(amount: number, reason: string): void {
    if (this.elapsed - this.lastDamageAt < 0.45) return;
    this.lastDamageAt = this.elapsed;
    this.health = Math.max(0, this.health - amount);
    audioBus.crash(Math.min(1.25, amount / 10));
    vibrate([45, 25, 70]);
    this.cameras.main.shake(180, 0.005 + amount * 0.00022);
    this.cameras.main.flash(100, 177, 47, 37, false);
    this.showToast(reason, `Rig integrity -${Math.round(amount)}`, 1050);
  }

  private spawnDust(): void {
    const dust = this.add.image(this.x - 86, terrainHeight(this.x - 76) - 10, 'dust').setScale(0.35 + Math.random() * 0.28).setDepth(2).setAlpha(0.72);
    this.tweens.add({
      targets: dust,
      x: dust.x - 28 - Math.random() * 30,
      y: dust.y - 20 - Math.random() * 18,
      scale: dust.scale * 1.9,
      alpha: 0,
      duration: 620,
      onComplete: () => dust.destroy()
    });
  }

  private startWinch(): void {
    audioBus.unlock();
    if (this.winchCooldown > 0 || this.winchTimer > 0) {
      audioBus.click();
      return;
    }
    this.winchTimer = 1.65;
    this.winchCooldown = 9;
    audioBus.winch();
    vibrate(45);
    this.showToast('CABLE SET', 'Pulling the rig forward.', 1100);
  }

  private patchRig(): void {
    audioBus.unlock();
    if (this.scrap < 2 || this.health >= 100) {
      audioBus.click();
      return;
    }
    this.scrap -= 2;
    this.health = Math.min(100, this.health + 24);
    audioBus.checkpoint();
    this.showToast('FIELD PATCH', '+24 rig integrity.', 1250);
  }

  private showToast(title: string, copy: string, duration: number): void {
    this.toastTitle.setText(title);
    this.toastCopy.setText(copy);
    this.tweens.killTweensOf(this.toastContainer);
    this.toastContainer.setAlpha(0).setY(132);
    this.tweens.add({ targets: this.toastContainer, alpha: 1, y: 142, duration: 180, ease: 'Back.out' });
    this.time.delayedCall(duration, () => {
      if (!this.toastContainer?.active) return;
      this.tweens.add({ targets: this.toastContainer, alpha: 0, y: 129, duration: 220 });
    });
  }

  private routeFlavor(route: string): string {
    const flavor: Record<string, string> = {
      'COYOTE RAVINE': 'Loose ground. Save the cable.',
      'JUNIPER PASS': 'The pines hide a steep ridge.',
      'MOSSBACK TRAIL': 'Easy on the pedal through the rocks.',
      'RED KNIFE BASIN': 'Open country. Watch your fuel.',
      'LAST LIGHT RIDGE': 'One final climb between you and home.'
    };
    return flavor[route] ?? 'Keep heading east.';
  }

  private togglePause(): void {
    if (this.runEnded) return;
    audioBus.click();
    this.paused = !this.paused;
    if (!this.paused) {
      this.scene.get('GameScene').children.getChildren().filter((child) => child.name === 'pause-overlay').forEach((child) => child.destroy());
      audioBus.startEngine();
      return;
    }
    audioBus.stopEngine();
    const overlay = this.add.container(0, 0).setScrollFactor(0).setDepth(90).setName('pause-overlay');
    const shade = this.add.rectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, 0x10131a, 0.88).setOrigin(0).setInteractive();
    const title = this.add.text(GAME_WIDTH / 2, 190, 'PARKED FOR A MINUTE', { fontFamily: FONT_HEAD, fontSize: '54px', fontStyle: '800', color: '#fff4da', letterSpacing: 2 }).setOrigin(0.5);
    const resume = this.pauseButton(470, 300, 'BACK TO THE TRAIL', COLORS.orange, () => this.togglePause());
    const restart = this.pauseButton(470, 390, 'RESTART RUN', 0x444b52, () => {
      audioBus.click();
      this.scene.restart();
    });
    const quit = this.pauseButton(470, 480, 'MAIN MENU', COLORS.rust, () => {
      audioBus.stopEngine();
      this.scene.start('MenuScene');
    });
    overlay.add([shade, title, resume, restart, quit]);
  }

  private pauseButton(x: number, y: number, copy: string, color: number, action: () => void): Phaser.GameObjects.Container {
    const bg = this.add.graphics().fillStyle(color).fillRoundedRect(0, 0, 340, 64, 13);
    const label = this.add.text(170, 32, copy, { fontFamily: FONT_HEAD, fontSize: '23px', fontStyle: '800', color: '#fff8e8', letterSpacing: 1 }).setOrigin(0.5);
    const button = this.add.container(x, y, [bg, label]).setSize(340, 64).setInteractive();
    button.on('pointerdown', action);
    return button;
  }

  private finishRun(won: boolean): void {
    if (this.runEnded) return;
    this.runEnded = true;
    audioBus.stopEngine();
    this.controls = { gas: false, brake: false, left: false, right: false };
    const bestDistance = Math.max(Number(localStorage.getItem('dustbound-best') ?? 0), this.x);
    localStorage.setItem('dustbound-best', String(bestDistance));
    if (won) {
      audioBus.checkpoint();
      this.cameras.main.flash(450, 255, 204, 104, false);
    } else {
      audioBus.crash(1.2);
    }
    const result: RunResult = { won, distance: Math.min(this.x, ROUTE_LENGTH), time: this.elapsed, scrap: this.scrap, bestDistance };
    this.time.delayedCall(650, () => this.scene.start('ResultScene', result));
  }
}
