package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Start/stop logic of the wake-word service without Android (WP50). */
class WakePolicyTest {
    private val on = WakeSettings(enabled = true)
    private val now = 1_000_000L

    private fun decide(
        s: WakeSettings = on,
        role: Boolean = true,
        mic: Boolean = true,
        charging: Boolean = true,
        station: Boolean = false,
    ) = WakePolicy.decide(s, role, mic, charging, now, station)

    @Test
    fun startsWhenEverythingFits() {
        assertEquals(WakeDecision.Start, decide())
    }

    @Test
    fun theReasonsComeInAFixedOrder() {
        assertEquals(WakeDecision.Skip("disabled"), decide(WakeSettings(), role = false, mic = false))
        assertEquals(WakeDecision.Skip("no-role"), decide(role = false, mic = false))
        assertEquals(WakeDecision.Skip("no-permission"), decide(mic = false))
        assertEquals(
            WakeDecision.Skip("paused"),
            decide(on.copy(pausedUntilMs = now + 1, mode = WakeMode.CHARGING), charging = false),
        )
        assertEquals(WakeDecision.Skip("not-charging"), decide(charging = false))
    }

    @Test
    fun callAndForeignRecordingCloseTheMicrophoneInTheService() {
        assertTrue(WakePolicy.closesMicFor("call"))
        assertTrue(WakePolicy.closesMicFor("recording"))
        assertFalse(WakePolicy.closesMicFor(null))
    }

    @Test
    fun handoffOverlapKeepsTheMicrophoneOpenForTheAppsOwnRecording() {
        // WP149: the app's new AudioRecord looks like a foreign recording during the overlap.
        assertFalse(WakePolicy.closesMicFor("recording", handoffOverlap = true))
        assertTrue(WakePolicy.closesMicFor("recording", handoffOverlap = false))
        // A call always closes it, overlap or not.
        assertTrue(WakePolicy.closesMicFor("call", handoffOverlap = true))
        assertFalse(WakePolicy.closesMicFor(null, handoffOverlap = true))
        // Dart may still not start the microphone while the conflict holds.
        assertFalse(WakePolicy.mayStartMic("recording"))
        assertEquals(
            "wake-conflict reason=recording handoff=kept action=keep",
            WakePolicy.conflictLog("recording", true, false),
        )
    }

    @Test
    fun stationKeepsTheWakeWordOnWhateverTheSettingsSay() {
        val off = WakeSettings(enabled = false)
        assertEquals(WakeDecision.Start, decide(off, station = true))
        val chargingOnly = on.copy(mode = WakeMode.CHARGING)
        assertEquals(WakeDecision.Start, decide(chargingOnly, charging = false, station = true))
        assertEquals(WakeDecision.Start, decide(off.copy(mode = WakeMode.CHARGING), charging = false, station = true))
        // Without the station nothing changes.
        assertEquals(WakeDecision.Skip("disabled"), decide(off))
        assertEquals(WakeDecision.Skip("not-charging"), decide(chargingOnly, charging = false))
    }

    @Test
    fun stationStillNeedsRoleMicAndRespectsAPause() {
        val off = WakeSettings(enabled = false)
        assertEquals(WakeDecision.Skip("no-role"), decide(off, role = false, station = true))
        assertEquals(WakeDecision.Skip("no-permission"), decide(off, mic = false, station = true))
        assertEquals(WakeDecision.Skip("paused"), decide(on.copy(pausedUntilMs = now + 1), station = true))
    }

    @Test
    fun forcedByStationOnlyWhenTheSettingsWouldNotStart() {
        val chargingOnly = on.copy(mode = WakeMode.CHARGING)
        assertTrue(WakePolicy.forcedByStation(WakeSettings(enabled = false), true, true))
        assertTrue(WakePolicy.forcedByStation(chargingOnly, false, true))
        assertFalse(WakePolicy.forcedByStation(chargingOnly, true, true))
        assertFalse(WakePolicy.forcedByStation(on.copy(mode = WakeMode.ALWAYS), false, true))
        assertFalse(WakePolicy.forcedByStation(WakeSettings(enabled = false), true, false))
    }

    @Test
    fun alwaysModeIgnoresCharging() {
        assertEquals(WakeDecision.Start, decide(on.copy(mode = WakeMode.ALWAYS), charging = false))
    }

    @Test
    fun aPauseEndsAtItsTime() {
        assertEquals(WakeDecision.Start, decide(on.copy(pausedUntilMs = now)))
        assertEquals(WakeDecision.Start, decide(on.copy(pausedUntilMs = now - 5)))
    }

