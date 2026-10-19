package app.wendelin

/** What the channel needs to know about one active media session (no Android types). */
data class SessionInfo(val packageName: String, val state: Int)

/**
 * Logic of the media channel without Android types, so it runs on the JVM: which session counts,
 * where the playback position is now, readable app names. `PlaybackState.STATE_*` values are kept
 * as numbers (like `WakePolicy`).
 */
object MediaSessionPick {
    const val STATE_NONE = 0
    const val STATE_STOPPED = 1
    const val STATE_PAUSED = 2
    const val STATE_PLAYING = 3
    const val STATE_BUFFERING = 6
    const val STATE_CONNECTING = 8

    /** Position value of "unknown" (`PlaybackState.PLAYBACK_POSITION_UNKNOWN`). */
    const val POSITION_UNKNOWN = -1L

    /** Whether [state] means sound is (about to be) playing. */
    fun isPlaying(state: Int): Boolean =
        state == STATE_PLAYING || state == STATE_BUFFERING || state == STATE_CONNECTING

    /**
     * Index of the session to control: the first one that is playing, else the first that is
     * paused (the most recently used player comes first), else the first one that is not
     * stopped or empty; `null` if there is nothing usable.
     */
    fun pick(sessions: List<SessionInfo>): Int? {
        sessions.indexOfFirst { isPlaying(it.state) }.takeIf { it >= 0 }?.let { return it }
        sessions.indexOfFirst { it.state == STATE_PAUSED }.takeIf { it >= 0 }?.let { return it }
        return sessions.indexOfFirst { it.state != STATE_NONE && it.state != STATE_STOPPED }
            .takeIf { it >= 0 }
    }

    /**
     * Position now: the reported position plus the time since the report times the speed while
     * playing, limited to [duration] when it is known. `null` if the player reports none.
     */
    fun position(
        reported: Long,
        updateTime: Long,
        now: Long,
        speed: Float,
        playing: Boolean,
        duration: Long,
    ): Long? {
        if (reported < 0) return null
        var pos = reported
        if (playing && updateTime > 0 && now > updateTime) {
            pos += ((now - updateTime) * speed).toLong()
        }
        if (duration > 0 && pos > duration) pos = duration
        return pos
    }

    /** Duration, `null` if the player reports none (live streams, 0 or negative). */
    fun duration(reported: Long): Long? = reported.takeIf { it > 0 }

    private val names = mapOf(
        "com.audible.application" to "Audible",
        "com.spotify.music" to "Spotify",
        "com.google.android.apps.youtube.music" to "YouTube Music",
        "com.google.android.youtube" to "YouTube",
        "au.com.shiftyjelly.pocketcasts" to "Pocket Casts",
        "de.danoeh.antennapod" to "AntennaPod",
        "com.itunestoppodcastplayer.app" to "Podcast Addict",
        "com.bambuna.podcastaddict" to "Podcast Addict",
        "org.videolan.vlc" to "VLC",
        "com.google.android.apps.podcasts" to "Google Podcasts",
        "audiobookshelf.app" to "Audiobookshelf",
        "com.amazon.mp3" to "Amazon Music",
        "deezer.android.app" to "Deezer",
    )

    /** Name for the player [packageName] when the system label is not visible to the app. */
    fun appName(packageName: String, systemLabel: String?): String =
        systemLabel?.takeIf { it.isNotBlank() } ?: names[packageName] ?: packageName

    /** Argument checks of `send`: the command names of the Dart side. */
    val commands = setOf("play", "pause", "next", "previous")
}
