package app.wendelin

import android.content.ContentResolver
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream

/** [VaultTree] on a Storage Access Framework tree URI with a persisted grant. */
class SafVaultTree(private val resolver: ContentResolver, private val tree: Uri) : VaultTree {
    override val rootId: String = DocumentsContract.getTreeDocumentId(tree)

    private fun uri(id: String) = DocumentsContract.buildDocumentUriUsingTree(tree, id)

    /** Display name of the vault folder. */
    fun rootName(): String? = resolver.query(
        uri(rootId),
        arrayOf(Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { if (it.moveToFirst()) it.getString(0) else null }

    override fun children(parentId: String): List<VaultDoc> = resolver.query(
        DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId),
        COLUMNS,
        null,
        null,
        null,
    )?.use { c ->
        val out = ArrayList<VaultDoc>(c.count)
        while (c.moveToNext()) {
            out.add(
                VaultDoc(
                    id = c.getString(0),
                    name = c.getString(1) ?: continue,
                    mime = c.getString(2) ?: "",
                    modified = if (c.isNull(3)) null else c.getLong(3),
                    size = if (c.isNull(4)) null else c.getLong(4),
                ),
            )
        }
        out
    } ?: throw FileNotFoundException()

    /** The new document; if the provider renamed it (name taken meanwhile), it is removed again. */
    override fun create(parentId: String, mime: String, name: String): VaultDoc {
        val docUri = DocumentsContract.createDocument(resolver, uri(parentId), mime, name)
            ?: throw VaultError("failed")
        val id = DocumentsContract.getDocumentId(docUri)
        val doc = resolver.query(uri(id), COLUMNS, null, null, null)?.use { c ->
            if (!c.moveToFirst()) null else VaultDoc(c.getString(0), c.getString(1) ?: "", c.getString(2) ?: "", null, null)
        } ?: throw VaultError("failed")
        if (doc.name != name) {
            DocumentsContract.deleteDocument(resolver, uri(id))
            throw VaultError("exists")
        }
        return doc
    }

    override fun delete(id: String): Boolean = DocumentsContract.deleteDocument(resolver, uri(id))

    override fun openInput(id: String): InputStream? = resolver.openInputStream(uri(id))

    // "wt": truncate, so a shorter content leaves no rest of the old one.
    override fun openOutput(id: String): OutputStream? = resolver.openOutputStream(uri(id), "wt")

    private companion object {
        val COLUMNS = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_SIZE,
        )
    }
}