    @Test
    fun unpluggingStopsOnlyTheChargingMode() {
        assertTrue(WakePolicy.stopsOnUnplug(WakeMode.CHARGING, charging = false))
        assertFalse(WakePolicy.stopsOnUnplug(WakeMode.CHARGING, charging = true))
        assertFalse(WakePolicy.stopsOnUnplug(WakeMode.ALWAYS, charging = false))
    }

    @Test
    fun inCommunicationModeIsAlwaysACall() {
        // WP165: the app sets no communication mode itself, so mode 3 is never its own.
        assertEquals("call", WakePolicy.conflict(audioMode = 3, foreignRecording = false))
        assertEquals("call", WakeConflictWatcher.reasonFor(audioMode = 3, ownSession = 1, clients = emptyList()))
    }

    @Test
    fun callsAndForeignRecordingsNeedTheMicrophone() {
        assertEquals("call", WakePolicy.conflict(audioMode = 2, foreignRecording = false))
        assertEquals("call", WakePolicy.conflict(audioMode = 3, foreignRecording = true))
        assertEquals("call", WakePolicy.conflict(audioMode = 4, foreignRecording = false))
        assertEquals("recording", WakePolicy.conflict(audioMode = 0, foreignRecording = true))
        assertNull(WakePolicy.conflict(audioMode = 0, foreignRecording = false))
        assertNull(WakePolicy.conflict(audioMode = 1, foreignRecording = false))
    }

    @Test
    fun theDefaultModeIsChargingAndUnknownValuesFallBack() {
        assertEquals(WakeMode.CHARGING, WakeSettings().mode)
        assertEquals(WakeMode.ALWAYS, WakeMode.parse("always"))
        assertEquals(WakeMode.CHARGING, WakeMode.parse("nonsense"))
        assertEquals(WakeMode.CHARGING, WakeMode.parse(null))
    }

    @Test
    fun stationFlagFollowsOpenNotActive() {
        // WP171: screen dark = activity stopped (active false), the station is still open: the detector stays.
        val (oldOpen, oldActive) = StationState.open to StationState.active
        try {
            StationState.open = true
            StationState.active = false
            assertEquals(true, WakeSettings().runArgsForStation()["station"])
            StationState.open = false
            StationState.active = true
            assertEquals(false, WakeSettings().runArgsForStation()["station"])
        } finally {
            StationState.open = oldOpen
            StationState.active = oldActive
        }
    }

    @Test
    fun channelArgumentsChangeOnlyWhatTheyName() {
        val old = WakeSettings(enabled = true, mode = WakeMode.ALWAYS, verify = true, pausedUntilMs = 5)
        assertEquals(old, old.withArgs(null))
        assertEquals(old.copy(verify = false), old.withArgs(mapOf("verify" to false)))
        assertEquals(old.copy(detector = "model"), old.withArgs(mapOf("detector" to "model")))
        assertEquals(old, old.withArgs(mapOf("detector" to "bogus")))
        assertEquals(
            mapOf("verify" to true, "detector" to "auto", "station" to true, "dev" to false),
            WakeSettings().runArgs(stationActive = true),
        )
        // WP148: the developer mode goes to the engine with `run`, `configure` leaves it alone.
        assertEquals(true, WakeSettings(devMode = true).runArgs(stationActive = false)["dev"])
        assertEquals(old.copy(devMode = true), old.copy(devMode = true).withArgs(mapOf("verify" to true)))
        assertEquals(old.copy(mode = WakeMode.CHARGING), old.withArgs(mapOf("mode" to "charging")))
        // Wrong types keep the old values.
        assertEquals(old, old.withArgs(mapOf("enabled" to "yes", "mode" to 3, "verify" to 1)))
        // Switching off also ends a pause.
        assertEquals(WakeSettings(enabled = false, mode = WakeMode.ALWAYS), old.withArgs(mapOf("enabled" to false)))
    }

    @Test
    fun offByUserIsClearedByEveryConfigure() {
        val off = WakeSettings(enabled = false, offByUser = true)
        assertTrue(off.withArgs(null).offByUser)
        assertTrue(off.withArgs(mapOf("verify" to false)).offByUser)
        val on = off.withArgs(mapOf("enabled" to true))
        assertTrue(on.enabled)
        assertFalse(on.offByUser)
        assertFalse(off.withArgs(mapOf("enabled" to false)).offByUser)
    }

