package app.wendelin

import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream

/** A vault operation failed with a channel error code (`rejected`, `isFolder`, `exists`, ...). */
class VaultError(val code: String) : Exception(code)

/** One document of the vault tree (`id` is the provider's document id). */
data class VaultDoc(
    val id: String,
    val name: String,
    val mime: String,
    val modified: Long?,
    val size: Long?,
) {
    val isFolder get() = mime == VaultResolver.DIR_MIME
}

/** The storage behind a vault: documents addressed by id (Storage Access Framework in the app). */
interface VaultTree {
    /** Document id of the vault folder. */
    val rootId: String

    /** Children of the folder [parentId]; [FileNotFoundException] if it is gone. */
    fun children(parentId: String): List<VaultDoc>

    /** Creates a document or folder ([VaultResolver.DIR_MIME]) with exactly [name]. */
    fun create(parentId: String, mime: String, name: String): VaultDoc

    fun delete(id: String): Boolean

    fun openInput(id: String): InputStream?

    /** Output that truncates the document first. */
    fun openOutput(id: String): OutputStream?
}

/**
 * Vault-relative paths on a [VaultTree]: segment checks (never leaves the tree), lookup,
 * creating missing folders, reading and writing. No Android classes.
 */
class VaultResolver(private val tree: VaultTree) {
    private val root = VaultDoc(tree.rootId, "", DIR_MIME, null, null)

    /** The document at [path], `null` if a segment is missing or a file is used as a folder. */
    fun find(path: List<String>): VaultDoc? {
        var current = root
        for (segment in path) {
            if (!current.isFolder) return null
            current = tree.children(current.id).firstOrNull { it.name == segment } ?: return null
        }
        return current
    }

    fun list(path: List<String>): List<VaultDoc> {
        val folder = find(path) ?: throw FileNotFoundException()
        if (!folder.isFolder) throw FileNotFoundException()
        return tree.children(folder.id)
    }

    fun file(path: List<String>): VaultDoc {
        val doc = find(path) ?: throw FileNotFoundException()
        if (doc.isFolder || path.isEmpty()) throw VaultError("isFolder")
        return doc
    }

    fun read(path: List<String>): ByteArray {
        val doc = file(path)
        val input = tree.openInput(doc.id) ?: throw FileNotFoundException()
        return input.use { readLimited(it) }
    }

    /** Overwrites (or creates) the file; a folder at [path] is refused. */
    fun write(path: List<String>, bytes: ByteArray) {
        val existing = find(path)
        val doc = when {
            existing == null -> createFile(path)
            existing.isFolder -> throw VaultError("isFolder")
            else -> existing
        }
        // The whole content is written in one call; SAF has no atomic rename-over.
        writeBytes(doc, bytes)
    }

    /** Creates a new file; `exists` if there is one already. */
    fun create(path: List<String>, bytes: ByteArray) {
        if (find(path) != null) throw VaultError("exists")
        writeBytes(createFile(path), bytes)
    }

    fun delete(path: List<String>) {
        val doc = file(path)
        if (!tree.delete(doc.id)) throw VaultError("failed")
    }

    /** Creates missing parent folders and a new, empty file with exactly the last segment. */
    private fun createFile(path: List<String>): VaultDoc {
        if (path.isEmpty()) throw VaultError("isFolder")
        var parent = root
        for (segment in path.dropLast(1)) {
            val existing = tree.children(parent.id).firstOrNull { it.name == segment }
            parent = when {
                existing == null -> tree.create(parent.id, DIR_MIME, segment)
                existing.isFolder -> existing
                else -> throw VaultError("rejected")
            }
        }
        val name = path.last()
        return tree.create(parent.id, mimeFor(name), name)
    }

    private fun writeBytes(doc: VaultDoc, bytes: ByteArray) {
        tree.openOutput(doc.id)?.use {
            it.write(bytes)
            it.flush()
        } ?: throw FileNotFoundException()
    }

    companion object {
        /** `Document.MIME_TYPE_DIR` of the Storage Access Framework. */
        const val DIR_MIME = "vnd.android.document/directory"

        /** Larger files are not read (notes are text; the tools refuse > 2 MB anyway). */
        const val MAX_BYTES = 16 * 1024 * 1024

        /** Vault-relative path to segments; refuses anything that could leave the tree. */
        fun segments(path: String): List<String> {
            val parts = path.split('/').filter { it.isNotEmpty() }
            if (parts.any { it == "." || it == ".." || it.contains('\\') || it.contains('\u0000') }) {
                throw VaultError("rejected")
            }
            return parts
        }

        /** MIME type for a new file: Markdown by extension, else binary. */
        fun mimeFor(name: String): String =
            if (name.lowercase().endsWith(".md")) "text/markdown" else "application/octet-stream"

        /** Channel map of a listing entry (folders have no size). */
        fun entry(doc: VaultDoc): Map<String, Any?> = mapOf(
            "name" to doc.name,
            "folder" to doc.isFolder,
            "modified" to doc.modified,
            "size" to if (doc.isFolder) null else doc.size,
        )

        /** Reads [input] completely; `tooLarge` beyond [max] bytes. */
        fun readLimited(input: InputStream, max: Int = MAX_BYTES): ByteArray {
            val out = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                out.write(buffer, 0, n)
                if (out.size() > max) throw VaultError("tooLarge")
            }
            return out.toByteArray()
        }
    }
}
