import Phaser from 'phaser';
import '@fontsource/barlow-condensed/latin-500.css';
import '@fontsource/barlow-condensed/latin-600.css';
import '@fontsource/barlow-condensed/latin-700.css';
import '@fontsource/barlow-condensed/latin-800.css';
import '@fontsource-variable/nunito/wght.css';
import { BootScene } from './game/scenes/BootScene';
import { MenuScene } from './game/scenes/MenuScene';
import { GameScene } from './game/scenes/GameScene';
import { ResultScene } from './game/scenes/ResultScene';
import { initializeNativeShell } from './game/systems/NativeShell';
import './style.css';

initializeNativeShell();

const config: Phaser.Types.Core.GameConfig = {
  type: Phaser.AUTO,
  parent: 'app',
  backgroundColor: '#171a25',
  width: 1280,
  height: 720,
  antialias: true,
  roundPixels: false,
  render: {
    powerPreference: 'high-performance',
    antialias: true,
    pixelArt: false
  },
  scale: {
    mode: Phaser.Scale.FIT,
    autoCenter: Phaser.Scale.CENTER_BOTH,
    width: 1280,
    height: 720
  },
  input: {
    activePointers: 5,
    touch: { capture: true }
  },
  scene: [BootScene, MenuScene, GameScene, ResultScene]
};

new Phaser.Game(config);
