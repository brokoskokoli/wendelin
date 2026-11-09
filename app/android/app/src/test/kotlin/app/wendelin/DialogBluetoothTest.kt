package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** WP188 part E: Bluetooth microphone only in the dialog, phone mode taken down in every case. */
class DialogBluetoothTest {
    private fun desc(type: Int, product: String, address: String, source: Boolean = true, sink: Boolean = false) =
        AudioDeviceDesc(type, product, address, source, sink)

    private val scoIn = desc(7, "Buds", "AA:BB:CC:DD:EE:FF")
    private val scoOut = desc(7, "Buds", "AA:BB:CC:DD:EE:FF", source = false, sink = true)
    private fun entry(d: AudioDeviceDesc, type: String = "bluetooth_sco") =
        AudioDeviceEntry(AudioDevicePick.keyOf(d), type, d.product)

    // --- Choice and connection ---

    @Test
    fun bluetoothChoiceIsFoundThroughItsSpeakerHalfBeforeTheLinkIsUp() {
        assertEquals(scoOut, DialogBluetooth.connected(entry(scoIn), listOf(scoOut)))
        assertNull(DialogBluetooth.connected(entry(scoIn), listOf(desc(15, "Phone", ""))))
    }

    @Test
    fun otherChoicesAreNoBluetoothChoice() {
        val usb = desc(11, "USB", "")
        assertFalse(DialogBluetooth.isBluetoothChoice(entry(usb, "usb")))
        assertFalse(DialogBluetooth.isBluetoothChoice(null))
        assertNull(DialogBluetooth.connected(entry(usb, "usb"), listOf(usb, scoIn)))
    }

    @Test
    fun bluetoothInputIsTargetOnlyWhileThePhoneModeIsHeld() {
        val e = entry(scoIn)
        assertNull(MicRoute.target(e, listOf(scoIn)))
        assertNull(MicRoute.target(e, listOf(scoIn), dialogBluetooth = false))
        assertEquals(e.key, MicRoute.target(e, listOf(scoIn), dialogBluetooth = true))
    }

    @Test
    fun wishNeedsDialogMicAndHeadset() {
        assertTrue(DialogBluetooth.wanted(true, true, true))
        assertFalse(DialogBluetooth.wanted(false, true, true))
        assertFalse(DialogBluetooth.wanted(true, false, true))
        assertFalse(DialogBluetooth.wanted(true, true, false))
    }

    // --- Own phone mode versus a real call ---

    @Test
    fun ownCommunicationModeIsNoCall() {
        assertNull(WakePolicy.conflict(audioMode = 3, foreignRecording = false, ownCommMode = true))
        assertNull(WakeConflictWatcher.reasonFor(3, setOf(1), emptyList(), ownCommMode = true))
    }

    @Test
    fun foreignCommunicationModeIsStillACall() {
        assertEquals("call", WakePolicy.conflict(audioMode = 3, foreignRecording = false, ownCommMode = false))
    }

    @Test
    fun realCallDuringOwnModeIsStillRecognised() {
        // Cellular call: mode 2 (or call screening 4) whatever we hold.
        assertEquals("call", WakePolicy.conflict(audioMode = 2, foreignRecording = false, ownCommMode = true))
        assertEquals("call", WakePolicy.conflict(audioMode = 4, foreignRecording = false, ownCommMode = true))
        // Voice call of another app: it records in its own session.
        val foreign = listOf(RecordingClient(1, false), RecordingClient(99, false))
        assertEquals("recording", WakeConflictWatcher.reasonFor(3, setOf(1), foreign, ownCommMode = true))
        // A silenced foreign recording does not count.
        assertNull(WakeConflictWatcher.reasonFor(3, setOf(1), listOf(RecordingClient(99, true)), ownCommMode = true))
    }

    // --- AppVoice as the dialog signal ---

    @Test
    fun staleDialogReportStopsCountingBeforeTheLongCap() {
        AppVoice.reset()
        AppVoice.set("a", true, 1_000L)
        assertTrue(AppVoice.activeWithin(1_000L + DialogBluetooth.MAX_SILENT_MS - 1, DialogBluetooth.MAX_SILENT_MS))
        assertFalse(AppVoice.activeWithin(1_000L + DialogBluetooth.MAX_SILENT_MS, DialogBluetooth.MAX_SILENT_MS))
        AppVoice.set("a", true, 50_000L) // heartbeat renews
        assertTrue(AppVoice.activeWithin(100_000L, DialogBluetooth.MAX_SILENT_MS))
        AppVoice.reset()
    }

