import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.piyushkumarexe.dustboundrv',
  appName: 'Dustbound RV',
  webDir: 'dist',
  loggingBehavior: 'none',
  backgroundColor: '#171a25',
  server: {
    androidScheme: 'https',
    iosScheme: 'capacitor'
  },
  android: {
    backgroundColor: '#171a25',
    allowMixedContent: false,
    captureInput: true,
    webContentsDebuggingEnabled: false
  },
  ios: {
    backgroundColor: '#171a25',
    contentInset: 'always',
    preferredContentMode: 'mobile',
    scrollEnabled: false,
    zoomEnabled: false
  }
};

export default config;
