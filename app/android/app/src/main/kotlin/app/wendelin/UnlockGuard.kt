package app.wendelin

/**
 * Tells whether the overlay is in the middle of unlocking the device (WP114, K85).
 *
 * Dismissing the keyguard moves the activity through `onStop` and the Flutter lifecycle
 * (hidden/paused), often after `onDismissSucceeded` already ran. That must not count as
 * "the user left the overlay": the guard stays active while a request is open and for
 * [GRACE_MS] after it ended (success, cancel or error alike).
 */
class UnlockGuard(private val now: () -> Long) {
    private var pending = false
    private var endedAt: Long? = null

    /** An unlock request (keyguard) starts. */
    fun begin() {
        pending = true
        endedAt = null
    }

    /** The unlock request ended, whatever the result. */
    fun end() {
        pending = false
        endedAt = now()
    }

    /** Whether leaving the overlay now belongs to the unlock transition. */
    fun active(): Boolean {
        if (pending) return true
        val ended = endedAt ?: return false
        return now() - ended < GRACE_MS
    }

    /**
     * How long until [active] can turn false (0 if it is not active). While a request is open it
     * is one full [GRACE_MS]: look again then.
     */
    fun remainingMs(): Long {
        if (pending) return GRACE_MS
        val ended = endedAt ?: return 0L
        return (GRACE_MS - (now() - ended)).coerceAtLeast(0L)
    }

    companion object {
        /** How long after the keyguard result the lifecycle changes still count as unlocking. */
        const val GRACE_MS = 1500L
    }
}
