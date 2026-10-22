package app.wendelin

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** WP118: the call path for the answer, its restore and the wake-word exception. */
class SpeechRouteTest {
    private class FakeAudio(
        override val sdk: Int = 34,
        override var mode: Int = 0,
        override var speakerphoneOn: Boolean = false,
        override var communicationDevice: Any? = null,
        var external: Boolean = false,
        var speaker: Any? = "speaker",
    ) : RouteAudio {
        override fun builtinSpeaker(): Any? = speaker

        override fun externalOutputActive(): Boolean = external
    }

    private val routes = mutableListOf<SpeechRoute>()

    // The state is per process: every test gives it back.
    @After
    fun giveBack() = routes.forEach { it.leave() }

    private fun route(a: FakeAudio, log: MutableList<String> = mutableListOf()) =
        SpeechRoute(a) { log += it }.also { routes += it }

    @Test
    fun enterSwitchesToCommunicationAndSpeakerFromApi31() {
        val a = FakeAudio(sdk = 34)
        assertEquals("speaker", route(a).enter())
        assertEquals(3, a.mode)
        assertEquals("speaker", a.communicationDevice)
        assertFalse(a.speakerphoneOn)
        assertTrue(SpeechRoute.active)
    }

    @Test
    fun enterUsesSpeakerphoneBeforeApi31() {
        val a = FakeAudio(sdk = 30)
        route(a).enter()
        assertEquals(3, a.mode)
        assertTrue(a.speakerphoneOn)
        assertNull(a.communicationDevice)
    }

    @Test
    fun headsetOrBluetoothKeepsTheirOutput() {
        val a = FakeAudio(sdk = 34, external = true)
        assertEquals("external", route(a).enter())
        assertEquals(3, a.mode)
        assertNull(a.communicationDevice)
        assertFalse(a.speakerphoneOn)
    }

    @Test
    fun leaveRestoresTheStateBefore() {
        val a = FakeAudio(sdk = 34, mode = 0, communicationDevice = "bt")
        val r = route(a)
        r.enter()
        r.leave()
        assertEquals(0, a.mode)
        assertEquals("bt", a.communicationDevice)
        assertFalse(SpeechRoute.active)
    }

    // Documentation of the contract, not a regression guard: leave() restores the mode saved
    // at enter(), whatever the player set meanwhile. audioplayers sets audioManager.mode only
    // when its context changes (WrappedPlayer.kt:159-171), not at every play.
    @Test
    fun leaveRestoresModeSavedBeforeThePlayerTouchedIt() {
        val a = FakeAudio(sdk = 34, mode = 0)
        val r = route(a)
        r.enter()
        a.mode = 0
        a.mode = SpeechRoute.MODE_IN_COMMUNICATION
        r.leave()
        assertEquals(0, a.mode)
    }

    @Test
    fun leaveRestoresSpeakerphoneBeforeApi31() {
        val a = FakeAudio(sdk = 30, mode = 0, speakerphoneOn = false)
        val r = route(a)
        r.enter()
        r.leave()
        assertEquals(0, a.mode)
        assertFalse(a.speakerphoneOn)
    }

    @Test
    fun enterAndLeaveAreIdempotent() {
        val a = FakeAudio(sdk = 34, mode = 0)
        val r = route(a)
        r.enter()
        r.enter() // must not save mode 3 as "before"
        r.leave()
        r.leave()
        assertEquals(0, a.mode)
        assertFalse(SpeechRoute.active)
        r.leave() // without enter: nothing
        assertEquals(0, a.mode)
    }

    @Test
    fun failedEnterLeavesNoModeBehind() {
        var m = 0
        val a = object : RouteAudio {
            override val sdk = 34
            override var mode: Int
                get() = m
                set(v) {
                    m = v
                }
            override var speakerphoneOn = false
            override var communicationDevice: Any?
                get() = null
                set(_) = throw IllegalStateException("device")
            override fun builtinSpeaker(): Any? = "speaker"
            override fun externalOutputActive() = false
        }
        try {
            SpeechRoute(a).enter()
            fail("expected exception")
        } catch (e: IllegalStateException) {
            // expected
        }
        assertEquals(0, m)
        assertFalse(SpeechRoute.active)
    }

    @Test
    fun leaveRestoresModeEvenIfTheDeviceFails() {
        var m = 0
        var failing = false
        val a = object : RouteAudio {
            override val sdk = 34
            override var mode: Int
                get() = m
                set(v) {
                    m = v
                }
            override var speakerphoneOn = false
            override var communicationDevice: Any? = null
                set(v) {
                    if (failing) throw IllegalStateException("device")
                    field = v
                }
            override fun builtinSpeaker(): Any? = "speaker"
            override fun externalOutputActive() = false
        }
        val r = SpeechRoute(a)
        r.enter()
        failing = true
        try {
            r.leave()
            fail("expected exception")
        } catch (e: IllegalStateException) {
            // expected
        }
        assertEquals(0, m)
        assertFalse(SpeechRoute.active)
    }

