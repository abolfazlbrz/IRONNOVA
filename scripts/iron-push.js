import { Capacitor } from '@capacitor/core';
import { PushNotifications } from '@capacitor/push-notifications';

const client = window.ironSupabaseClient;
let registeringUserId = null;

if (client && Capacitor.isNativePlatform()) {
  PushNotifications.addListener('registration', async ({ value }) => {
    try {
      const { data: { user }, error: authError } = await client.auth.getUser();
      if (authError || !user || !value) return;
      const { error } = await client.from('iron_push_tokens').upsert({
        user_id: user.id,
        token: value,
        platform: Capacitor.getPlatform(),
        updated_at: new Date().toISOString()
      }, { onConflict: 'user_id,token' });
      if (error) console.error('IRONNOVA push token save failed:', error.message);
      else console.info('IRONNOVA push token registered.');
    } catch (error) {
      console.error('IRONNOVA push token registration failed:', error);
    }
  });

  PushNotifications.addListener('registrationError', error => {
    console.error('IRONNOVA FCM registration error:', error);
  });

  PushNotifications.addListener('pushNotificationReceived', notification => {
    console.info('IRONNOVA push received:', notification?.title || '');
    if (typeof window.toast === 'function') {
      const message = [notification?.title, notification?.body].filter(Boolean).join(' · ');
      if (message) window.toast(message);
    }
  });

  PushNotifications.addListener('pushNotificationActionPerformed', async action => {
    try {
      const notification = action?.notification || {};
      const data = notification?.data || {};
      console.info('IRONNOVA push opened:', notification?.title || '');
      if (typeof window.ironOpenPushNotification === 'function') {
        await window.ironOpenPushNotification({ ...data, data });
      } else {
        window.location.hash = '#home';
      }
    } catch (error) {
      console.error('IRONNOVA push navigation failed:', error);
      window.location.hash = '#home';
    }
  });

  async function registerForUser(user) {
    if (!user?.id || registeringUserId === user.id) return;
    registeringUserId = user.id;
    try {
      const permission = await PushNotifications.checkPermissions();
      let receive = permission.receive;
      if (receive !== 'granted' && (receive === 'prompt' || receive === 'prompt-with-rationale')) {
        receive = (await PushNotifications.requestPermissions()).receive;
      }
      if (receive !== 'granted') {
        console.info('IRONNOVA notifications permission not granted.');
        registeringUserId = null;
        return;
      }
      await PushNotifications.register();
    } catch (error) {
      registeringUserId = null;
      console.error('IRONNOVA push setup failed:', error);
    }
  }

  client.auth.onAuthStateChange((event, session) => {
    if (session?.user && ['INITIAL_SESSION', 'SIGNED_IN', 'TOKEN_REFRESHED'].includes(event)) {
      void registerForUser(session.user);
    }
    if (event === 'SIGNED_OUT') registeringUserId = null;
  });

  client.auth.getSession().then(({ data, error }) => {
    if (!error && data.session?.user) void registerForUser(data.session.user);
  });
}