    @Test
    fun aHitGoesToTheChatOnlyWhenItIsVisibleUnlockedAndAskable() {
        assertEquals(HitRoute.CHAT, WakePolicy.routeHit(chatVisible = true, locked = false, hostAvailable = true))
        // Settings open, app paused: the flag is off.
        assertEquals(HitRoute.OVERLAY, WakePolicy.routeHit(chatVisible = false, locked = false, hostAvailable = true))
        assertEquals(HitRoute.OVERLAY, WakePolicy.routeHit(chatVisible = true, locked = true, hostAvailable = true))
        assertEquals(HitRoute.OVERLAY, WakePolicy.routeHit(chatVisible = true, locked = false, hostAvailable = false))
    }

    private class FakeScheduler : HitScheduler {
        val tasks = mutableListOf<Runnable>()
        var delay = 0L

        override fun postDelayed(delayMs: Long, task: Runnable) {
            delay = delayMs
            tasks += task
        }

        override fun cancel(task: Runnable) {
            tasks -= task
        }

        /** The time passes: pending tasks run. */
        fun fire() = tasks.toList().also { tasks.clear() }.forEach { it.run() }
    }

    private class Run {
        val sched = FakeScheduler()
        var overlays = 0
        var accepted = 0
        var reply: ((Any?) -> Unit)? = null
        val arbiter = ChatHitArbiter(sched, { overlays++ }, { accepted++ })

        init {
            ChatState.reset()
            arbiter.begin { reply = it }
        }
    }

    @Test
    fun onlyAnInTimeYesTakesTheHitIntoTheChat() {
        val r = Run()
        assertEquals(ChatHitArbiter.ANSWER_MS, r.sched.delay)
        r.reply!!(true)
        assertEquals(1, r.accepted)
        assertEquals(0, r.overlays)
        assertTrue(ChatState.owned)
        // The timeout is gone: nothing opens later.
        assertTrue(r.sched.tasks.isEmpty())
        r.sched.fire()
        assertEquals(0, r.overlays)
    }

    @Test
    fun refusalAndErrorOpenTheOverlay() {
        for (reply in listOf<Any?>(false, null)) {
            val r = Run()
            r.reply!!(reply)
            assertEquals(1, r.overlays)
            assertFalse(ChatState.owned)
            r.sched.fire()
            assertEquals(1, r.overlays)
        }
    }

    @Test
    fun aLateYesAfterTheTimeoutDoesNotMakeTheChatAnOwner() {
        val r = Run()
        r.sched.fire()
        assertEquals(1, r.overlays)
        r.reply!!(true)
        assertEquals(0, r.accepted)
        assertFalse(ChatState.owned)
        assertEquals(1, r.overlays)
    }

    @Test
    fun chatDoneIsOnlyEffectiveForTheOwner() {
        ChatState.reset()
        // The overlay won; the chat that lost the hit reports done: the service stays quiet.
        assertFalse(ChatState.release())
        ChatState.own()
        assertTrue(ChatState.release())
        assertFalse(ChatState.release())
    }

    @Test
    fun theMainAppTakesTheAudioOnlyForAnOwnedHit() {
        assertFalse(WakePolicy.mayTakeHandoff(isMainApp = true, chatOwned = false))
        assertTrue(WakePolicy.mayTakeHandoff(isMainApp = true, chatOwned = true))
        assertTrue(WakePolicy.mayTakeHandoff(isMainApp = false, chatOwned = false))
    }

    @Test
    fun theDebugHitNeedsADebuggableApp() {
        assertTrue(WakePolicy.allowsDebugHit(2 or 8))
        assertFalse(WakePolicy.allowsDebugHit(8))
        assertFalse(WakePolicy.allowsDebugHit(0))
    }

    @Test
    fun pausingTheActivityHidesTheChat() {
        ChatState.reported = true
        ChatState.paused()
        assertFalse(ChatState.visible)
    }

    @Test
    fun startMicWaitsWhileAConflictHolds() {
        assertFalse(WakePolicy.mayStartMic("call"))
        assertFalse(WakePolicy.mayStartMic("recording"))
        assertTrue(WakePolicy.mayStartMic(null))
    }

    @Test
    fun aHitIsHandedOverOnceAndGoesStale() {
        WakeHandoff.clear()
        val pcm = byteArrayOf(1, 2, 3, 4)
        WakeHandoff.put(pcm, 100)
        assertTrue(WakeHandoff.pending())
        assertEquals(pcm.toList(), WakeHandoff.take(200)!!.pcm.toList())
        assertFalse(WakeHandoff.pending())
        assertNull(WakeHandoff.take(300))
        WakeHandoff.put(pcm, 100)
        assertNull(WakeHandoff.take(100 + WakeHandoff.MAX_AGE_MS + 1))
    }

