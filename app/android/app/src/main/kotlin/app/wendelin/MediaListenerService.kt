package app.wendelin

import android.service.notification.NotificationListenerService

/**
 * Anchor for the "notification access" permission: only an app with an enabled listener may read
 * `MediaSessionManager.getActiveSessions`. Wendelin does not read notifications; the service has
 * no logic (see `MediaChannel`).
 */
class MediaListenerService : NotificationListenerService()
