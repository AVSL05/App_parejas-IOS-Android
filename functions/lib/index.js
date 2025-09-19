"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.onNotificationCreate = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const v2_1 = require("firebase-functions/v2");
const logger_1 = __importDefault(require("firebase-functions/logger"));
admin.initializeApp();
const db = admin.firestore();
// Use a fixed region compatible with Firestore (US multi-region -> us-central1)
(0, v2_1.setGlobalOptions)({ region: 'us-central1' });
// Trigger when a notification doc is created (v2 API)
exports.onNotificationCreate = (0, firestore_1.onDocumentCreated)('notifications/{id}', async (event) => {
    const snap = event.data; // QueryDocumentSnapshot
    if (!snap) {
        logger_1.default.warn('No snapshot data for event', event.params);
        return;
    }
    const data = snap.data();
    const to = typeof data.to === 'string' ? data.to : undefined;
    const title = typeof data.title === 'string' ? data.title : 'Notificación';
    const body = typeof data.body === 'string' ? data.body : '';
    if (!to) {
        logger_1.default.warn('Missing `to` in notification doc', event.params.id);
        return;
    }
    try {
        // Read receiver tokens
        const userDoc = await db.collection('users').doc(to).get();
        const tokens = userDoc.get('fcmTokens') || [];
        if (!tokens.length) {
            logger_1.default.info('No FCM tokens for user', to);
            await snap.ref.update({ status: 'no-tokens', processedAt: admin.firestore.FieldValue.serverTimestamp() });
            return;
        }
        const type = typeof data.type === 'string' ? data.type : 'generic';
        const pairId = typeof data.pairId === 'string' ? data.pairId : '';
        const senderId = typeof data.senderId === 'string' ? data.senderId : '';
        const senderName = typeof data.senderName === 'string' ? data.senderName : '';
        const message = {
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
        const invalidTokens = [];
        resp.responses.forEach((r, idx) => {
            if (!r.success) {
                const errCode = r.error?.code || '';
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
    }
    catch (e) {
        logger_1.default.error('Error sending FCM', e);
        await snap.ref.update({
            status: 'error',
            error: e.message,
            processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    }
});
//# sourceMappingURL=index.js.map