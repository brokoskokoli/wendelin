package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Evaluation of `voice_recognition_service` (B12): component comparison without Android. */
class RecognitionServiceStatusTest {
    private val pkg = "app.wendelin"
    private val cls = "app.wendelin.WendelinRecognitionService"

    private fun state(value: String?, serviceActive: Boolean = true) =
        RecognitionServiceStatus.evaluate(value, pkg, cls, serviceActive)

    /** Scheduler driven by the test: pending tasks run on [runAll]. */
    private class FakeScheduler : RecognitionServiceStatus.Scheduler {
        val pending = mutableListOf<Runnable>()

        override fun post(delayMs: Long, task: Runnable) {
            pending += task
        }

        override fun cancel(task: Runnable) {
            pending.remove(task)
        }

        fun runAll() = pending.toList().forEach { it.run() }
    }

    @Test
    fun ownServiceShortAndLongFormIsActive() {
        assertEquals("active", state("app.wendelin/.WendelinRecognitionService").state)
        assertEquals("active", state("app.wendelin/app.wendelin.WendelinRecognitionService").state)
        assertEquals("active", state(" app.wendelin/.WendelinRecognitionService\n").state)
    }

    @Test
    fun ownServiceSwitchedOffIsInactive() {
        // Role missing or „anbieten“ off: the component is disabled, other apps get errors.
        val off = state("app.wendelin/.WendelinRecognitionService", serviceActive = false)
        assertEquals("inactive", off.state)
        assertNull(off.otherPackage)
        assertEquals(
            mapOf("state" to "inactive"),
            RecognitionServiceStatus.toArgs(off, "x"),
        )
        // Another service stays „other“ whatever Wendelin's switch says.
        assertEquals("other", state("com.example/.Rec", serviceActive = false).state)
        assertEquals("unknown", state(null, serviceActive = false).state)
    }

    @Test
    fun parallelSelfTestsKeepTheirOwnTimeout() {
        val scheduler = FakeScheduler()
        val results = mutableListOf<Pair<String, String>>()
        val first = RecognitionServiceStatus.OnceWithTimeout(scheduler, 2000) {
            results += "first" to it.state
        }
        RecognitionServiceStatus.OnceWithTimeout(scheduler, 2000) {
            results += "second" to it.state
        }
        assertEquals(2, scheduler.pending.size)
        // The first answers: only its own timeout is cancelled.
        first.finish(RecognitionServiceStatus.Evaluation("active"))
        assertEquals(1, scheduler.pending.size)
        scheduler.runAll()
        assertEquals(listOf("first" to "active", "second" to "unknown"), results)
        // Answers once: a late result or timeout changes nothing.
        first.finish(RecognitionServiceStatus.Evaluation("other"))
        assertEquals(2, results.size)
    }

    @Test
    fun otherServiceNamesItsPackage() {
        val google = state(
            "com.google.android.tts/com.google.android.apps.speech.tts.googletts.service." +
                "GoogleTTSRecognitionService",
        )
        assertEquals("other", google.state)
        assertEquals("com.google.android.tts", google.otherPackage)
    }

    @Test
    fun otherClassOfOwnPackageIsNotActive() {
        val sameApp = state("app.wendelin/.WendelinVoiceInteractionService")
        assertEquals("other", sameApp.state)
        assertEquals("app.wendelin", sameApp.otherPackage)
        // Same class name in another package (e.g. a debug build with a suffix).
        assertEquals("other", state("app.wendelin.debug/app.wendelin.WendelinRecognitionService").state)
    }

    @Test
    fun emptyOrBrokenValueIsUnknown() {
        for (value in listOf(null, "", "   ", "app.wendelin", "/.Cls", "app.wendelin/", "a/b/c")) {
            val e = state(value)
            assertEquals("value: $value", "unknown", e.state)
            assertNull(e.otherPackage)
        }
    }

    @Test
    fun channelAnswerCarriesTheNameOnlyForOther() {
        assertEquals(
            mapOf("state" to "other", "appName" to "Speech Services by Google"),
            RecognitionServiceStatus.toArgs(
                RecognitionServiceStatus.Evaluation("other", "com.google.android.tts"),
                "Speech Services by Google",
            ),
        )
        assertEquals(
            mapOf("state" to "active"),
            RecognitionServiceStatus.toArgs(RecognitionServiceStatus.Evaluation("active"), "x"),
        )
        assertEquals(
            mapOf("state" to "unknown"),
            RecognitionServiceStatus.toArgs(RecognitionServiceStatus.Evaluation("unknown"), null),
        )
    }
}
