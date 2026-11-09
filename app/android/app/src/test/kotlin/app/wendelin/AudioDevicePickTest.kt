package app.wendelin

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Stable device keys, the choice "selected else system" and the persisted selection (WP188). */
class AudioDevicePickTest {
    private fun mic(addr: String = "", product: String = "Pixel", type: Int = 15) =
        AudioDeviceDesc(type, product, addr, isSource = true, isSink = false)

    private fun sink(type: Int, product: String, addr: String = "") =
        AudioDeviceDesc(type, product, addr, isSource = false, isSink = true)

    private val btMic = AudioDeviceDesc(7, "Buds", "AA:BB:CC:DD:EE:FF", isSource = true, isSink = true)

    private class MapKv : KeyValues {
        val map = HashMap<String, String>()
        override fun getString(key: String) = map[key]
        override fun putString(key: String, value: String?) {
            if (value == null) map.remove(key) else map[key] = value
        }
    }

    @Test
    fun keyIsSameForSameDevice() {
        assertEquals(AudioDevicePick.keyOf(btMic), AudioDevicePick.keyOf(btMic.copy()))
    }

    @Test
    fun keyDiffersByTypeProductAndAddress() {
        val k = AudioDevicePick.keyOf(btMic)
        assertNotEquals(k, AudioDevicePick.keyOf(btMic.copy(type = 26)))
        assertNotEquals(k, AudioDevicePick.keyOf(btMic.copy(product = "Other")))
        assertNotEquals(k, AudioDevicePick.keyOf(btMic.copy(address = "11:22:33:44:55:66")))
    }

    private fun bt(addr: String, type: Int = 8, product: String = "Buds") =
        AudioDeviceDesc(type, product, addr, isSource = false, isSink = true)

    @Test
    fun bluetoothKeySameForAnonymisedAndRealAddress() {
        assertEquals(
            AudioDevicePick.keyOf(bt("XX:XX:XX:XX:A1:B2")),
            AudioDevicePick.keyOf(bt("00:11:22:33:a1:b2")),
        )
    }

    @Test
    fun bluetoothKeyDiffersByAddressEnding() {
        assertNotEquals(
            AudioDevicePick.keyOf(bt("XX:XX:XX:XX:A1:B2")),
            AudioDevicePick.keyOf(bt("XX:XX:XX:XX:A1:B3")),
        )
    }

    @Test
    fun usbKeyIgnoresCardAndDevice() {
        val a = AudioDeviceDesc(11, "Mic", "card=1;device=0", isSource = true, isSink = false)
        assertEquals(AudioDevicePick.keyOf(a), AudioDevicePick.keyOf(a.copy(address = "card=3;device=2")))
        assertFalse(AudioDevicePick.keyOf(a).contains("card"))
    }

    @Test
    fun a2dpHidesScoSinkOfSameDevice() {
        val all = listOf(bt("XX:XX:XX:XX:A1:B2", 7), bt("00:11:22:33:A1:B2", 8))
        assertEquals(listOf("bluetooth_a2dp"), AudioDevicePick.entries(all, "output").map { it.type })
    }

    @Test
    fun scoSinkWithoutAddressMatchesByProduct() {
        val all = listOf(bt("", 7), bt("", 26))
        assertEquals(listOf("bluetooth_le"), AudioDevicePick.entries(all, "output").map { it.type })
    }

    @Test
    fun pureScoSinkStays() {
        val all = listOf(bt("XX:XX:XX:XX:A1:B2", 7), bt("XX:XX:XX:XX:C3:D4", 8, "Other"))
        assertEquals(listOf("bluetooth_sco", "bluetooth_a2dp"), AudioDevicePick.entries(all, "output").map { it.type })
    }

    @Test
    fun scoInputStaysDespiteA2dp() {
        val sco = AudioDeviceDesc(7, "Buds", "AA:BB:CC:DD:A1:B2", isSource = true, isSink = true)
        val all = listOf(sco, bt("AA:BB:CC:DD:A1:B2", 8))
        assertEquals(listOf("bluetooth_sco"), AudioDevicePick.entries(all, "input").map { it.type })
    }

    @Test
    fun keyHasNoAddress() {
        val k = AudioDevicePick.keyOf(btMic)
        assertFalse(k.contains("AA:BB"))
        assertFalse(k.contains("aabb", ignoreCase = true))
    }

    @Test
    fun separatorInProductNameKeepsKeyParseable() {
        assertEquals(3, AudioDevicePick.keyOf(mic(product = "A|B")).split("|").size)
    }

    @Test
    fun entriesFilterByDirectionAndKnownTypes() {
        val all = listOf(mic(), btMic, sink(2, "Speaker"), sink(9, "HDMI"), mic(type = 18, product = "Tel"))
        assertEquals(listOf("builtin_mic", "bluetooth_sco"), AudioDevicePick.entries(all, "input").map { it.type })
        assertEquals(listOf("bluetooth_sco", "builtin_speaker"), AudioDevicePick.entries(all, "output").map { it.type })
    }

    @Test
    fun entriesNeverCarryTheAddress() {
        val e = AudioDevicePick.entries(listOf(btMic), "input").single()
        assertEquals("Buds", e.name)
        assertFalse(e.toString().contains("AA:BB"))
    }

    @Test
    fun duplicateKeyListedOnce() {
        assertEquals(1, AudioDevicePick.entries(listOf(mic(), mic()), "input").size)
    }

    @Test
    fun unknownDirectionHasNoEntries() {
        assertTrue(AudioDevicePick.entries(listOf(mic()), "both").isEmpty())
    }

    @Test
    fun noSelectionIsSystem() {
        assertNull(AudioDevicePick.resolve(null, AudioDevicePick.entries(listOf(mic()), "input")))
    }

    @Test
    fun missingDeviceFallsBackToSystemAndComesBack() {
        val key = AudioDevicePick.keyOf(btMic)
        assertNull(AudioDevicePick.resolve(key, AudioDevicePick.entries(listOf(mic()), "input")))
        val back = AudioDevicePick.entries(listOf(mic(), btMic), "input")
        assertEquals(key, AudioDevicePick.resolve(key, back)?.key)
    }

    private val e1 = AudioDeviceEntry("k1", "usb", "Mic")
    private val e2 = AudioDeviceEntry("k2", "bluetooth_a2dp", "Box")

    @Test
    fun selectionSurvivesRestart() {
        val kv = MapKv()
        AudioDeviceSelectionStore(kv).set("input", e1)
        AudioDeviceSelectionStore(kv).set("output", e2)
        val again = AudioDeviceSelectionStore(kv)
        assertEquals(e1, again.get("input"))
        assertEquals(e2, again.get("output"))
    }

    @Test
    fun nullOrEmptyKeyResetsToSystem() {
        val kv = MapKv()
        val s = AudioDeviceSelectionStore(kv)
        s.set("input", e1)
        s.set("input", null)
        assertNull(s.get("input"))
        assertTrue(kv.map.isEmpty())
        s.set("output", e2)
        s.set("output", AudioDeviceEntry("", "", ""))
        assertNull(s.get("output"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun unknownDirectionIsRejected() {
        AudioDeviceSelectionStore(MapKv()).set("speaker", e1)
    }

    @Test
    fun unreadableStoreIsSystem() {
        val broken = object : KeyValues {
            override fun getString(key: String): String? = throw IllegalStateException("x")
            override fun putString(key: String, value: String?) {}
        }
        assertNull(AudioDeviceSelectionStore(broken).get("input"))
    }
}
