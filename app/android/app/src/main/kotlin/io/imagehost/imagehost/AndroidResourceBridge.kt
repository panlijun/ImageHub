package io.imagehost.imagehost

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.OperationCanceledException
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.AtomicFile
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.InputStream
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit

/** Only the private registry sees URIs; Flutter receives opaque one-use handles. */
class AndroidResourceBridge(private val activity: Activity) : AndroidResourceHost {
    private val resolver = activity.applicationContext.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private val workers = (Executors.newFixedThreadPool(4) as ThreadPoolExecutor).apply {
        setKeepAliveTime(30, TimeUnit.SECONDS)
        allowCoreThreadTimeOut(true)
    }
    // Activity recreation may overlap a provider's actual read/close on the old bridge.
    // A process-wide owner prevents the new bridge treating that live IO as crash residue.
    private val gate = PROCESS_GATE
    private val registry = AtomicFile(File(activity.noBackupFilesDir, "imagehost_resources_v1"))
    private val entries = LinkedHashMap<String, Entry>()
    private val nodes = LinkedHashMap<String, Node>()
    private val ownedGrants = LinkedHashSet<String>()
    private val control = Lane()
    private var loaded = false
    private var registryFailed = false
    @Volatile private var disposed = false
    // Picker lifetime includes the provider result and registry commit, not only its window.
    @Volatile private var picker: Picker? = null

    private data class Picker(
        val type: String,
        val callback: (Result<AndroidSelection>) -> Unit,
        var receiving: Boolean = false,
    )
    private data class Entry(
        val id: String,
        val uri: String,
        val name: String,
        val type: String,
        val code: AndroidIoCode,
        val recoverable: Boolean,
        var consumed: Boolean = false,
    )
    private inner class Node(val entry: Entry) {
        val lane = Lane()
        @Volatile var closing = false
        var stream: InputStream? = null
        var opened = false
        var closeUncertain = false
        var terminal = false
        var recoveryCleanupOnly = false
    }

    /** FIFO per resource, backed by one bounded shared pool (no blocking main-thread IO). */
    private inner class Lane {
        private val queue = ArrayDeque<() -> Unit>()
        private var running = false
        fun submit(work: () -> Unit) {
            synchronized(queue) {
                queue.addLast(work)
                if (!running) {
                    running = true
                    workers.execute { runNext() }
                }
            }
        }
        private fun runNext() {
            val work = synchronized(queue) { queue.removeFirst() }
            try { work() } finally {
                synchronized(queue) {
                    if (queue.isEmpty()) running = false
                    else workers.execute { runNext() }
                }
            }
        }
    }

    override fun pickResources(
        photos: Boolean,
        backup: Boolean,
        callback: (Result<AndroidSelection>) -> Unit,
    ) = onMain(callback) {
        if (disposed) throw fixed(AndroidIoCode.CANCELLED)
        if (photos && backup) throw fixed(AndroidIoCode.INVALID_INPUT)
        if (picker != null) throw fixed(AndroidIoCode.UNAVAILABLE)
        val type = if (backup) "backup" else if (photos) "photo" else "file"
        val pending = Picker(type, callback)
        picker = pending // Reserve before background registry IO; concurrent calls cannot steal it.
        control.submit {
            try {
                if (disposed) throw fixed(AndroidIoCode.CANCELLED)
                synchronized(gate) { loadLocked() }
                main.post {
                    try {
                        if (disposed) throw fixed(AndroidIoCode.CANCELLED)
                        if (picker !== pending) throw fixed(AndroidIoCode.UNAVAILABLE)
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            this.type = when (type) {
                                "photo" -> "image/*"
                                "backup" -> "application/zip"
                                else -> "*/*"
                            }
                            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, type != "backup")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                        }
                        activity.startActivityForResult(intent, REQUEST_CODE)
                    } catch (error: Throwable) {
                        completePicker(pending, Result.failure(safe(error)))
                    }
                }
            } catch (error: Throwable) {
                completePicker(pending, Result.failure(safe(error)))
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        try {
            val pending = picker ?: return true
            if (pending.receiving) return true
            pending.receiving = true
            if (resultCode == Activity.RESULT_CANCELED || disposed) {
                completePicker(pending, Result.success(AndroidSelection(true, emptyList())))
                return true
            }
            if (resultCode != Activity.RESULT_OK || data == null) {
                completePicker(pending, Result.failure(fixed(AndroidIoCode.UNAVAILABLE)))
                return true
            }
            val uris = ArrayList<Uri>()
            val clip = data.clipData
            if (clip != null) {
                if (clip.itemCount > MAX_ENTRIES) throw fixed(AndroidIoCode.INVALID_INPUT)
                for (index in 0 until clip.itemCount) uris.add(clip.getItemAt(index).uri)
            } else data.data?.let { uris.add(it) }
            if (uris.isEmpty() || (pending.type == "backup" && uris.size != 1)) {
                throw fixed(AndroidIoCode.INVALID_INPUT)
            }
            val flags = data.flags
            control.submit {
                try {
                    val selected = ArrayList<AndroidPickedResource>()
                    synchronized(gate) {
                        loadLocked()
                        if (entries.size + uris.size > MAX_ENTRIES) {
                            throw fixed(AndroidIoCode.UNAVAILABLE)
                        }
                    }
                    for (uri in uris) {
                        // Metadata and grant failures belong to this item, never erase its neighbours.
                        val entry = inspect(uri, pending.type, flags)
                        selected.add(publicEntry(entry))
                    }
                    synchronized(gate) { saveLocked() }
                    completePicker(pending, Result.success(AndroidSelection(false, selected)))
                } catch (error: Throwable) {
                    // Keep any grant/identity evidence; never guess cleanup after a failed commit.
                    completePicker(pending, Result.failure(safe(error)))
                }
            }
        } catch (error: Throwable) {
            val pending = picker
            if (pending != null) completePicker(pending, Result.failure(safe(error)))
        }
        return true
    }