    @Test
    fun theCaptureIsAttachedWithoutGapOrOverlap() {
        WakeHandoff.clear()
        val tap = WakeMicTap()
        // Chunks 0..9 of 480 samples go to Dart (sample value = running index); Dart confirms the
        // hit at position 7 * 480 and its pre-roll ends there; chunks 7..9 were already on the way.
        fun chunk(i: Int) = ByteArray(960) { n -> if (n % 2 == 0) (i * 10).toByte() else 0 }
        for (i in 0 until 10) tap.onChunk(chunk(i))
        val pre = chunk(99)
        WakeHandoff.put(pre, 100, 400)
        WakeHandoff.beginCapture(tap.tailAfter(7L * 480))
        assertTrue(WakeHandoff.capturing())
        WakeHandoff.append(chunk(10))
        WakeHandoff.append(chunk(11))
        val taken = WakeHandoff.take(200)!!
        assertFalse(WakeHandoff.capturing())
        assertEquals(400, taken.wakeEnd)
        // pre-roll + chunks 7..11, each exactly once and in order
        assertEquals(960 * 6, taken.pcm.size)
        val order = (1 until 6).map { taken.pcm[it * 960].toInt() }
        assertEquals(listOf(70, 80, 90, 100, 110), order)
        assertEquals(5 * 480 * 1000L / 16_000, taken.capturedMs)
        // after the take nothing is collected any more
        WakeHandoff.append(chunk(12))
        assertNull(WakeHandoff.take(300))
    }

    @Test
    fun theCaptureStaysOpenAfterTheTakeUntilFinishWp146() {
        WakeHandoff.clear()
        fun chunk(i: Int) = ByteArray(960) { n -> if (n % 2 == 0) i.toByte() else 0 }
        WakeHandoff.put(chunk(99), 100, 400)
        WakeHandoff.beginCapture(chunk(1))
        val taken = WakeHandoff.takeKeepingOpen(200)!!
        // pre-roll + what was collected until the take, exactly once
        assertEquals(960 * 2, taken.pcm.size)
        assertFalse(WakeHandoff.pending())
        // the service keeps recording: the chunks go to the tail, not to the (taken) pre-roll
        assertTrue(WakeHandoff.capturing())
        WakeHandoff.append(chunk(2), 1000)
        WakeHandoff.append(chunk(3), 1030)
        val tail = WakeHandoff.finish()!!
        assertEquals(960 * 2, tail.pcm.size)
        assertEquals(2, tail.pcm[0].toInt())
        assertEquals(3, tail.pcm[960].toInt())
        assertEquals(1030L, tail.lastSampleAtMs)
        // finished: nothing more is collected, a second finish has nothing
        assertFalse(WakeHandoff.capturing())
        WakeHandoff.append(chunk(4), 1060)
        assertNull(WakeHandoff.finish())
    }

