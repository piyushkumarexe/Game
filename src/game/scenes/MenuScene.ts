import Phaser from 'phaser';
import { audioBus } from '../systems/AudioBus';
import { COLORS, FONT_BODY, FONT_HEAD, GAME_HEIGHT, GAME_WIDTH } from '../constants';

export class MenuScene extends Phaser.Scene {
  private cloudLayer?: Phaser.GameObjects.Container;

  constructor() {
    super('MenuScene');
  }

  create(): void {
    this.cameras.main.fadeIn(350, 23, 26, 37);
    this.drawBackdrop();
    this.drawHeroRV();

    this.add.text(78, 70, 'DUSTBOUND', {
      fontFamily: FONT_HEAD,
      fontSize: '92px',
      fontStyle: '800',
      color: '#fff4da',
      stroke: '#171a25',
      strokeThickness: 8,
      letterSpacing: 3
    }).setDepth(5);
    this.add.text(86, 161, 'R V', {
      fontFamily: FONT_HEAD,
      fontSize: '40px',
      fontStyle: '800',
      color: '#f4a53b',
      letterSpacing: 18
    }).setDepth(5);
    this.add.text(84, 220, 'ONE OLD RIG.  ONE WILD WAY HOME.', {
      fontFamily: FONT_BODY,
      fontSize: '17px',
      fontStyle: '800',
      color: '#fff4da',
      letterSpacing: 1
    }).setDepth(5);

    this.makeButton(90, 292, 294, 82, 'HIT THE TRAIL', COLORS.orange, () => {
      audioBus.unlock();
      audioBus.click();
      this.cameras.main.fadeOut(280, 23, 26, 37);
      this.time.delayedCall(290, () => this.scene.start('GameScene'));
    });

    this.makeButton(90, 390, 142, 58, 'HOW TO', 0x343a43, () => this.showHowTo());
    this.makeButton(242, 390, 142, 58, audioBus.isMuted() ? 'SOUND OFF' : 'SOUND ON', 0x343a43, (_container, label) => {
      audioBus.unlock();
      audioBus.setMuted(!audioBus.isMuted());
      label.setText(audioBus.isMuted() ? 'SOUND OFF' : 'SOUND ON');
      audioBus.click();
    });

    const best = Number(localStorage.getItem('dustbound-best') ?? 0);
    this.add.text(90, 486, best > 0 ? `BEST RUN  ${Math.floor(best / 100)}%` : 'FIRST TRIP?  THE TRAIL WILL TEACH YOU.', {
      fontFamily: FONT_BODY,
      fontSize: '14px',
      fontStyle: '800',
      color: '#d7c6a8',
      letterSpacing: 1
    });

    this.add.text(90, 654, 'TOUCH BUILT  •  OFFLINE READY  •  ORIGINAL ART', {
      fontFamily: FONT_BODY,
      fontSize: '12px',
      fontStyle: '800',
      color: '#b39b81',
      letterSpacing: 1
    });

    this.input.on('pointermove', (pointer: Phaser.Input.Pointer) => {
      if (this.cloudLayer) this.cloudLayer.x = (pointer.x / GAME_WIDTH - 0.5) * -18;
    });
  }

  update(_time: number, delta: number): void {
    if (!this.cloudLayer) return;
    this.cloudLayer.list.forEach((item) => {
      const cloud = item as Phaser.GameObjects.Image;
      cloud.x += delta * 0.008;
      if (cloud.x > GAME_WIDTH + 180) cloud.x = -220;
    });
  }

  private drawBackdrop(): void {
    const bg = this.add.graphics();
    bg.fillGradientStyle(0x486b75, 0x486b75, 0xd28b61, 0xd28b61, 1);
    bg.fillRect(0, 0, GAME_WIDTH, GAME_HEIGHT);
    bg.fillStyle(0xf8cd79, 0.85).fillCircle(1040, 156, 83);

    const far = this.add.graphics();
    far.fillStyle(0x765e5d).fillPoints([
      new Phaser.Math.Vector2(0, 414), new Phaser.Math.Vector2(150, 330), new Phaser.Math.Vector2(330, 390),
      new Phaser.Math.Vector2(512, 268), new Phaser.Math.Vector2(705, 396), new Phaser.Math.Vector2(884, 304),
      new Phaser.Math.Vector2(1088, 378), new Phaser.Math.Vector2(1280, 287), new Phaser.Math.Vector2(1280, 720),
      new Phaser.Math.Vector2(0, 720)
    ], true);
    const near = this.add.graphics();
    near.fillStyle(0x3e4542).fillPoints([
      new Phaser.Math.Vector2(0, 508), new Phaser.Math.Vector2(160, 430), new Phaser.Math.Vector2(330, 479),
      new Phaser.Math.Vector2(530, 378), new Phaser.Math.Vector2(764, 485), new Phaser.Math.Vector2(1005, 401),
      new Phaser.Math.Vector2(1280, 489), new Phaser.Math.Vector2(1280, 720), new Phaser.Math.Vector2(0, 720)
    ], true);
    near.fillStyle(0x2a302e).fillRect(0, 548, GAME_WIDTH, 172);
    near.fillStyle(0xc07a45).fillPoints([
      new Phaser.Math.Vector2(0, 583), new Phaser.Math.Vector2(450, 532), new Phaser.Math.Vector2(820, 570),
      new Phaser.Math.Vector2(1280, 521), new Phaser.Math.Vector2(1280, 720), new Phaser.Math.Vector2(0, 720)
    ], true);

    this.cloudLayer = this.add.container(0, 0, [
      this.add.image(220, 110, 'cloud').setScale(0.8),
      this.add.image(670, 175, 'cloud').setScale(0.48).setAlpha(0.6),
      this.add.image(1160, 76, 'cloud').setScale(0.65)
    ]).setDepth(1);
  }