    override fun recoverSelection(callback: (Result<AndroidSelection>) -> Unit) = onMain(callback) {
        if (disposed) throw fixed(AndroidIoCode.CANCELLED)
        if (picker != null) throw fixed(AndroidIoCode.UNAVAILABLE)
        control.submit {
            try {
                if (disposed) throw fixed(AndroidIoCode.CANCELLED)
                // Streams cannot survive process death. Retired registrations are only closed,
                // never reopened; backups are not returned through image/file recovery.
                val retired = synchronized(gate) {
                    loadLocked()
                    entries.values.filter { (it.consumed || it.type == "backup") &&
                        (nodes[it.id] == null || nodes[it.id]!!.recoveryCleanupOnly) }
                        .map { entry -> nodes[entry.id] ?: Node(entry).also {
                            nodes[entry.id] = it
                            it.closing = true
                            it.recoveryCleanupOnly = true
                        } }
                }
                for (node in retired) {
                    node.terminal = true
                    try { finishClose(node) } catch (error: Throwable) {
                        // Retain a failed-close node: a disposed owner must not be released
                        // while its stream/grant/registry cleanup remains unconfirmed.
                        throw error
                    }
                }
                val recovered = synchronized(gate) {
                    loadLocked()
                    if (disposed) throw fixed(AndroidIoCode.CANCELLED)
                    entries.values.filter { !it.consumed && it.type != "backup" }.map { entry ->
                        if (!nodes.containsKey(entry.id)) nodes[entry.id] = Node(entry)
                        publicEntry(entry)
                    }
                }
                reply(callback, Result.success(AndroidSelection(false, recovered)))
            } catch (error: Throwable) { reply(callback, Result.failure(safe(error))) }
        }
    }

    override fun readResource(handle: String, callback: (Result<AndroidReadReply>) -> Unit) =
        onMain(callback) {
            if (disposed) throw fixed(AndroidIoCode.CANCELLED)
            control.submit {
                try {
                    if (disposed) throw fixed(AndroidIoCode.CANCELLED)
                    val node = synchronized(gate) {
                        checkRegistryLocked()
                        if (!validId(handle)) throw fixed(AndroidIoCode.INVALID_INPUT)
                        nodes[handle] ?: throw fixed(AndroidIoCode.INVALID_INPUT)
                    }
                    if (node.closing) throw fixed(AndroidIoCode.CANCELLED)
                    node.lane.submit {
                        val result = try { readChunk(node) } catch (error: Throwable) {
                            node.terminal = true
                            AndroidReadReply(classify(error), ByteArray(0), false)
                        }
                        reply(callback, Result.success(result))
                    }
                } catch (error: Throwable) { reply(callback, Result.failure(safe(error))) }
            }
        }

