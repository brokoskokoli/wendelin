package app.wendelin

import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Audio subscriber kinds for the central recording (WP180, ADR 0024).
 */
enum class AudioSubscriberKind {
    /** Continuous stream for the background wake-word engine. */
    WAKE,

    /** Stream for active voice commands / dialog session (with pre-roll, uninterrupted mic). */
    SESSION,

    /** Stream for wake-word and speaker enrollment screens on request. */
    ENROLL,
}

/** One active subscriber to the central audio stream. */
internal data class AudioSubscription(
    val id: String,
    val kind: AudioSubscriberKind,
    val onChunk: (ByteArray) -> Unit,
    val onError: ((Throwable) -> Unit)? = null,
)

/**
 * Central multi-subscriber audio dispatcher and ring buffer (WP180, ADR 0024).
 *
 * Owned by [WakeWordService]. Audio chunks from the single hardware [MicAudioSource] roll
 * continuously into [ringBuffer] and are dispatched to active subscribers.
 * While [AudioSubscriberKind.SESSION] or [AudioSubscriberKind.ENROLL] is active, [AudioSubscriberKind.WAKE]
 * is suppressed so the wake-word engine does not trigger during dialogues or enrollment.
 */
class CentralAudioHub(val ringBuffer: AudioRingBuffer = AudioRingBuffer()) {
    private val subscriptions = CopyOnWriteArrayList<AudioSubscription>()

    /** Adds a subscriber for [kind]. Returns the subscription ID. */
    fun subscribe(
        kind: AudioSubscriberKind,
        id: String = UUID.randomUUID().toString(),
        onChunk: (ByteArray) -> Unit,
        onError: ((Throwable) -> Unit)? = null,
    ): String {
        subscriptions.removeIf { it.id == id }
        subscriptions.add(AudioSubscription(id, kind, onChunk, onError))
        return id
    }

    /** Removes the subscriber with [id]. Returns `true` if removed. */
    fun unsubscribe(id: String): Boolean =
        subscriptions.removeIf { it.id == id }

    /** Removes all subscribers of [kind]. */
    fun unsubscribeKind(kind: AudioSubscriberKind) {
        subscriptions.removeIf { it.kind == kind }
    }

    /** Whether any subscribers are registered. */
    fun hasSubscribers(): Boolean = subscriptions.isNotEmpty()

    /** Whether any subscriber of [kind] is registered. */
    fun hasSubscriber(kind: AudioSubscriberKind): Boolean =
        subscriptions.any { it.kind == kind }

    /** Number of active subscribers. */
    val subscriberCount: Int get() = subscriptions.size

    /** Retrieves the most recent [ms] milliseconds from the ring buffer. */
    fun getPreRollMs(ms: Long): ByteArray = ringBuffer.readRecentMs(ms)

    /** Appends [pcm] to the ring buffer and delivers it to active subscribers. */
    fun dispatchChunk(pcm: ByteArray) {
        ringBuffer.append(pcm)

        val sessions = subscriptions.filter { it.kind == AudioSubscriberKind.SESSION }
        val enrolls = subscriptions.filter { it.kind == AudioSubscriberKind.ENROLL }

        if (sessions.isNotEmpty()) {
            for (sub in sessions) {
                try {
                    sub.onChunk(pcm)
                } catch (e: Throwable) {
                    sub.onError?.invoke(e)
                }
            }
        }

        if (enrolls.isNotEmpty()) {
            for (sub in enrolls) {
                try {
                    sub.onChunk(pcm)
                } catch (e: Throwable) {
                    sub.onError?.invoke(e)
                }
            }
        }

        // WAKE is only dispatched when no dialogue session or enrollment is active.
        if (sessions.isEmpty() && enrolls.isEmpty()) {
            val wakes = subscriptions.filter { it.kind == AudioSubscriberKind.WAKE }
            for (sub in wakes) {
                try {
                    sub.onChunk(pcm)
                } catch (e: Throwable) {
                    sub.onError?.invoke(e)
                }
            }
        }
    }

    /** Dispatches [error] to all active subscribers. */
    fun dispatchError(error: Throwable) {
        for (sub in subscriptions) {
            sub.onError?.invoke(error)
        }
    }

    /** Resets the ring buffer and frees all subscribers. */
    fun clear() {
        ringBuffer.clear()
        subscriptions.clear()
    }
}
