package app.wendelin

/**
 * One engine group per process (WP145, ADR 0021): the first engine runs on its own, every further
 * one is spawned from a living sibling and shares its resources (Dart VM, isolate group, shaders).
 * Generic and Android-free so a JVM test can drive the lifecycle ([EngineGroups] binds it to
 * Flutter). Main thread only.
 *
 * @param newGroup creates the group (called once, on the first [obtain]).
 * @param onWillDestroy registers a callback that fires when the engine is destroyed.
 */
class EnginePool<G, E>(
    private val newGroup: () -> G,
    private val onWillDestroy: (E, () -> Unit) -> Unit,
) {
    private var group: G? = null

    /** How often the group was created: 1 after the first [obtain], never more. */
    var groupsCreated = 0
        private set

    /** Engines created by this pool that are not destroyed yet. */
    var live = 0
        private set

    /** An engine of the pool; [siblings] counts the engines that lived when it was created. */
    class Lease<E>(val engine: E, val siblings: Int, val groupIsNew: Boolean) {
        /** Spawned from a sibling (shared resources) instead of started alone. */
        val fromSibling: Boolean get() = siblings > 0
    }

    /** A new engine in the group; [spawn] creates and starts it there. */
    fun obtain(spawn: (G) -> E): Lease<E> {
        val existing = group
        val g = existing ?: newGroup().also {
            group = it
            groupsCreated++
        }
        val siblings = live
        val engine = spawn(g)
        live++
        var gone = false
        onWillDestroy(engine) {
            if (!gone) {
                gone = true
                live--
            }
        }
        return Lease(engine, siblings, existing == null)
    }
}
