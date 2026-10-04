import { Capacitor } from '@capacitor/core';
import { Haptics } from '@capacitor/haptics';
import { ScreenOrientation } from '@capacitor/screen-orientation';
import { StatusBar } from '@capacitor/status-bar';

export function initializeNativeShell(): void {
  if (!Capacitor.isNativePlatform()) return;
  void Promise.allSettled([
    ScreenOrientation.lock({ orientation: 'landscape' }),
    StatusBar.hide(),
    StatusBar.setOverlaysWebView({ overlay: true })
  ]);
}

export function vibrate(pattern: number | number[]): void {
  if (Capacitor.isNativePlatform()) {
    const duration = Array.isArray(pattern)
      ? Math.min(250, pattern.filter((_, index) => index % 2 === 0).reduce((total, value) => total + value, 0))
      : pattern;
    void Haptics.vibrate({ duration }).catch(() => undefined);
    return;
  }
  navigator.vibrate?.(pattern);
}
