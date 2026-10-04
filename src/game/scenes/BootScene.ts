import Phaser from 'phaser';
import { COLORS, FONT_BODY, FONT_HEAD, GAME_HEIGHT, GAME_WIDTH } from '../constants';

export class BootScene extends Phaser.Scene {
  constructor() {
    super('BootScene');
  }

  create(): void {
    this.cameras.main.setBackgroundColor(COLORS.ink);
    const title = this.add.text(GAME_WIDTH / 2, GAME_HEIGHT / 2 - 20, 'DUSTBOUND', {
      fontFamily: FONT_HEAD,
      fontSize: '62px',
      fontStyle: '800',
      color: '#fff4da',
      letterSpacing: 6
    }).setOrigin(0.5);
    this.add.text(GAME_WIDTH / 2, GAME_HEIGHT / 2 + 44, 'PACKING THE RV…', {
      fontFamily: FONT_BODY,
      fontSize: '14px',
      fontStyle: '800',
      color: '#f4a53b',
      letterSpacing: 3
    }).setOrigin(0.5);

    this.createTextures();
    void document.fonts.ready.then(() => {
      this.time.delayedCall(260, () => {
        this.cameras.main.fadeOut(240, 23, 26, 37);
        this.time.delayedCall(250, () => this.scene.start('MenuScene'));
      });
    });

    this.tweens.add({ targets: title, alpha: { from: 0.55, to: 1 }, duration: 800, yoyo: true, repeat: -1 });
  }

  private createTextures(): void {
    const g = this.make.graphics({ x: 0, y: 0 });

    // Pine tree
    g.fillStyle(0x283f3a).fillTriangle(44, 0, 7, 92, 81, 92);
    g.fillStyle(0x36594c).fillTriangle(44, 18, 0, 116, 88, 116);
    g.fillStyle(0x4c6d56).fillTriangle(44, 45, 2, 137, 86, 137);
    g.fillStyle(0x3b2925).fillRoundedRect(37, 117, 14, 39, 4);
    g.generateTexture('pine', 88, 156);
    g.clear();

    // Cactus
    g.fillStyle(0x486d51).fillRoundedRect(25, 5, 22, 105, 11);
    g.fillRoundedRect(7, 39, 21, 18, 9).fillRoundedRect(7, 28, 13, 37, 7);
    g.fillRoundedRect(44, 55, 24, 17, 8).fillRoundedRect(57, 36, 12, 37, 6);
    g.fillStyle(0x6d8e67).fillRoundedRect(30, 9, 5, 92, 3);
    g.generateTexture('cactus', 76, 115);
    g.clear();

    // Boulder
    g.fillStyle(0x4b3b39).fillPoints([
      new Phaser.Math.Vector2(2, 56), new Phaser.Math.Vector2(12, 20), new Phaser.Math.Vector2(36, 3),
      new Phaser.Math.Vector2(70, 10), new Phaser.Math.Vector2(91, 39), new Phaser.Math.Vector2(86, 63),
      new Phaser.Math.Vector2(12, 67)
    ], true);
    g.fillStyle(0x765447).fillTriangle(13, 22, 36, 7, 37, 47);
    g.fillStyle(0x8b6651).fillTriangle(39, 7, 69, 14, 40, 47);
    g.generateTexture('boulder', 96, 70);
    g.clear();

    // Fuel can
    g.fillStyle(0x262a31).fillRoundedRect(17, 0, 30, 12, 4);
    g.fillStyle(COLORS.rust).fillRoundedRect(5, 9, 55, 65, 8);
    g.lineStyle(5, 0xf4a53b, 1).strokeRoundedRect(16, 21, 33, 39, 4);
    g.lineBetween(18, 23, 47, 57).lineBetween(47, 23, 18, 57);
    g.generateTexture('fuel', 66, 78);
    g.clear();

    // Scrap bolt
    g.fillStyle(0xd7d2bf).fillCircle(36, 36, 31);
    g.fillStyle(0x70757a).fillPoints([
      new Phaser.Math.Vector2(36, 4), new Phaser.Math.Vector2(61, 19), new Phaser.Math.Vector2(61, 52),
      new Phaser.Math.Vector2(36, 68), new Phaser.Math.Vector2(10, 52), new Phaser.Math.Vector2(10, 19)
    ], true);
    g.fillStyle(0x252a31).fillCircle(36, 36, 13);
    g.generateTexture('scrap', 72, 72);
    g.clear();

    // Route marker
    g.fillStyle(0x312721).fillRoundedRect(43, 62, 12, 72, 3);
    g.fillStyle(0xf4ead1).fillRoundedRect(0, 0, 98, 72, 9);
    g.lineStyle(5, 0x302a2b, 1).strokeRoundedRect(0, 0, 98, 72, 9);
    g.fillStyle(COLORS.orange).fillTriangle(17, 18, 80, 36, 17, 54);
    g.generateTexture('route-sign', 98, 134);
    g.clear();

    // Campsite flag
    g.fillStyle(0x332b28).fillRect(10, 0, 7, 118);
    g.fillStyle(COLORS.teal).fillTriangle(17, 4, 81, 26, 17, 49);
    g.fillStyle(COLORS.cream).fillCircle(34, 26, 7);
    g.generateTexture('camp-flag', 86, 120);
    g.clear();

    // Soft cloud
    g.fillStyle(0xfff1d4, 0.45).fillEllipse(59, 31, 92, 45);
    g.fillEllipse(118, 36, 104, 56).fillEllipse(173, 39, 76, 39).fillRoundedRect(46, 34, 153, 31, 15);
    g.generateTexture('cloud', 220, 74);
    g.clear();

    // Dust puff
    g.fillStyle(0xd9aa74, 0.7).fillCircle(12, 15, 11);
    g.fillStyle(0xe9c48f, 0.5).fillCircle(26, 9, 8);
    g.fillStyle(0x9b765b, 0.55).fillCircle(38, 17, 13);
    g.generateTexture('dust', 53, 33);
    g.clear();

    // Winch anchor marker
    g.lineStyle(7, COLORS.cream, 1).strokeCircle(29, 29, 20);
    g.lineBetween(29, 0, 29, 58).lineBetween(0, 29, 58, 29);
    g.fillStyle(COLORS.rust).fillCircle(29, 29, 7);
    g.generateTexture('anchor', 58, 58);

    g.destroy();
  }
}
