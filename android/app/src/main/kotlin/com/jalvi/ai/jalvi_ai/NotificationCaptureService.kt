package com.jalvi.ai.jalvi_ai

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * User-enabled notification reader.
 * Content stays in process memory and is returned only after an explicit app request.
 */
class NotificationCaptureService : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        val item = sbn ?: return
        if (item.packageName == packageName) return
        val extras = item.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
        if (title.isBlank() && text.isBlank()) return

        val safeTitle = redactCodes(title).take(180)
        val safeText = redactCodes(text).take(500)
        val entry = mapOf(
            "app" to item.packageName.substringAfterLast('.').take(50),
            "title" to safeTitle,
            "text" to safeText
        )
        synchronized(entries) {
            entries.addFirst(entry)
            while (entries.size > 15) entries.removeLast()
        }
    }

    companion object {
        private val entries = java.util.ArrayDeque<Map<String, String>>()

        private fun redactCodes(value: String): String {
            return value.replace(
                Regex("(?i)(otp|verification code|one[- ]time password)\\s*[:：-]?\\s*\\d{4,8}"),
                "$1 [hidden]"
            )
        }

        @JvmStatic
        fun recentNotifications(): List<Map<String, String>> {
            return synchronized(entries) { entries.toList() }
        }
    }
}