    private fun readChunk(node: Node): AndroidReadReply {
        if (disposed || node.closing) return AndroidReadReply(AndroidIoCode.CANCELLED, ByteArray(0), false)
        synchronized(gate) {
            checkRegistryLocked()
            if (entries[node.entry.id] !== node.entry || nodes[node.entry.id] !== node) {
                throw fixed(AndroidIoCode.INVALID_INPUT)
            }
        }
        if (node.terminal) throw fixed(AndroidIoCode.INVALID_INPUT)
        if (node.entry.code != AndroidIoCode.OK) {
            node.terminal = true
            return AndroidReadReply(node.entry.code, ByteArray(0), false)
        }
        if (!node.opened) {
            if (node.entry.consumed) throw fixed(AndroidIoCode.INVALID_INPUT)
            if (isPartial(Uri.parse(node.entry.uri))) {
                node.terminal = true
                return AndroidReadReply(AndroidIoCode.CLOUD_PENDING, ByteArray(0), false)
            }
            synchronized(gate) {
                node.entry.consumed = true
                saveLocked() // Durable before opening: crash recovery must never reopen this source.
            }
            node.opened = true
            if (disposed || node.closing) {
                node.terminal = true
                return AndroidReadReply(AndroidIoCode.CANCELLED, ByteArray(0), false)
            }
            node.stream = resolver.openInputStream(Uri.parse(node.entry.uri))
                ?: throw fixed(AndroidIoCode.UNAVAILABLE)
        }
        val bytes = ByteArray(CHUNK_BYTES)
        val count = node.stream!!.read(bytes)
        if (count < 0) {
            node.terminal = true
            closeStream(node)
            return AndroidReadReply(AndroidIoCode.OK, ByteArray(0), true)
        }
        if (count == 0) throw fixed(AndroidIoCode.UNAVAILABLE)
        return AndroidReadReply(AndroidIoCode.OK, if (count == bytes.size) bytes else bytes.copyOf(count), false)
    }

    override fun closeResource(handle: String, callback: (Result<Unit>) -> Unit) = onMain(callback) {
        control.submit {
            try {
                val node = synchronized(gate) {
                    checkRegistryLocked()
                    if (!validId(handle)) throw fixed(AndroidIoCode.INVALID_INPUT)
                    nodes[handle] ?: throw fixed(AndroidIoCode.INVALID_INPUT)
                }
                node.closing = true
                node.lane.submit {
                    try {
                        finishClose(node)
                        reply(callback, Result.success(Unit))
                    } catch (error: Throwable) { reply(callback, Result.failure(safe(error))) }
                }
            } catch (error: Throwable) { reply(callback, Result.failure(safe(error))) }
        }
    }

    private fun closeStream(node: Node) {
        if (node.closeUncertain) throw fixed(AndroidIoCode.CLEANUP_PENDING)
        val stream = node.stream ?: return
        try { stream.close() } catch (_: Throwable) {
            // Providers may set an internal closed flag before throwing. A
            // subsequent no-op close cannot retire the source protection.
            node.closeUncertain = true
            throw fixed(AndroidIoCode.CLEANUP_PENDING)
        }
        node.stream = null // A thrown close never claims that the stream has been closed.
    }

