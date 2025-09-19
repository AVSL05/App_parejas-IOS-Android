import * as admin from 'firebase-admin';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import logger from 'firebase-functions/logger';

admin.initializeApp();
const db = admin.firestore();

// Use a fixed region compatible with Firestore (US multi-region -> us-central1)
setGlobalOptions({ region: 'us-central1' });

// Trigger when a notification doc is created (v2 API)
export const onNotificationCreate = onDocumentCreated('notifications/{id}', async (event) => {
  const snap = event.data; // QueryDocumentSnapshot
  if (!snap) {
    logger.warn('No snapshot data for event', event.params);
    return;
  }

  const data = snap.data() as Record<string, unknown>;

  const to = typeof data.to === 'string' ? (data.to as string) : undefined;
  const title = typeof data.title === 'string' ? (data.title as string) : 'Notificación';
  const body = typeof data.body === 'string' ? (data.body as string) : '';

  if (!to) {
    logger.warn('Missing `to` in notification doc', event.params.id);
    return;
  }

  try {
    // Read receiver tokens
    const userDoc = await db.collection('users').doc(to).get();
    const tokens: string[] = (userDoc.get('fcmTokens') as string[]) || [];

    if (!tokens.length) {
      logger.info('No FCM tokens for user', to);
      await snap.ref.update({ status: 'no-tokens', processedAt: admin.firestore.FieldValue.serverTimestamp() });
      return;
    }

    const type = typeof data.type === 'string' ? (data.type as string) : 'generic';
    const pairId = typeof data.pairId === 'string' ? (data.pairId as string) : '';
    const senderId = typeof data.senderId === 'string' ? (data.senderId as string) : '';
    const senderName = typeof data.senderName === 'string' ? (data.senderName as string) : '';

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: {
        title,
        body,
      },
      data: {
        type,
        pairId,
        senderId,
        senderName,
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            alert: {
              title,
              body,
            },
          },
        },
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'amor_app_channel',
          sound: 'default',
          color: '#E91E63',
        },
      },
    };

    const resp = await admin.messaging().sendEachForMulticast(message);
    const success = resp.successCount;
    const failure = resp.failureCount;

    // Cleanup invalid tokens
    const invalidTokens: string[] = [];
    resp.responses.forEach((r, idx) => {
      if (!r.success) {
        const errCode = (r.error as { code?: string } | undefined)?.code || '';
        if (errCode === 'messaging/invalid-registration-token' || errCode === 'messaging/registration-token-not-registered') {
          invalidTokens.push(tokens[idx]);
        }
      }
    });

    if (invalidTokens.length) {
      await db.collection('users').doc(to).update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(...invalidTokens),
      });
    }

    await snap.ref.update({
      status: failure ? 'partial' : 'sent',
      successCount: success,
      failureCount: failure,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  } catch (e) {
    logger.error('Error sending FCM', e);
    await snap.ref.update({
      status: 'error',
      error: (e as Error).message,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});
