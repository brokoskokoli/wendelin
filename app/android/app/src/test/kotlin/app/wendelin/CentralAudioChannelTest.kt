package app.wendelin

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.ByteBuffer

/**
 * Unit tests for [CentralAudioChannel] multi-subscriber support (WP184).
 */
class CentralAudioChannelTest {

    private class FakeBinaryMessenger : BinaryMessenger {
        val sentCalls = mutableListOf<Pair<String, MethodCall>>()

        override fun send(channel: String, message: ByteBuffer?) {
            send(channel, message, null)
        }

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) {
            if (message != null) {
                val buffer = message.duplicate()
                buffer.position(0)
                buffer.order(java.nio.ByteOrder.nativeOrder())
                val call = StandardMethodCodec.INSTANCE.decodeMethodCall(buffer)
                sentCalls.add(channel to call)
            }
            val replyBuf = StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(null)
            replyBuf.rewind()
            callback?.reply(replyBuf)
        }

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) {}
    }

    private class SyncResult : MethodChannel.Result {
        var value: Any? = null
        var errorOccurred = false
        var notImplementedOccurred = false

        override fun success(result: Any?) {
            value = result
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            errorOccurred = true
        }

        override fun notImplemented() {
            notImplementedOccurred = true
        }
    }

    @Test
    fun supportsMultipleSubscribersWithTargetedStop() {
        val messenger = FakeBinaryMessenger()
        val hub = CentralAudioHub()
        val channel = CentralAudioChannel(
            context = null,
            channel = MethodChannel(messenger, CentralAudioChannel.CHANNEL),
            hubProvider = { hub },
            isServiceRunning = { true },
            ensureMicRunning = {},
            postToMain = { it.run() },
        )

        // Start subscriber 1
        val res1 = SyncResult()
        channel.onMethodCall(
            MethodCall("start", mapOf("subId" to "sub-1", "kind" to "session")),
            res1,
        )
        @Suppress("UNCHECKED_CAST")
        val map1 = res1.value as Map<String, Any?>
        assertEquals(true, map1["started"])
        assertEquals("sub-1", map1["subId"])
        assertEquals(1, hub.subscriberCount)

        // Start subscriber 2 (e.g. barge-in or follow-up)
        val res2 = SyncResult()
        channel.onMethodCall(
            MethodCall("start", mapOf("subId" to "sub-2", "kind" to "session")),
            res2,
        )
        @Suppress("UNCHECKED_CAST")
        val map2 = res2.value as Map<String, Any?>
        assertEquals(true, map2["started"])
        assertEquals("sub-2", map2["subId"])
        assertEquals(2, hub.subscriberCount)

        // Dispatch a chunk from the hardware mic to hub
        val pcm = ByteArray(32) { 42 }
        hub.dispatchChunk(pcm)

        // Both subscribers received their chunk marked with subId
        val audioCalls = messenger.sentCalls.filter { it.second.method == "audioChunk" }
        assertEquals(2, audioCalls.size)

        val args1 = audioCalls[0].second.arguments as Map<*, *>
        val args2 = audioCalls[1].second.arguments as Map<*, *>

        val seenSubIds = setOf(args1["subId"], args2["subId"])
        assertTrue(seenSubIds.contains("sub-1"))
        assertTrue(seenSubIds.contains("sub-2"))
        assertArrayEquals(pcm, args1["pcm"] as ByteArray)
        assertArrayEquals(pcm, args2["pcm"] as ByteArray)

        // Stop sub-1 selectively
        val stopRes1 = SyncResult()
        channel.onMethodCall(MethodCall("stop", mapOf("subId" to "sub-1")), stopRes1)
        assertEquals(1, hub.subscriberCount)

        // Dispatch another chunk
        val pcm2 = ByteArray(32) { 99 }
        messenger.sentCalls.clear()
        hub.dispatchChunk(pcm2)

        // Only sub-2 receives pcm2
        val remainingCalls = messenger.sentCalls.filter { it.second.method == "audioChunk" }
        assertEquals(1, remainingCalls.size)
        val remainingArgs = remainingCalls[0].second.arguments as Map<*, *>
        assertEquals("sub-2", remainingArgs["subId"])
        assertArrayEquals(pcm2, remainingArgs["pcm"] as ByteArray)

        // Dispose removes all remaining subscriptions
        channel.dispose()
        assertEquals(0, hub.subscriberCount)
    }

    @Test
    fun returnsServiceNotRunningWhenServiceIsOff() {
        val messenger = FakeBinaryMessenger()
        val hub = CentralAudioHub()
        val channel = CentralAudioChannel(
            context = null,
            channel = MethodChannel(messenger, CentralAudioChannel.CHANNEL),
            hubProvider = { hub },
            isServiceRunning = { false },
            ensureMicRunning = {},
            postToMain = { it.run() },
        )

        val res = SyncResult()
        channel.onMethodCall(
            MethodCall("start", mapOf("subId" to "sub-1", "kind" to "session")),
            res,
        )
        @Suppress("UNCHECKED_CAST")
        val map = res.value as Map<String, Any?>
        assertEquals(false, map["started"])
        assertEquals("serviceNotRunning", map["reason"])
    }
}