    private fun finishClose(node: Node) {
        closeStream(node) // Lane ordering waits for an already-started actual read.
        node.terminal = true
        synchronized(gate) {
            checkRegistryLocked()
            if (nodes[node.entry.id] !== node) return
            val uri = node.entry.uri
            val lastReference = entries.values.none { it.id != node.entry.id && it.uri == uri }
            if (uri in ownedGrants && lastReference) {
                try {
                    if (resolver.persistedUriPermissions.any { it.uri.toString() == uri && it.isReadPermission }) {
                        resolver.releasePersistableUriPermission(Uri.parse(uri), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    if (resolver.persistedUriPermissions.any { it.uri.toString() == uri && it.isReadPermission }) {
                        throw fixed(AndroidIoCode.CLEANUP_PENDING)
                    }
                } catch (_: Throwable) { throw fixed(AndroidIoCode.CLEANUP_PENDING) }
                ownedGrants.remove(uri)
            }
            // A failed atomic commit keeps this node/registration available for a close retry.
            entries.remove(node.entry.id)
            try { saveLocked() } catch (error: Throwable) {
                entries[node.entry.id] = node.entry
                throw error
            }
            nodes.remove(node.entry.id)
            releaseOwnerIfDrainedLocked()
        }
    }

    /** Requests stop; queued closes run after real IO. It never interrupts a provider read. */
    fun dispose() {
        try {
            disposed = true
            disposeNodes()
            // A pending picker is retained until onActivityResult; its callback is not completed early.
        } catch (_: Throwable) { /* Evidence remains private; no raw system exception crosses Pigeon. */ }
    }

    private fun disposeNodes() {
        control.submit {
            val active = synchronized(gate) { nodes.values.toList() }
            for (node in active) {
                node.closing = true
                node.lane.submit {
                    try { finishClose(node) } catch (_: Throwable) { /* Retain failed-close evidence. */ }
                }
            }
            synchronized(gate) { releaseOwnerIfDrainedLocked() }
        }
    }

    private fun completePicker(pending: Picker, result: Result<AndroidSelection>) {
        main.post {
            try {
                // Stop/dispose can race metadata IO after RESULT_OK. Deliver only cancellation
                // to the old action, and retain the owner until its callback actually returns.
                pending.callback(if (disposed) Result.success(AndroidSelection(true, emptyList())) else result)
            } catch (_: Throwable) {
                // The system/provider exception and the callback object never become diagnostics.
            } finally {
                if (picker === pending) picker = null
                if (disposed) disposeNodes()
            }
        }
    }

    private fun releaseOwnerIfDrainedLocked() {
        if (registryOwner === this && disposed && nodes.isEmpty() && picker == null) {
            registryOwner = null
        }
    }

    private fun claimOwnerLocked() {
        val previous = registryOwner
        if (previous != null && previous !== this) {
            // No timeout/cancellation substitutes for actual stream and selection cleanup.
            if (!previous.disposed || previous.nodes.isNotEmpty() || previous.picker != null) {
                throw fixed(AndroidIoCode.UNAVAILABLE)
            }
        }
        registryOwner = this
    }

    private fun inspect(uri: Uri, type: String, flags: Int): Entry {
        var code = AndroidIoCode.OK
        var name = when (type) { "photo" -> "所选图片"; "backup" -> "所选备份"; else -> "所选文件" }
        var recoverable = false
        if (uri.scheme != "content" || uri.authority.isNullOrBlank() || uri.toString().length > MAX_URI) code = AndroidIoCode.INVALID_INPUT
        else {
            try {
                resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null).use { cursor ->
                    if (cursor == null || !cursor.moveToFirst()) throw fixed(AndroidIoCode.UNAVAILABLE)
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column < 0 || cursor.isNull(column)) throw fixed(AndroidIoCode.UNAVAILABLE)
                    name = safeName(cursor.getString(column), name)
                }
                if (isPartial(uri)) code = AndroidIoCode.CLOUD_PENDING
            } catch (error: Throwable) { code = classify(error) }
        }
        // Grant evidence and its resource registration share the gate, preventing a last-close
        // operation on another handle for this URI from racing a newly confirmed selection.
        return synchronized(gate) {
            // Read grants that predate this bridge are never adopted as owned or released.
            try {
                val existing = code != AndroidIoCode.INVALID_INPUT &&
                    resolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
                recoverable = existing
                if (code != AndroidIoCode.INVALID_INPUT && !existing && flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0 &&
                    flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0) {
                    resolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    recoverable = resolver.persistedUriPermissions.any { it.uri == uri && it.isReadPermission }
                    if (recoverable) ownedGrants.add(uri.toString())
                }
            } catch (_: Throwable) {
                // A provider may refuse persistence while granting a valid current-session read.
                // Do not claim that a transient grant will survive a process/device restart.
            }
            val id = UUID.randomUUID().toString()
            val recordedUri = if (code == AndroidIoCode.INVALID_INPUT) "content://io.imagehost.invalid/$id" else uri.toString()
            Entry(id, recordedUri, name, type, code, recoverable).also { entry ->
                entries[id] = entry
                nodes[id] = Node(entry)
            }
        }
    }

