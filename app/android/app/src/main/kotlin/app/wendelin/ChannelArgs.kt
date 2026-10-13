package app.wendelin

/** A required channel argument is missing or has the wrong type (reported as `failed`). */
class ArgumentException(val key: String) : IllegalArgumentException("argument $key")

/**
 * Typed access to the argument map of a `MethodCall` without Android types, so the checks can be
 * tested on the JVM. Keys and types are those of `app/channels.json`.
 */
class ChannelArgs(private val map: Map<*, *>?) {
    /** The string at [key], `null` if absent (or not a string). */
    fun string(key: String): String? = map?.get(key) as? String

    /** The string at [key]; [ArgumentException] if absent. */
    fun requireString(key: String): String = string(key) ?: throw ArgumentException(key)

    /** The number at [key] as a long; [ArgumentException] if absent. */
    fun requireLong(key: String): Long =
        (map?.get(key) as? Number)?.toLong() ?: throw ArgumentException(key)

    /** `true` only for an explicit `true`. */
    fun isTrue(key: String): Boolean = map?.get(key) == true

    /** The byte array at [key]; [ArgumentException] if absent. */
    fun requireBytes(key: String): ByteArray =
        map?.get(key) as? ByteArray ?: throw ArgumentException(key)

    /** The string list at [key], `null` if absent. */
    fun stringList(key: String): List<String>? =
        (map?.get(key) as? List<*>)?.map { it as String }

    companion object {
        /** Arguments of a call: `call.arguments` as a map (anything else is empty). */
        fun of(arguments: Any?): ChannelArgs = ChannelArgs(arguments as? Map<*, *>)
    }
}
