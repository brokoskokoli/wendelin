package app.wendelin

import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min

/** What happens around the station that could end it (WP99, K62/K63). */
enum class StationEvent {
    /** The button „Beenden“ after the keyguard was dismissed. */
    END_UNLOCKED,
    /** The charger is unplugged. */
    UNPLUG,
    BACK,
    HOME,
    SCREEN_OFF,
    /** Any voice command, wake word included. */
    VOICE,
}

/**
 * Whether the station is up. [active] follows visibility (onStart/onStop) and is read by the wake
 * word routing: the station is never the chat. [open] (WP171) holds from onCreate to onDestroy,
 * also with a dark screen, lock or home: it alone keeps the wake word forced on. Both are static,
 * so a process death resets them.
 */
object StationState {
    @Volatile var active = false
    @Volatile var open = false

    fun created() { open = true }
    fun started() { active = true }
    fun stopped() { active = false }

    /** Returns whether the station ended (false for a recreate: the new instance sets [open] again). */
    fun destroyed(changingConfigurations: Boolean): Boolean {
        active = false
        if (changingConfigurations) return false
        open = false
        return true
    }
}

/** Pure rules of the station mode; the activity and the channels only apply them. */
object StationPolicy {
    /** The station ends only by the button after unlocking: nothing else ends it. */
    fun endsOn(event: StationEvent): Boolean = event == StationEvent.END_UNLOCKED

    /** The activity closes only while the keyguard is not showing (after `requestDismissKeyguard`). */
    fun mayFinish(locked: Boolean): Boolean = !locked

    /** `finish` from Dart: the overlay always closes; the station only while the keyguard is not showing. */
    fun finishAllowed(isStation: Boolean, locked: Boolean): Boolean = !isStation || mayFinish(locked)

    /** Runs [finish] if allowed; the result is what Dart hears (`false`: refused, nothing was closed). */
    fun finishIfAllowed(isStation: Boolean, locked: Boolean, finish: () -> Unit): Boolean {
        if (!finishAllowed(isStation, locked)) return false
        finish()
        return true
    }

    /** The voice command „Stationsmodus“ starts only on an unlocked device. */
    fun voiceStartAllowed(locked: Boolean): Boolean = !locked

    /** The quick tile starts after unlocking: a locked device asks first. */
    fun tileNeedsUnlock(locked: Boolean): Boolean = locked

    /** Window brightness for an ambient light of [lux]: dim, never fully off, up to 1.0 by day. */
    fun brightnessFor(lux: Float): Float {
        if (lux <= 1f) return MIN_BRIGHTNESS
        val x = ln(lux) / ln(DAYLIGHT_LUX)
        return max(MIN_BRIGHTNESS, min(MAX_BRIGHTNESS, MIN_BRIGHTNESS + x * (MAX_BRIGHTNESS - MIN_BRIGHTNESS)))
    }

    /** Quiet hours: nearly black. */
    const val QUIET_BRIGHTNESS = 0.01f

    /** Whether the room counts as dark (muted colors). */
    fun isDark(lux: Float): Boolean = lux < DARK_LUX

    const val MIN_BRIGHTNESS = 0.03f
    const val MAX_BRIGHTNESS = 1.0f
    private const val DAYLIGHT_LUX = 1000f
    private const val DARK_LUX = 15f
}
