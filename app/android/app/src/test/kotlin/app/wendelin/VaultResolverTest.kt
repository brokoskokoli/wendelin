package app.wendelin

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Vault paths on an in-memory tree: segment rules, lookup, folder creation, read and write. */
class VaultResolverTest {
    /** In-memory [VaultTree]; ids are generated, names are unique per folder. */
    private class FakeTree : VaultTree {
        override val rootId = "root"
        val docs = mutableMapOf<String, VaultDoc>()
        val parents = mutableMapOf<String, String>()
        val content = mutableMapOf<String, ByteArray>()
        var renameOnCreate = false
        private var next = 0

        override fun children(parentId: String): List<VaultDoc> =
            docs.values.filter { parents[it.id] == parentId }

        override fun create(parentId: String, mime: String, name: String): VaultDoc {
            val doc = VaultDoc("d${next++}", name, mime, null, 0)
            docs[doc.id] = doc
            parents[doc.id] = parentId
            content[doc.id] = ByteArray(0)
            return doc
        }

        override fun delete(id: String): Boolean = docs.remove(id) != null

        override fun openInput(id: String): InputStream? = content[id]?.let(::ByteArrayInputStream)

        override fun openOutput(id: String): OutputStream? {
            if (id !in docs) return null
            return object : ByteArrayOutputStream() {
                override fun close() {
                    content[id] = toByteArray()
                }
            }
        }

        fun file(parent: String, name: String, text: String): VaultDoc =
            create(parent, "text/markdown", name).also { content[it.id] = text.toByteArray() }
    }

    private val tree = FakeTree()
    private val vault = VaultResolver(tree)
    private fun p(path: String) = VaultResolver.segments(path)

    @Test
    fun segmentsSplitAndDropEmptyParts() {
        assertEquals(listOf("Projekte", "App.md"), p("Projekte//App.md/"))
        assertEquals(emptyList<String>(), p(""))
        assertEquals(emptyList<String>(), p("/"))
    }

    @Test
    fun segmentsRefuseEverythingThatLeavesTheTree() {
        for (bad in listOf("..", "a/../b", "./a", "a/./b", "a\\b", "a/b\u0000c")) {
            try {
                p(bad)
                fail("expected rejected: $bad")
            } catch (e: VaultError) {
                assertEquals(bad, "rejected", e.code)
            }
        }
        assertEquals(listOf("..a", "a..", "a.b"), p("..a/a../a.b"))
    }

    @Test
    fun findWalksSegmentsAndStopsAtFiles() {
        val dir = tree.create("root", VaultResolver.DIR_MIME, "Projekte")
        val note = tree.file(dir.id, "App.md", "hi")
        assertEquals(dir, vault.find(p("Projekte")))
        assertEquals(note, vault.find(p("Projekte/App.md")))
        assertNull(vault.find(p("Projekte/fehlt.md")))
        assertNull(vault.find(p("Projekte/App.md/unter")))
        assertEquals("", vault.find(emptyList())!!.name)
    }

    @Test
    fun writeCreatesMissingFoldersAndMarkdownMime() {
        vault.write(p("Neu/Tief/Notiz.md"), "text".toByteArray())
        val doc = vault.find(p("Neu/Tief/Notiz.md"))!!
        assertEquals("text/markdown", doc.mime)
        assertTrue(vault.find(p("Neu/Tief"))!!.isFolder)
        assertArrayEquals("text".toByteArray(), vault.read(p("Neu/Tief/Notiz.md")))
        assertEquals("application/octet-stream", VaultResolver.mimeFor("bild.png"))
        assertEquals("text/markdown", VaultResolver.mimeFor("A.MD"))
    }

    @Test
    fun writeTruncatesAnExistingFile() {
        tree.file("root", "A.md", "langer alter Inhalt")
        vault.write(p("A.md"), "neu".toByteArray())
        assertEquals("neu", String(vault.read(p("A.md"))))
    }

    @Test
    fun writeOnAFolderOrAFilePathFails() {
        tree.create("root", VaultResolver.DIR_MIME, "Ordner")
        tree.file("root", "Datei.md", "x")
        assertCode("isFolder") { vault.write(p("Ordner"), ByteArray(0)) }
        assertCode("rejected") { vault.write(p("Datei.md/unter.md"), ByteArray(0)) }
        assertCode("isFolder") { vault.write(emptyList(), ByteArray(0)) }
    }

    @Test
    fun createRefusesAnExistingPath() {
        tree.file("root", "A.md", "x")
        assertCode("exists") { vault.create(p("A.md"), ByteArray(0)) }
        vault.create(p("B.md"), "b".toByteArray())
        assertEquals("b", String(vault.read(p("B.md"))))
    }

    @Test
    fun readMissingAndFolders() {
        tree.create("root", VaultResolver.DIR_MIME, "Ordner")
        try {
            vault.read(p("fehlt.md"))
            fail("expected FileNotFoundException")
        } catch (_: FileNotFoundException) {
        }
        assertCode("isFolder") { vault.read(p("Ordner")) }
        assertCode("isFolder") { vault.read(emptyList()) }
    }

    @Test
    fun listReturnsChildrenAndRefusesFiles() {
        val dir = tree.create("root", VaultResolver.DIR_MIME, "Ordner")
        tree.file(dir.id, "a.md", "")
        tree.file(dir.id, "b.md", "")
        assertEquals(listOf("a.md", "b.md"), vault.list(p("Ordner")).map { it.name }.sorted())
        assertEquals(setOf("Ordner"), vault.list(emptyList()).map { it.name }.toSet())
        try {
            vault.list(p("Ordner/a.md"))
            fail("a file has no children")
        } catch (_: FileNotFoundException) {
        }
    }

    @Test
    fun deleteRemovesFilesOnly() {
        tree.file("root", "A.md", "x")
        tree.create("root", VaultResolver.DIR_MIME, "Ordner")
        vault.delete(p("A.md"))
        assertNull(vault.find(p("A.md")))
        assertCode("isFolder") { vault.delete(p("Ordner")) }
        try {
            vault.delete(p("A.md"))
            fail("already gone")
        } catch (_: FileNotFoundException) {
        }
    }

    @Test
    fun readRefusesTooLargeFiles() {
        assertEquals(3, VaultResolver.readLimited(ByteArrayInputStream(ByteArray(3)), max = 3).size)
        assertCode("tooLarge") { VaultResolver.readLimited(ByteArrayInputStream(ByteArray(4)), max = 3) }
    }

    @Test
    fun entryMapHidesFolderSize() {
        val file = VaultDoc("1", "A.md", "text/markdown", 5, 12)
        val dir = VaultDoc("2", "Ordner", VaultResolver.DIR_MIME, 6, 99)
        assertEquals(mapOf("name" to "A.md", "folder" to false, "modified" to 5L, "size" to 12L), VaultResolver.entry(file))
        assertEquals(mapOf("name" to "Ordner", "folder" to true, "modified" to 6L, "size" to null), VaultResolver.entry(dir))
        assertFalse(file.isFolder)
    }

    private fun assertCode(code: String, block: () -> Unit) {
        try {
            block()
            fail("expected VaultError $code")
        } catch (e: VaultError) {
            assertEquals(code, e.code)
        }
    }
}
