package app.wendelin

/**
 * WP188 part E: a chosen Bluetooth microphone is used only while a dialog runs. This file is the
 * pure logic (no Android types, tested on the JVM): when the phone mode is wanted, the state
 * machine that sets it up and takes it down again, and the flag that tells our own phone mode
 * from a real call ([WakePolicy.conflict]).
 */
internal object OwnCommMode {
    /** `true` from just before the service sets `MODE_IN_COMMUNICATION` until it is back to normal. */
    @Volatile var active = false
}

internal object DialogBluetooth {
    /** The dialog report of the app is only believed this long without a renewal (it repeats every 60 s). */
    const val MAX_SILENT_MS = 90_000L

    /** How often a running phone mode is re-checked (watchdog for a lost end). */
    const val TICK_MS = 5_000L

    private val BLUETOOTH_NAMES = setOf("bluetooth_sco", "bluetooth_le")
    private val BLUETOOTH_TYPES = setOf(7, 26, 27)

    /** Whether the chosen microphone is a Bluetooth one (SCO or LE). */
    fun isBluetoothChoice(selected: AudioDeviceEntry?): Boolean = selected?.type in BLUETOOTH_NAMES

    /**
     * The connected Bluetooth device of the choice among [devices] (inputs and outputs together:
     * the microphone half of a SCO headset may only show once the link is up, its speaker half
     * is there), else `null`. Same key rule as the choice list, ignoring the direction.
     */
    fun connected(selected: AudioDeviceEntry?, devices: List<AudioDeviceDesc>): AudioDeviceDesc? {
        if (!isBluetoothChoice(selected)) return null
        val type = selected!!.key.substringBefore('|').toIntOrNull() ?: return null
        return devices.firstOrNull {
            it.type in BLUETOOTH_TYPES && AudioDevicePick.keyOf(it.copy(type = type)) == selected.key
        }
    }

    /** The phone mode is wanted only with a dialog, a running central microphone and a connected headset. */
    fun wanted(dialogActive: Boolean, micRunning: Boolean, headsetConnected: Boolean): Boolean =
        dialogActive && micRunning && headsetConnected
}

/** Which step the phone mode needs next. */
internal enum class CommStep { NONE, ENTER, LEAVE }

/**
 * Whether we hold the phone mode. [next] marks it as held already when it asks for [CommStep.ENTER],
 * so a half-done setup is still taken down by the following [CommStep.LEAVE] (fail-safe).
 */
internal class CommModeState {
    var engaged = false
        private set

    fun next(wanted: Boolean): CommStep = when {
        wanted && !engaged -> { engaged = true; CommStep.ENTER }
        !wanted && engaged -> { engaged = false; CommStep.LEAVE }
        else -> CommStep.NONE
    }
}

/**
 * Sets the phone mode up for a dialog and takes it down in every case. [evaluate] is called on
 * every event that can change the answer (dialog report, devices, choice, microphone start/stop)
 * and by the watchdog tick that runs as long as the mode is held: a dialog end that never arrives
 * or a crashed dialog is noticed there ([Ops.dialogActive] counts a report only for
 * [DialogBluetooth.MAX_SILENT_MS]). [release] takes it down unconditionally (service stop).
 */
internal class DialogMicController(private val ops: Ops) {
    interface Ops {
        fun dialogActive(): Boolean
        fun micRunning(): Boolean
        fun headsetConnected(): Boolean

        /** Sets the phone mode and the communication route; may throw (the controller then still leaves later). */
        fun enter()

        /** Back to normal; must not leave anything set even if a part fails. */
        fun leave()

        /** The wanted microphone route may have changed (the recording follows it). */
        fun routeChanged()
        fun schedule(delayMs: Long, task: Runnable)
        fun cancel(task: Runnable)
        fun log(line: String)
    }

    private val state = CommModeState()
    private val tick = Runnable { evaluate() }

    val engaged: Boolean get() = state.engaged

    fun evaluate() {
        ops.cancel(tick)
        val wanted = try {
            DialogBluetooth.wanted(ops.dialogActive(), ops.micRunning(), ops.headsetConnected())
        } catch (e: RuntimeException) {
            false // unreadable state: not wanted (fail-safe, takes the mode down)
        }
        when (state.next(wanted)) {
            CommStep.ENTER -> {
                try {
                    ops.enter()
                    ops.log("wake-dialog-bt enter")
                } catch (e: RuntimeException) {
                    ops.log("wake-dialog-bt enter-failed=${e.javaClass.simpleName}")
                    // Half set up: back to normal at once; no retry until the wish has been off once.
                    leaveSafely()
                }
                ops.routeChanged()
            }
            CommStep.LEAVE -> {
                leaveSafely()
                ops.routeChanged()
            }
            CommStep.NONE -> Unit
        }
        if (state.engaged) ops.schedule(DialogBluetooth.TICK_MS, tick)
    }

    /** Takes the mode down at once (service stop, engine gone), whatever the state says. */
    fun release() {
        ops.cancel(tick)
        if (state.next(false) == CommStep.LEAVE) leaveSafely()
    }

    private fun leaveSafely() {
        try {
            ops.leave()
            ops.log("wake-dialog-bt leave")
        } catch (e: RuntimeException) {
            ops.log("wake-dialog-bt leave-failed=${e.javaClass.simpleName}")
        }
    }
}