    @Test
    fun ownCommunicationModeIsNoCall() {
        assertNull(WakePolicy.conflict(audioMode = 3, foreignRecording = false, ownCommunication = true))
    }

    @Test
    fun otherAppsCommunicationModeStillIsACall() {
        assertEquals("call", WakePolicy.conflict(audioMode = 3, foreignRecording = false, ownCommunication = false))
    }

    @Test
    fun realPhoneCallIsStillACallDuringOwnAnswer() {
        assertEquals("call", WakePolicy.conflict(audioMode = 2, foreignRecording = false, ownCommunication = true))
        assertEquals("call", WakePolicy.conflict(audioMode = 4, foreignRecording = false, ownCommunication = true))
    }

    @Test
    fun foreignRecordingIsStillFoundDuringOwnAnswer() {
        assertEquals("recording", WakePolicy.conflict(audioMode = 3, foreignRecording = true, ownCommunication = true))
    }

    @Test
    fun watcherDecisionKnowsTheOwnCommunicationMode() {
        val r = route(FakeAudio())
        assertEquals("call", WakePolicy.conflictNow(audioMode = 3, foreignRecording = false))
        r.enter()
        assertNull(WakePolicy.conflictNow(audioMode = 3, foreignRecording = false))
        r.leave()
        assertEquals("call", WakePolicy.conflictNow(audioMode = 3, foreignRecording = false))
    }

    @Test
    fun watcherReasonIgnoresOnlyTheOwnCallMode() {
        val r = route(FakeAudio())
        assertEquals("call", WakeConflictWatcher.reasonFor(3, 7, emptyList()))
        r.enter()
        assertNull(WakeConflictWatcher.reasonFor(3, 7, emptyList()))
        assertEquals("call", WakeConflictWatcher.reasonFor(2, 7, emptyList()))
    }

    @Test
    fun watcherReasonCountsOnlyForeignUnsilencedRecordings() {
        val own = RecordingClient(7, false)
        val foreign = RecordingClient(8, false)
        val silenced = RecordingClient(9, true)
        assertEquals("recording", WakeConflictWatcher.reasonFor(0, 7, listOf(foreign)))
        assertEquals("recording", WakeConflictWatcher.reasonFor(0, 7, listOf(own, silenced, foreign)))
        assertNull(WakeConflictWatcher.reasonFor(0, 7, listOf(own)))
        assertNull(WakeConflictWatcher.reasonFor(0, 7, listOf(silenced)))
    }

    @Test
    fun disposeReleasesOnlyTheOwnPartOfTheCallPath() {
        val a = FakeAudio(sdk = 34, mode = 0)
        val main = route(a)
        val overlay = route(a)
        main.enter()
        overlay.enter()
        val released = mutableListOf<String>()
        releaseAll(listOf("duck", "listen"), { released += it }, overlay)
        assertEquals(listOf("duck", "listen"), released)
        assertEquals(3, a.mode) // the other route still answers
        assertTrue(SpeechRoute.active)
    }

    @Test
    fun twoRoutesShareOneState() {
        val a = FakeAudio(sdk = 34, mode = 0)
        val main = route(a)
        val overlay = route(a)
        main.enter()
        overlay.enter() // must not save mode 3 as "before"
        main.leave()
        assertEquals(0, a.mode)
        assertFalse(SpeechRoute.active)
        overlay.leave()
        assertEquals(0, a.mode)
    }

    @Test
    fun releaseOfOneRouteKeepsTheCallPathForTheOther() {
        val a = FakeAudio(sdk = 34, mode = 0)
        val main = route(a)
        val overlay = route(a)
        main.enter()
        overlay.enter()
        overlay.release() // its activity is destroyed while the other still answers
        assertEquals(3, a.mode)
        assertTrue(SpeechRoute.active)
        main.release()
        assertEquals(0, a.mode)
        assertFalse(SpeechRoute.active)
    }

    @Test
    fun releaseOfARouteThatNeverEnteredChangesNothing() {
        val a = FakeAudio(sdk = 34, mode = 0)
        val main = route(a)
        val idle = route(a)
        main.enter()
        idle.release()
        assertEquals(3, a.mode)
        assertTrue(SpeechRoute.active)
        main.release()
        assertEquals(0, a.mode)
    }

    @Test
    fun releaseOfTheOnlyHolderGivesTheStateBack() {
        val a = FakeAudio(sdk = 34, mode = 0)
        val r = route(a)
        r.enter()
        r.release()
        assertEquals(0, a.mode)
        assertFalse(SpeechRoute.active)
    }

    @Test
    fun activeStaysTrueUntilTheModeIsRestored() {
        val seen = mutableListOf<Boolean>()
        val a = object : RouteAudio {
            override val sdk = 34
            override var mode = 0
                set(v) {
                    seen += SpeechRoute.active
                    field = v
                }
            override var speakerphoneOn = false
            override var communicationDevice: Any? = null
            override fun builtinSpeaker(): Any? = "speaker"
            override fun externalOutputActive() = false
        }
        val r = SpeechRoute(a).also { routes += it }
        r.enter()
        r.leave()
        assertEquals(listOf(true, true), seen)
    }
}
