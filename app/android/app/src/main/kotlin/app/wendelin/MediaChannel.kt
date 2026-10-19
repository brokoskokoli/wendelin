package app.wendelin

import android.app.NotificationManager
import android.app.SearchManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.os.SystemClock
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform side of `ChannelMediaControlPort` (app/lib/platform/channel_media_control_port.dart):
 * the active media player via `MediaSessionManager.getActiveSessions` (needs the notification
 * access of [MediaListenerService]), without it media key events through
 * `AudioManager.dispatchMediaKeyEvent` (play/pause/next/previous only).
 */
class MediaChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val listener = ComponentName(context, MediaListenerService::class.java)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = ChannelArgs.of(call.arguments)
        try {
            when (call.method) {
                "hasSessionAccess" -> result.success(hasAccess())
                "openSessionAccessSettings" -> {
                    openAccessSettings()
                    result.success(null)
                }
                "nowPlaying" -> result.success(nowPlaying())
                "send" -> {
                    send(args.requireString("command"))
                    result.success(null)
                }
                "seekTo" -> {
                    seekTo(args.requireLong("positionMs"))
                    result.success(null)
                }
                "openApp" -> {
                    openApp(args.requireString("package"), args.string("query"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: MediaException) {
            result.error(e.code, e.message, null)
        } catch (e: ArgumentException) {
            result.error("bad_args", "${e.key} fehlt", null)
        } catch (e: SecurityException) {
            result.error("no_access", "Benachrichtigungszugriff fehlt", null)
        } catch (e: Exception) {
            // ActivityNotFound, IllegalState, ...: an error for Dart instead of a crash.
            result.error("failed", e.message, null)
        }
    }

    private class MediaException(val code: String, message: String) : Exception(message)

    private fun hasAccess(): Boolean {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.isNotificationListenerAccessGranted(listener)
    }

    private fun openAccessSettings() {
        val intents = buildList {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                add(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        listener.flattenToString(),
                    ),
                )
            }
            add(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
        for (intent in intents) {
            try {
                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                return
            } catch (_: Exception) {
                // Try the next, more general page.
            }
        }
        throw MediaException("failed", "Einstellungsseite nicht verfügbar")
    }

    /** Active controllers, most recently used first; needs the notification access. */
    private fun controllers(): List<MediaController> {
        if (!hasAccess()) throw MediaException("no_access", "Benachrichtigungszugriff fehlt")
        val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        return manager.getActiveSessions(listener)
    }

    private fun active(): MediaController? {
        val all = controllers()
        val index =
            MediaSessionPick.pick(
                all.map { SessionInfo(it.packageName, it.playbackState?.state ?: PlaybackState.STATE_NONE) },
            ) ?: return null
        return all[index]
    }

    private fun label(pkg: String): String? =
        try {
            val pm = context.packageManager
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (_: Exception) {
            null
        }

    private fun nowPlaying(): Map<String, Any?>? {
        val c = active() ?: return null
        val state = c.playbackState
        val meta = c.metadata
        val playing = MediaSessionPick.isPlaying(state?.state ?: PlaybackState.STATE_NONE)
        return mapOf(
            "package" to c.packageName,
            "app" to MediaSessionPick.appName(c.packageName, label(c.packageName)),
            "playing" to playing,
            "title" to (meta?.getString(MediaMetadata.METADATA_KEY_DISPLAY_TITLE)
                ?: meta?.getString(MediaMetadata.METADATA_KEY_TITLE)),
            "artist" to (meta?.getString(MediaMetadata.METADATA_KEY_ARTIST)
                ?: meta?.getString(MediaMetadata.METADATA_KEY_AUTHOR)),
            "album" to meta?.getString(MediaMetadata.METADATA_KEY_ALBUM),
            "positionMs" to state?.let {
                MediaSessionPick.position(
                    it.position,
                    it.lastPositionUpdateTime,
                    SystemClock.elapsedRealtime(),
                    it.playbackSpeed,
                    playing,
                    meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L,
                )
            },
            "durationMs" to MediaSessionPick.duration(
                meta?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L,
            ),
        )
    }

    private fun send(command: String) {
        if (command !in MediaSessionPick.commands) {
            throw MediaException("bad_args", "Unbekannter Befehl")
        }
        // Prefer the session; with no access or no session the media keys reach the last player.
        val controller = if (hasAccess()) active() else null
        if (controller != null) {
            val t = controller.transportControls
            when (command) {
                "play" -> t.play()
                "pause" -> t.pause()
                "next" -> t.skipToNext()
                else -> t.skipToPrevious()
            }
            return
        }
        val code = when (command) {
            "play" -> KeyEvent.KEYCODE_MEDIA_PLAY
            "pause" -> KeyEvent.KEYCODE_MEDIA_PAUSE
            "next" -> KeyEvent.KEYCODE_MEDIA_NEXT
            else -> KeyEvent.KEYCODE_MEDIA_PREVIOUS
        }
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_DOWN, code))
        audio.dispatchMediaKeyEvent(KeyEvent(KeyEvent.ACTION_UP, code))
    }

    private fun seekTo(positionMs: Long) {
        val c = active() ?: throw MediaException("no_session", "Nichts aktiv")
        val actions = c.playbackState?.actions ?: 0L
        if (actions and PlaybackState.ACTION_SEEK_TO == 0L) {
            throw MediaException("not_seekable", "Player kann nicht spulen")
        }
        c.transportControls.seekTo(positionMs.coerceAtLeast(0L))
    }

    private fun openApp(pkg: String, query: String?) {
        val pm = context.packageManager
        val launch = pm.getLaunchIntentForPackage(pkg)
            ?: throw MediaException("not_installed", "App nicht installiert")
        if (!query.isNullOrBlank()) {
            val search = Intent(MediaStore.INTENT_ACTION_MEDIA_PLAY_FROM_SEARCH)
                .setPackage(pkg)
                .putExtra(MediaStore.EXTRA_MEDIA_FOCUS, "vnd.android.cursor.item/*")
                .putExtra(SearchManager.QUERY, query)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (search.resolveActivity(pm) != null) {
                try {
                    context.startActivity(search)
                    return
                } catch (_: Exception) {
                    // Fall through to the plain launch.
                }
            }
        }
        context.startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    companion object {
        const val CHANNEL = "app.wendelin/media"
    }
}