    private fun isPartial(uri: Uri): Boolean {
        if (!DocumentsContract.isDocumentUri(activity, uri)) return false
        resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_FLAGS), null, null, null).use { cursor ->
            if (cursor == null || !cursor.moveToFirst()) throw fixed(AndroidIoCode.UNAVAILABLE)
            val column = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_FLAGS)
            return column >= 0 && !cursor.isNull(column) &&
                cursor.getLong(column) and DocumentsContract.Document.FLAG_PARTIAL.toLong() != 0L
        }
    }

    private fun publicEntry(entry: Entry) = AndroidPickedResource(entry.id, entry.name, entry.type)

    private fun loadLocked() {
        claimOwnerLocked()
        if (registryFailed) throw fixed(AndroidIoCode.STORAGE)
        if (loaded) return
        try {
            val bytes = try {
                registry.openRead().use { stream ->
                    val out = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = stream.read(buffer)
                        if (count < 0) break
                        if (out.size() + count > MAX_REGISTRY_BYTES) throw fixed(AndroidIoCode.STORAGE)
                        out.write(buffer, 0, count)
                    }
                    out.toByteArray()
                }
            } catch (error: FileNotFoundException) {
                if (registry.baseFile.exists() || File(registry.baseFile.path + ".bak").exists() ||
                    File(registry.baseFile.path + ".new").exists()) throw error
                loaded = true
                return
            }
            val parsed = LinkedHashMap<String, Entry>()
            val grants = LinkedHashSet<String>()
            DataInputStream(ByteArrayInputStream(bytes)).use { input ->
                if (input.readInt() != MAGIC || input.readInt() != 1) throw fixed(AndroidIoCode.STORAGE)
                val count = input.readInt()
                if (count !in 0..MAX_ENTRIES) throw fixed(AndroidIoCode.STORAGE)
                repeat(count) {
                    val id = input.readUTF()
                    val uri = input.readUTF()
                    val name = input.readUTF()
                    val type = input.readUTF()
                    val code = AndroidIoCode.ofRaw(input.readInt()) ?: throw fixed(AndroidIoCode.STORAGE)
                    val recoverable = strictBoolean(input)
                    val consumed = strictBoolean(input)
                    if (!validId(id) || uri.length > MAX_URI || Uri.parse(uri).scheme != "content" ||
                        Uri.parse(uri).authority.isNullOrBlank() ||
                        name != safeName(name, "") || name.isEmpty() || type !in setOf("photo", "file", "backup") ||
                        parsed.containsKey(id)) throw fixed(AndroidIoCode.STORAGE)
                    // Persistence-less selections still get an item, with a fixed permission result.
                    parsed[id] = Entry(id, uri, name, type,
                        if (!recoverable && code == AndroidIoCode.OK) AndroidIoCode.PERMISSION_DENIED else code,
                        recoverable, consumed)
                }
                val grantCount = input.readInt()
                if (grantCount !in 0..MAX_ENTRIES) throw fixed(AndroidIoCode.STORAGE)
                repeat(grantCount) {
                    val uri = input.readUTF()
                    if (uri.length > MAX_URI || Uri.parse(uri).scheme != "content" || !grants.add(uri) ||
                        parsed.values.none { it.uri == uri && it.recoverable }) throw fixed(AndroidIoCode.STORAGE)
                }
                if (input.read() != -1) throw fixed(AndroidIoCode.STORAGE)
            }
            entries.putAll(parsed)
            ownedGrants.addAll(grants)
            loaded = true
        } catch (_: Throwable) {
            registryFailed = true
            throw fixed(AndroidIoCode.STORAGE) // Unknown/corrupt bytes stay untouched; no empty reset.
        }
    }

    private fun strictBoolean(input: DataInputStream): Boolean = when (input.readUnsignedByte()) {
        0 -> false
        1 -> true
        else -> throw fixed(AndroidIoCode.STORAGE)
    }

    private fun checkRegistryLocked() {
        if (registryOwner !== this) throw fixed(AndroidIoCode.UNAVAILABLE)
        if (!loaded || registryFailed) throw fixed(AndroidIoCode.STORAGE)
    }

    private fun saveLocked() {
        checkRegistryLocked()
        val out = ByteArrayOutputStream()
        DataOutputStream(out).use { data ->
            data.writeInt(MAGIC)
            data.writeInt(1)
            data.writeInt(entries.size)
            for (entry in entries.values) {
                data.writeUTF(entry.id)
                data.writeUTF(entry.uri)
                data.writeUTF(entry.name)
                data.writeUTF(entry.type)
                data.writeInt(entry.code.raw)
                data.writeBoolean(entry.recoverable)
                data.writeBoolean(entry.consumed)
            }
            data.writeInt(ownedGrants.size)
            for (uri in ownedGrants) data.writeUTF(uri)
        }
        if (out.size() > MAX_REGISTRY_BYTES) throw fixed(AndroidIoCode.STORAGE)
        var stream: java.io.FileOutputStream? = null
        try {
            stream = registry.startWrite()
            stream.write(out.toByteArray())
            registry.finishWrite(stream)
        } catch (_: Throwable) {
            try { registry.failWrite(stream) } catch (_: Throwable) { }
            throw fixed(AndroidIoCode.STORAGE)
        }
    }

    private fun safeName(value: String, fallback: String): String {
        // Ordinary provider label only; never derive a label from a URI/path.
        val safe = buildString {
            var index = 0
            while (index < value.length && length < MAX_NAME) {
                val char = value[index++]
                if (char.isISOControl() || char == '/' || char == '\\') continue
                if (Character.isHighSurrogate(char)) {
                    if (index >= value.length || !Character.isLowSurrogate(value[index])) continue
                    if (length + 2 > MAX_NAME) break
                    append(char)
                    append(value[index++])
                } else if (!Character.isLowSurrogate(char)) append(char)
            }
        }
        return safe.ifBlank { fallback }
    }

    private fun validId(value: String): Boolean = try {
        value.length == 36 && UUID.fromString(value).toString() == value
    } catch (_: Throwable) { false }

    private fun classify(error: Throwable): AndroidIoCode = when (error) {
        is FlutterError -> when (error.code) {
            "permissionDenied" -> AndroidIoCode.PERMISSION_DENIED
            "sourceMissing" -> AndroidIoCode.SOURCE_MISSING
            "cloudPending" -> AndroidIoCode.CLOUD_PENDING
            "invalidInput" -> AndroidIoCode.INVALID_INPUT
            "cleanupPending" -> AndroidIoCode.CLEANUP_PENDING
            "cancelled" -> AndroidIoCode.CANCELLED
            "storage" -> AndroidIoCode.STORAGE
            else -> AndroidIoCode.UNAVAILABLE
        }
        is SecurityException -> AndroidIoCode.PERMISSION_DENIED
        is FileNotFoundException -> AndroidIoCode.SOURCE_MISSING
        is OperationCanceledException -> AndroidIoCode.CANCELLED
        else -> AndroidIoCode.UNAVAILABLE
    }
    private fun codeName(code: AndroidIoCode): String = when (code) {
        AndroidIoCode.PERMISSION_DENIED -> "permissionDenied"
        AndroidIoCode.SOURCE_MISSING -> "sourceMissing"
        AndroidIoCode.CLOUD_PENDING -> "cloudPending"
        AndroidIoCode.INVALID_INPUT -> "invalidInput"
        AndroidIoCode.CLEANUP_PENDING -> "cleanupPending"
        AndroidIoCode.CANCELLED -> "cancelled"
        AndroidIoCode.STORAGE -> "storage"
        else -> "unavailable"
    }
    private fun fixed(code: AndroidIoCode) = FlutterError(codeName(code), "Android resource operation did not complete.", null)
    private fun safe(error: Throwable) = fixed(classify(error))

    private fun <T> onMain(callback: (Result<T>) -> Unit, work: () -> Unit) {
        try {
            main.post {
                try { work() } catch (error: Throwable) { reply(callback, Result.failure(safe(error))) }
            }
        } catch (error: Throwable) { reply(callback, Result.failure(safe(error))) }
    }
    private fun <T> reply(callback: (Result<T>) -> Unit, result: Result<T>) {
        main.post {
            try { callback(result) } catch (_: Throwable) { /* Do not expose callback/system exceptions. */ }
        }
    }

    companion object {
        private val PROCESS_GATE = Any()
        // Process-only ownership: it deliberately does not survive process death, so
        // an ordinary new process can recover valid AtomicFile selections normally.
        private var registryOwner: AndroidResourceBridge? = null
        const val REQUEST_CODE = 47001
        private const val CHUNK_BYTES = 64 * 1024
        private const val MAX_ENTRIES = 1024
        private const val MAX_NAME = 255
        private const val MAX_URI = 8192
        private const val MAX_REGISTRY_BYTES = 16 * 1024 * 1024
        private const val MAGIC = 0x49485231 // IHR1, strict local format 1.
    }
}