    // --- Controller ---

    private class Rig {
        var dialog = false
        var mic = true
        var headset = true
        var enterFails = false
        var leaveFails = false
        var held = false
        var enters = 0
        var leaves = 0
        var routeChanges = 0
        val tasks = mutableListOf<Runnable>()
        val lines = mutableListOf<String>()
        val ops = object : DialogMicController.Ops {
            override fun dialogActive() = dialog
            override fun micRunning() = mic
            override fun headsetConnected() = headset
            override fun enter() {
                enters++
                held = true
                if (enterFails) throw IllegalStateException("x")
            }
            override fun leave() {
                leaves++
                held = false
                if (leaveFails) throw IllegalStateException("x")
            }
            override fun routeChanged() { routeChanges++ }
            override fun schedule(delayMs: Long, task: Runnable) { tasks += task }
            override fun cancel(task: Runnable) { tasks -= task }
            override fun log(line: String) { lines += line }
        }
        val c = DialogMicController(ops)
        fun fireTick() = tasks.toList().also { tasks.clear() }.forEach { it.run() }
    }

    @Test
    fun noPhoneModeWithoutDialog_wakeWordStaysOnThePhoneMic() {
        val r = Rig()
        r.c.evaluate()
        assertEquals(0, r.enters)
        assertFalse(r.held)
        assertTrue(r.tasks.isEmpty())
    }

    @Test
    fun dialogStartsAndEndsThePhoneMode() {
        val r = Rig()
        r.dialog = true
        r.c.evaluate()
        assertTrue(r.held)
        assertEquals(1, r.routeChanges)
        r.c.evaluate() // same state again: nothing new
        assertEquals(1, r.enters)
        r.dialog = false
        r.c.evaluate()
        assertFalse(r.held)
        assertEquals(1, r.leaves)
        assertEquals(2, r.routeChanges)
        assertTrue(r.tasks.isEmpty())
    }

    @Test
    fun watchdogEndsTheModeWhenTheDialogEndIsNeverReported() {
        val r = Rig()
        r.dialog = true
        r.c.evaluate()
        r.fireTick()
        assertTrue(r.held)
        // The report ran out (AppVoice.activeWithin turns false), no event arrives, only the tick.
        r.dialog = false
        r.fireTick()
        assertFalse(r.held)
        assertEquals(1, r.leaves)
    }

    @Test
    fun abortedDialogMicStopOrErrorTakesTheModeDown() {
        val r = Rig()
        r.dialog = true
        r.c.evaluate()
        r.c.release() // stopMic: error, conflict, service stop
        assertFalse(r.held)
        assertFalse(r.c.engaged)
        assertTrue(r.tasks.isEmpty())
        r.c.release() // idempotent
        assertEquals(1, r.leaves)
    }

    @Test
    fun microphoneGoneOrHeadsetLostTakesTheModeDown() {
        val r = Rig()
        r.dialog = true
        r.c.evaluate()
        r.headset = false
        r.c.evaluate()
        assertFalse(r.held)
        r.headset = true
        r.c.evaluate() // back: new dialog phase continues, the mode is set again
        assertTrue(r.held)
        r.mic = false
        r.c.evaluate()
        assertFalse(r.held)
        assertEquals(2, r.leaves)
    }

    @Test
    fun failedSetupIsUndoneAtOnceAndNotRetriedInALoop() {
        val r = Rig()
        r.dialog = true
        r.enterFails = true
        r.c.evaluate()
        assertFalse(r.held)
        assertEquals(1, r.leaves)
        r.fireTick()
        r.fireTick()
        assertEquals(1, r.enters)
        r.dialog = false
        r.c.evaluate() // wish off once: engaged is cleared
        r.dialog = true
        r.enterFails = false
        r.c.evaluate()
        assertTrue(r.held)
    }

    @Test
    fun failingLeaveStillClearsTheState() {
        val r = Rig()
        r.dialog = true
        r.c.evaluate()
        r.leaveFails = true
        r.dialog = false
        r.c.evaluate()
        assertFalse(r.c.engaged)
        assertTrue(r.tasks.isEmpty())
    }

    @Test
    fun unreadableStateCountsAsNotWanted() {
        val r = Rig()
        r.dialog = true
        r.c.evaluate()
        val c = DialogMicController(object : DialogMicController.Ops by r.ops {
            override fun headsetConnected(): Boolean = throw IllegalStateException("x")
        })
        c.evaluate()
        assertFalse(c.engaged)
    }
}
