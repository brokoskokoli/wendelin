package app.wendelin

/** Pure decisions of the AudioTrack output (WP188 part C1); no Android types, testable on the JVM. */
object AudioOutputRoute {
    /**
     * The index in [devices] of the output to prefer for the stored [selected] choice, or `null` =
     * system routing (no choice, or the chosen device is not connected right now). Only a sink that
     * is also a choosable entry counts, so a hidden SCO twin is never picked.
     *
     * While [ownCommMode] (the dialog's phone mode) is on, the system suspends A2DP/LE audio and
     * plays through the communication device, so a Bluetooth sink counts as not available: the
     * system route (= that device) is used instead of an output that stays silent.
     */
    fun deviceIndex(
        selected: AudioDeviceEntry?,
        devices: List<AudioDeviceDesc>,
        ownCommMode: Boolean = false,
    ): Int? {
        val entries = AudioDevicePick.entries(devices, AudioDevicePick.OUTPUT)
        val key = AudioDevicePick.resolve(selected?.key, entries)?.key ?: return null
        val index = devices.indexOfFirst {
            it.isSink && AudioDevicePick.typeName(it, AudioDevicePick.OUTPUT) != null &&
                AudioDevicePick.keyOf(it) == key
        }
        if (index < 0) return null
        return if (ownCommMode && AudioDevicePick.isBluetoothSink(devices[index])) null else index
    }
}

/** What the playback head says about a clip of [totalFrames] frames. */
enum class PlaybackState { PLAYING, DONE, STALLED }

/**
 * Decides from the playback head (frames really played, not frames written) whether the clip has
 * ended. [stallMs] without any head movement (after the first frame) or without a start at all
 * counts as stuck, so a vanished device never hangs the end message.
 */
class PlaybackProgress(private val totalFrames: Int, private val stallMs: Long, startMs: Long) {
    private var lastHead = 0
    private var lastMoveMs = startMs

    fun onPoll(head: Int, nowMs: Long): PlaybackState {
        if (head >= totalFrames) return PlaybackState.DONE
        if (head != lastHead) {
            lastHead = head
            lastMoveMs = nowMs
        }
        return if (nowMs - lastMoveMs >= stallMs) PlaybackState.STALLED else PlaybackState.PLAYING
    }
}
