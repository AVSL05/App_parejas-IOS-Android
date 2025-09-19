# Cloud Functions for Amor App

## Requirements

- Node.js 18.x (recommended). Your current node is newer; Firebase Functions v2 expects Node 18 runtime during deploy.

## Setup

```bash
cd functions
npm install
npm run build
firebase deploy --only functions --project amor-app-parejas
```

## Notes

- The function `onNotificationCreate` uses Firebase Functions v2 API (`onDocumentCreated`).
- Make sure the receiving user document contains `fcmTokens` array.
- iOS requires APNs key uploaded in Firebase Console and Push/Background capabilities enabled in Xcode.
