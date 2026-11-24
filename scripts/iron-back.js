import { App } from '@capacitor/app';

App.addListener('backButton', () => {
  // Navigate through the app's page stack. At home, first press confirms;
  // second press exits the Android app.
  const handled = typeof window.ironHandleBack === 'function'
    ? window.ironHandleBack()
    : true;
  if (!handled) App.exitApp();
});
