import Phaser from 'phaser';
import { audioBus } from '../systems/AudioBus';
import { COLORS, FONT_BODY, FONT_HEAD, GAME_HEIGHT, GAME_WIDTH, ROUTE_LENGTH, type RunResult } from '../constants';

export class ResultScene extends Phaser.Scene {
  private result: RunResult = { won: false, distance: 0, time: 0, scrap: 0, bestDistance: 0 };

  constructor() {
    super('ResultScene');
  }

  init(data: RunResult): void {
    this.result = data;
  }

  create(): void {
    this.drawBackdrop();
    this.cameras.main.fadeIn(350, 23, 26, 37);
    const won = this.result.won;
    const percent = Math.floor((this.result.distance / ROUTE_LENGTH) * 100);

    this.add.text(GAME_WIDTH / 2, 96, won ? 'MADE IT HOME' : 'THE TRAIL WON', {
      fontFamily: FONT_HEAD,
      fontSize: '66px',
      fontStyle: '800',
      color: won ? '#fff4da' : '#f3c2a8',
      stroke: '#171a25',
      strokeThickness: 8,
      letterSpacing: 3
    }).setOrigin(0.5);
    this.add.text(GAME_WIDTH / 2, 168, won ? 'The old rig lives to roam another day.' : 'Patch it up, load it again, and take another line.', {
      fontFamily: FONT_BODY, fontSize: '17px', fontStyle: '800', color: '#d9cbb5'
    }).setOrigin(0.5);

    const card = this.add.graphics();
    card.fillStyle(0x171a25, 0.86).fillRoundedRect(250, 222, 780, 214, 25);
    card.lineStyle(3, won ? COLORS.teal : COLORS.rust, 0.8).strokeRoundedRect(250, 222, 780, 214, 25);
    this.stat(365, 280, `${percent}%`, 'ROUTE');
    this.stat(550, 280, this.formatTime(this.result.time), 'TIME');
    this.stat(735, 280, String(this.result.scrap), 'PARTS');
    this.stat(915, 280, `${Math.floor((this.result.bestDistance / ROUTE_LENGTH) * 100)}%`, 'BEST');

    this.add.rectangle(330, 381, 620, 12, 0x3d4143).setOrigin(0, 0.5);
    this.add.rectangle(330, 381, 620 * (this.result.distance / ROUTE_LENGTH), 12, won ? COLORS.teal : COLORS.orange).setOrigin(0, 0.5);
    this.add.text(330, 402, won ? 'SUNDOWN WASH  →  HOME' : `SUNDOWN WASH  →  ${percent}% OF THE WAY`, {
      fontFamily: FONT_HEAD, fontSize: '14px', fontStyle: '800', color: '#bcb19e', letterSpacing: 1
    });

    this.makeButton(330, 488, 290, 72, 'RIDE AGAIN', COLORS.orange, () => {
      audioBus.click();
      this.scene.start('GameScene');
    });
    this.makeButton(660, 488, 290, 72, 'MAIN MENU', 0x444a4f, () => {
      audioBus.click();
      this.scene.start('MenuScene');
    });
    this.add.text(GAME_WIDTH / 2, 628, 'TIP  •  EASE OFF THE PEDAL BEFORE A STEEP RIDGE', {
      fontFamily: FONT_BODY, fontSize: '13px', fontStyle: '800', color: '#a8967f', letterSpacing: 1
    }).setOrigin(0.5);
  }

  private drawBackdrop(): void {
    const bg = this.add.graphics();
    bg.fillGradientStyle(0x3f5062, 0x3f5062, 0xbe7152, 0xbe7152).fillRect(0, 0, GAME_WIDTH, GAME_HEIGHT);
    bg.fillStyle(0xf3bd68, 0.8).fillCircle(1030, 128, 62);
    bg.fillStyle(0x4c4c4b).fillPoints([
      new Phaser.Math.Vector2(0, 510), new Phaser.Math.Vector2(210, 376), new Phaser.Math.Vector2(440, 488),
      new Phaser.Math.Vector2(670, 350), new Phaser.Math.Vector2(903, 470), new Phaser.Math.Vector2(1110, 374),
      new Phaser.Math.Vector2(1280, 449), new Phaser.Math.Vector2(1280, 720), new Phaser.Math.Vector2(0, 720)
    ], true);
    bg.fillStyle(0x5f463c).fillPoints([
      new Phaser.Math.Vector2(0, 590), new Phaser.Math.Vector2(330, 515), new Phaser.Math.Vector2(580, 570),
      new Phaser.Math.Vector2(870, 505), new Phaser.Math.Vector2(1280, 550), new Phaser.Math.Vector2(1280, 720),
      new Phaser.Math.Vector2(0, 720)
    ], true);
  }

  private stat(x: number, y: number, value: string, label: string): void {
    this.add.text(x, y, value, { fontFamily: FONT_HEAD, fontSize: '38px', fontStyle: '800', color: '#fff4da' }).setOrigin(0.5);
    this.add.text(x, y + 46, label, { fontFamily: FONT_BODY, fontSize: '12px', fontStyle: '800', color: '#a9a69d', letterSpacing: 1 }).setOrigin(0.5);
  }

  private makeButton(x: number, y: number, width: number, height: number, copy: string, color: number, action: () => void): void {
    const bg = this.add.graphics().fillStyle(color).fillRoundedRect(0, 0, width, height, 15);
    const label = this.add.text(width / 2, height / 2, copy, { fontFamily: FONT_HEAD, fontSize: '26px', fontStyle: '800', color: '#fff8e7', letterSpacing: 1 }).setOrigin(0.5);
    const button = this.add.container(x, y, [bg, label]).setSize(width, height).setInteractive({ useHandCursor: true });
    button.on('pointerdown', () => { button.setScale(0.97); action(); });
    button.on('pointerup', () => button.setScale(1));
  }

  private formatTime(seconds: number): string {
    const minutes = Math.floor(seconds / 60);
    const rest = Math.floor(seconds % 60).toString().padStart(2, '0');
    return `${minutes}:${rest}`;
  }
}