  private drawHeroRV(): void {
    const rv = this.add.container(880, 435).setDepth(4).setRotation(-0.045);
    const shadow = this.add.ellipse(6, 137, 486, 66, 0x171a25, 0.36);
    const body = this.add.graphics();
    body.fillStyle(0x2f3438).fillCircle(-137, 108, 56).fillCircle(143, 108, 56);
    body.fillStyle(0x15181d).fillCircle(-137, 108, 34).fillCircle(143, 108, 34);
    body.fillStyle(0xc2c1ad).fillCircle(-137, 108, 15).fillCircle(143, 108, 15);
    body.fillStyle(0xe7dfc7).fillRoundedRect(-230, -92, 425, 185, 24);
    body.fillStyle(COLORS.rust).fillRoundedRect(-230, 33, 425, 43, 4);
    body.fillStyle(0x364b52).fillRoundedRect(74, -68, 101, 68, 9);
    body.fillStyle(0x5e7b80).fillRoundedRect(-182, -66, 92, 61, 8).fillRoundedRect(-72, -66, 92, 61, 8);
    body.fillStyle(0x252a2e).fillRoundedRect(-66, 8, 72, 22, 7);
    body.fillStyle(0xf4a53b).fillCircle(191, 38, 10);
    body.fillStyle(0xffffff, 0.35).fillTriangle(83, -60, 163, -60, 163, -11);
    body.lineStyle(7, 0x44433e).strokeRoundedRect(-230, -92, 425, 185, 24);
    body.lineBetween(-214, 12, 191, 12);
    const luggage = this.add.graphics();
    luggage.fillStyle(0x6b3d2e).fillRoundedRect(-110, -126, 91, 34, 6);
    luggage.fillStyle(0x2e4c47).fillRoundedRect(-10, -119, 68, 27, 5);
    luggage.lineStyle(5, 0x292829).lineBetween(-132, -93, 85, -93);
    rv.add([shadow, body, luggage]);
  }

  private makeButton(
    x: number,
    y: number,
    width: number,
    height: number,
    copy: string,
    color: number,
    action: (container: Phaser.GameObjects.Container, label: Phaser.GameObjects.Text) => void
  ): Phaser.GameObjects.Container {
    const panel = this.add.graphics();
    panel.fillStyle(0x171a25, 0.25).fillRoundedRect(4, 7, width, height, 15);
    panel.fillStyle(color).fillRoundedRect(0, 0, width, height, 15);
    panel.lineStyle(3, 0xfff4da, 0.13).strokeRoundedRect(2, 2, width - 4, height - 4, 13);
    const label = this.add.text(width / 2, height / 2, copy, {
      fontFamily: FONT_HEAD,
      fontSize: height > 70 ? '28px' : '20px',
      fontStyle: '800',
      color: '#fff8e7',
      letterSpacing: 1
    }).setOrigin(0.5);
    const container = this.add.container(x, y, [panel, label]).setSize(width, height).setInteractive({ useHandCursor: true }).setDepth(10);
    container.on('pointerdown', () => {
      container.setScale(0.97);
      action(container, label);
    });
    container.on('pointerup', () => container.setScale(1));
    container.on('pointerout', () => container.setScale(1));
    return container;
  }

  private showHowTo(): void {
    audioBus.click();
    const shade = this.add.rectangle(0, 0, GAME_WIDTH, GAME_HEIGHT, 0x0c0e13, 0.78).setOrigin(0).setDepth(50).setInteractive();
    const card = this.add.graphics().setDepth(51);
    card.fillStyle(0x282d34).fillRoundedRect(240, 90, 800, 540, 26);
    card.lineStyle(4, 0xf4a53b, 1).strokeRoundedRect(240, 90, 800, 540, 26);
    const title = this.add.text(640, 134, 'THE TRAIL GUIDE', {
      fontFamily: FONT_HEAD, fontSize: '42px', fontStyle: '800', color: '#fff4da', letterSpacing: 2
    }).setOrigin(0.5).setDepth(52);
    const guide = this.add.text(318, 203,
      'DRIVE\nHold the amber pedal. Ease off before hard landings.\n\nBALANCE\nUse the arrow buttons in the air to keep the rig level.\n\nRECOVER\nThe cable pulls you uphill. Save it for when you’re stuck.\n\nSURVIVE\nGrab fuel, collect scrap, and stop at trail camps to repair.',
      { fontFamily: FONT_BODY, fontSize: '20px', fontStyle: '700', color: '#e7dcc7', lineSpacing: 7, wordWrap: { width: 640 } }
    ).setDepth(52);
    const close = this.makeButton(510, 550, 260, 58, 'GOT IT', COLORS.rust, () => {
      audioBus.click();
      [shade, card, title, guide, close].forEach((object) => object.destroy());
    }).setDepth(53);
  }
}