    @Test
    fun aStaleHitIsNotKeptOpenWp146() {
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(2), 100)
        WakeHandoff.beginCapture(ByteArray(0))
        assertNull(WakeHandoff.takeKeepingOpen(100 + WakeHandoff.MAX_AGE_MS + 1))
        assertFalse(WakeHandoff.capturing())
    }

    @Test
    fun aStaleCaptureFlagDoesNotMakeTheWakeWordDeaf() {
        // Service ended during a handover: release() clears the hit, the flag is gone.
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(2), 0)
        WakeHandoff.beginCapture(ByteArray(0))
        assertTrue(WakePolicy.ignoresMicCalls(WakeHandoff.capturing(), micOpen = true))
        WakeHandoff.clear()
        assertFalse(WakeHandoff.capturing())
        assertFalse(WakePolicy.ignoresMicCalls(WakeHandoff.capturing(), micOpen = true))
        // A flag without an open microphone does not block the restart either.
        assertFalse(WakePolicy.ignoresMicCalls(capturing = true, micOpen = false))
    }

    @Test
    fun theTimeOfTheLastCollectedChunkIsHandedOver() {
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(2), 0)
        WakeHandoff.beginCapture(ByteArray(0))
        WakeHandoff.append(ByteArray(960), 1000)
        WakeHandoff.append(ByteArray(960), 1060)
        assertEquals(1060, WakeHandoff.take(1).let { it!!.lastSampleAtMs })
        WakeHandoff.put(ByteArray(2), 0)
        assertEquals(0, WakeHandoff.take(1)!!.lastSampleAtMs)
    }

    @Test
    fun captureStopsAtTheLimit() {
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(2), 0)
        WakeHandoff.beginCapture(ByteArray(0))
        repeat(20) { WakeHandoff.append(ByteArray(WakeHandoff.MAX_CAPTURE_BYTES / 10)) }
        assertEquals(2 + WakeHandoff.MAX_CAPTURE_BYTES, WakeHandoff.take(1)!!.pcm.size)
    }

    @Test
    fun theTapKeepsOnlyTheRecentChunks() {
        val tap = WakeMicTap(keepBytes = 2000)
        repeat(10) { tap.onChunk(ByteArray(960)) }
        assertEquals(4800L, tap.sent)
        assertEquals(0, tap.tailAfter(4800).size)
        assertEquals(960, tap.tailAfter(4320).size)
        // older than kept: only what is still there
        assertTrue(tap.tailAfter(0).size <= 3 * 960)
    }

    @Test
    fun aMissingModelKeepsItsOwnStopReason() {
        assertEquals("modelMissing", WakePolicy.failureReason("modelMissing"))
        assertEquals("engine-failed", WakePolicy.failureReason("no-templates"))
        assertEquals("engine-failed", WakePolicy.failureReason(null))
    }

    @Test
    fun onlyTheKnownReasonSwitchesTheStage2GapNoticeOn() {
        assertTrue(WakePolicy.stage2GapActive("model_missing"))
        assertTrue(WakePolicy.stage2GapActive("no_sequences"))
        assertFalse(WakePolicy.stage2GapActive(null))
        assertFalse(WakePolicy.stage2GapActive("none"))
        assertFalse(WakePolicy.stage2GapActive("voiceexception"))
    }

    @Test
    fun serviceMicWaitsWhileTheAppRecordsAndForTheQuietTimeAfter() {
        AppVoice.reset()
        assertEquals(0L, AppVoice.waitMs(1_000))
        AppVoice.set("a", true, 1_000)
        assertEquals(AppVoice.WAIT_FOR_APP, AppVoice.waitMs(1_500))
        AppVoice.set("a", false, 2_000)
        assertEquals(AppVoice.QUIET_MS, AppVoice.waitMs(2_000))
        assertEquals(200L, AppVoice.waitMs(2_500))
        assertEquals(0L, AppVoice.waitMs(2_700))
        AppVoice.reset()
    }

    @Test
    fun theAppIsActiveUntilEveryEngineEnded() {
        AppVoice.reset()
        AppVoice.set("overlay", true, 100)
        AppVoice.set("main", true, 200)
        AppVoice.set("overlay", false, 300)
        assertTrue(AppVoice.active(300))
        AppVoice.set("main", false, 400)
        assertFalse(AppVoice.active(400))
        assertEquals(AppVoice.QUIET_MS - 100, AppVoice.waitMs(500))
        // An end of an engine that never started changes nothing.
        AppVoice.set("ghost", false, 10_000)
        assertEquals(0L, AppVoice.waitMs(10_000))
        AppVoice.reset()
    }

    @Test
    fun aHangingActiveReportStopsCountingAfterTheCap() {
        AppVoice.reset()
        AppVoice.set("main", true, 1_000)
        assertEquals(AppVoice.WAIT_FOR_APP, AppVoice.waitMs(1_000 + AppVoice.MAX_ACTIVE_MS - 1))
        // Never reported the end: the service listens again, after the quiet time.
        val capEnd = 1_000 + AppVoice.MAX_ACTIVE_MS
        assertFalse(AppVoice.active(capEnd))
        assertEquals(AppVoice.QUIET_MS, AppVoice.waitMs(capEnd))
        assertEquals(0L, AppVoice.waitMs(capEnd + AppVoice.QUIET_MS))
        // A new report renews the time of an engine.
        AppVoice.reset()
        AppVoice.set("main", true, 0)
        AppVoice.set("main", true, 100_000)
        assertTrue(AppVoice.active(100_000 + AppVoice.MAX_ACTIVE_MS - 1))
        AppVoice.reset()
    }

    @Test
    fun clearDropsWhatTheGuardStoppedCollecting() {
        WakeHandoff.clear()
        WakeHandoff.put(ByteArray(3200), 100)
        assertNotNull(WakeHandoff.takeKeepingOpen(200))
        WakeHandoff.append(ByteArray(3200), 250)
        WakeHandoff.stopCapture()
        // The overlay closed without `finish`: the rest does not linger.
        WakeHandoff.clear()
        assertNull(WakeHandoff.finish())
    }
}
