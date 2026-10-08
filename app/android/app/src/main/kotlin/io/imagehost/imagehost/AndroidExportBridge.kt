package io.imagehost.imagehost

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import android.system.ErrnoException
import java.io.Closeable
import java.io.File
import java.io.FileDescriptor
import java.io.InputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Only user-selected SAF destinations and newly inserted pending media rows are writable. */
class AndroidExportBridge(private val activity: Activity) : AndroidExportHost {
    private val resolver = activity.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private val executor = ThreadPoolExecutor(
        1, 1, 0L, TimeUnit.MILLISECONDS, ArrayBlockingQueue<Runnable>(4),
    )
    private val handles = HashMap<String, Destination>()
    private val operations = ConcurrentHashMap<String, Operation>()
    // A bounded session refuses further operations rather than evicting replay evidence.
    private val usedOperations = HashSet<String>()
    private var pending: Selection? = null
    @Volatile private var disposed = false

    private class Destination(
        val uri: Uri,
        val kind: AndroidDestinationKind,
        val name: String? = null,
        val mime: String? = null,
        val remaining: MutableSet<String>? = null,
    ) {
        val active = HashSet<String>()
        val closers = ArrayList<(Result<Unit>) -> Unit>()
        var closing = false
        var consumed = false
        var published = false
        var cleaned = false
        var uncertain = false
        var cleanupRunning = false
        var selectedMetadata: Metadata? = null
    }
    private data class Selection(
        val kind: AndroidDestinationKind,
        val name: String?,
        val mime: String?,
        val operationIds: Set<String>?,
        val callback: (Result<AndroidDestination>) -> Unit,
    )
    private class Operation(val request: AndroidExportRequest, val destination: Destination?) {
        val cancelled = AtomicBoolean(false)
        var closeFailed = false
    }
    private data class Digest(val sha: String, val length: Long)
    private data class Metadata(val name: String, val mime: String?, val size: Long?)
    private class Target(val uri: Uri, val media: Boolean, val name: String) {
        var owned = true
        var published = false
        var written: Digest? = null
    }
    private class Stop(val code: AndroidIoCode) : RuntimeException()

    override fun createDocument(
        displayName: String, mimeType: String, callback: (Result<AndroidDestination>) -> Unit,
    ) {
        select(AndroidDestinationKind.DOCUMENT, displayName, mimeType, null, callback)
    }

    override fun pickDirectory(operationIds: List<String>, callback: (Result<AndroidDestination>) -> Unit) {
        try {
            if (operationIds.isEmpty() || operationIds.size > MAX_OPERATIONS ||
                operationIds.any { !validUuid(it) || usedOperations.contains(it) } ||
                operationIds.toSet().size != operationIds.size) {
                selectionError(callback, "invalidInput")
                return
            }
            select(AndroidDestinationKind.TREE, null, null, operationIds.toSet(), callback)
        } catch (_: Throwable) { selectionError(callback, "unavailable") }
    }

    private fun select(
        kind: AndroidDestinationKind, name: String?, mime: String?,
        operationIds: Set<String>?,
        callback: (Result<AndroidDestination>) -> Unit,
    ) {
        try {
            if (disposed || pending != null || handles.size >= MAX_HANDLES) {
                selectionError(callback, "unavailable")
                return
            }
            if (kind == AndroidDestinationKind.DOCUMENT &&
                (!validName(name!!) || !validMime(mime!!))) {
                selectionError(callback, "invalidInput")
                return
            }
            val intent = if (kind == AndroidDestinationKind.DOCUMENT) {
                Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = mime
                    putExtra(Intent.EXTRA_TITLE, name)
                }
            } else Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            pending = Selection(kind, name, mime, operationIds, callback)
            activity.startActivityForResult(intent, if (kind == AndroidDestinationKind.DOCUMENT) CREATE else TREE)
        } catch (_: SecurityException) {
            pending = null
            selectionError(callback, "permissionDenied")
        } catch (_: Throwable) {
            pending = null
            selectionError(callback, "unavailable")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CREATE && requestCode != TREE) return false
        val selection = pending ?: return true
        if ((selection.kind == AndroidDestinationKind.DOCUMENT) != (requestCode == CREATE)) return true
        pending = null
        try {
            if (resultCode == Activity.RESULT_CANCELED) {
                // A late created document is retained: cancellation supplies no reliable ownership proof.
                selection.callback(Result.success(AndroidDestination(true)))
                return true
            }
            if (resultCode != Activity.RESULT_OK) {
                selectionError(selection.callback, "unconfirmed")
                return true
            }
            val uri = data?.data
            val required = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            if (uri == null || uri.scheme != "content" || ((data?.flags ?: 0) and required) != required) {
                selectionError(selection.callback, "permissionDenied")
                return true
            }
            if (selection.kind == AndroidDestinationKind.DOCUMENT &&
                !DocumentsContract.isDocumentUri(activity, uri) ||
                selection.kind == AndroidDestinationKind.TREE && !DocumentsContract.isTreeUri(uri)) {
                selectionError(selection.callback, "invalidInput")
                return true
            }
            val handle = UUID.randomUUID().toString()
            val destination = Destination(uri, selection.kind, selection.name, selection.mime,
                selection.operationIds?.toMutableSet())
            if (selection.kind == AndroidDestinationKind.DOCUMENT) {
                // Freeze the newly-created empty document before exposing its handle. Provider IO
                // remains on the bounded worker, including when the Activity is disposed meanwhile.
                executor.execute {
                    var verified = false
                    try {
                        val request = AndroidExportRequest(UUID.randomUUID().toString(), "", selection.name!!,
                            selection.mime!!, EMPTY_SHA, 0, AndroidDestinationKind.DOCUMENT)
                        val operation = Operation(request, destination)
                        val details = metadata(uri)
                        if (details.size == 0L && details.mime == selection.mime &&
                            targetDigest(uri, operation, 0, ignoreCancellation = true) == Digest(EMPTY_SHA, 0) &&
                            !operation.closeFailed && metadata(uri) == details) {
                            destination.selectedMetadata = details
                            verified = true
                        }
                    } catch (_: Throwable) { /* no unsafe new-document claim */ }
                    main.post {
                        if (!verified) selectionError(selection.callback, "unconfirmed")
                        else if (disposed) {
                            handles[handle] = destination
                            destination.closing = true
                            destination.closers.add { result ->
                                if (result.isSuccess) selection.callback(Result.success(AndroidDestination(true)))
                                else selectionError(selection.callback, "unconfirmed")
                            }
                            finishDestination(handle, destination)
                        } else {
                            handles[handle] = destination
                            try { selection.callback(Result.success(AndroidDestination(false, handle))) }
                            catch (_: Throwable) { /* no raw error escapes */ }
                        }
                    }
                }
                return true
            }
            handles[handle] = destination
            // Selection never returns the provider URI or persists a broad grant.
            selection.callback(Result.success(AndroidDestination(false, handle)))
        } catch (_: Throwable) {
            selectionError(selection.callback, "unavailable")
        }
        return true
    }

    override fun exportFile(request: AndroidExportRequest, callback: (Result<AndroidExportReply>) -> Unit) {
        try {
            if (!validRequest(request)) {
                complete(callback, AndroidExportReply(AndroidIoCode.INVALID_INPUT))
                return
            }
            if (disposed || usedOperations.size >= MAX_OPERATIONS ||
                usedOperations.contains(request.operationId) || operations.size >= 4) {
                complete(callback, AndroidExportReply(AndroidIoCode.UNAVAILABLE))
                return
            }
            val destination = if (request.kind == AndroidDestinationKind.PHOTOS) null
                else handles[request.destinationHandle]
            if (request.kind != AndroidDestinationKind.PHOTOS &&
                (destination == null || destination.closing || destination.kind != request.kind ||
                    request.kind == AndroidDestinationKind.DOCUMENT &&
                    (destination.consumed || destination.name != request.displayName || destination.mime != request.mimeType) ||
                    request.kind == AndroidDestinationKind.TREE && destination.remaining?.contains(request.operationId) != true)) {
                complete(callback, AndroidExportReply(AndroidIoCode.INVALID_INPUT))
                return
            }
            usedOperations.add(request.operationId)
            destination?.consumed = true
            destination?.remaining?.remove(request.operationId)
            destination?.active?.add(request.operationId)
            val operation = Operation(request, destination)
            operations[request.operationId] = operation
            try {
                executor.execute {
                    val reply = runExport(operation)
                    main.post {
                        operations.remove(request.operationId)
                        destination?.active?.remove(request.operationId)
                        try { callback(Result.success(reply)) } catch (_: Throwable) { /* fixed results only */ }
                        if (destination != null && destination.closing) finishDestination(request.destinationHandle!!, destination)
                    }
                }
            } catch (_: Throwable) {
                operations.remove(request.operationId)
                destination?.active?.remove(request.operationId)
                complete(callback, AndroidExportReply(AndroidIoCode.UNAVAILABLE))
            }
        } catch (_: Throwable) {
            complete(callback, AndroidExportReply(AndroidIoCode.UNAVAILABLE))
        }
    }

    override fun closeDestination(handle: String, callback: (Result<Unit>) -> Unit) {
        try {
            if (!validUuid(handle)) {
                unitReply(callback, false, "invalidInput")
                return
            }
            val destination = handles[handle]
            if (destination == null) {
                unitReply(callback, true)
                return
            }
            destination.closing = true
            destination.remaining?.clear()
            destination.closers.add(callback)
            operations.values.filter { it.destination === destination }.forEach { it.cancelled.set(true) }
            finishDestination(handle, destination)
        } catch (_: Throwable) { unitReply(callback, false) }
    }

    private fun finishDestination(handle: String, destination: Destination) {
        if (destination.active.isNotEmpty() || destination.closers.isEmpty() || destination.cleanupRunning) return
        if (destination.kind == AndroidDestinationKind.TREE || destination.published || destination.cleaned) {
            handles.remove(handle)
            val callbacks = destination.closers.toList()
            destination.closers.clear()
            callbacks.forEach { unitReply(it, true) }
            return
        }
        if (destination.uncertain) {
            val callbacks = destination.closers.toList()
            destination.closers.clear()
            callbacks.forEach { unitReply(it, false, "unconfirmed") }
            return
        }
        try {
            destination.cleanupRunning = true
            executor.execute {
                val request = AndroidExportRequest(UUID.randomUUID().toString(), "", destination.name!!,
                    destination.mime!!, EMPTY_SHA, 0, AndroidDestinationKind.DOCUMENT)
                val operation = Operation(request, destination)
                val cleaned = try {
                    val details = metadata(destination.uri)
                    if (details != destination.selectedMetadata || details.size != 0L || details.mime != destination.mime) false
                    else cleanupTarget(Target(destination.uri, false, details.name).apply {
                        written = Digest(EMPTY_SHA, 0)
                    }, operation)
                } catch (_: Throwable) { false }
                main.post {
                    destination.cleanupRunning = false
                    destination.cleaned = cleaned
                    destination.uncertain = !cleaned
                    if (cleaned) handles.remove(handle)
                    val callbacks = destination.closers.toList()
                    destination.closers.clear()
                    callbacks.forEach { unitReply(it, cleaned, "unconfirmed") }
                }
            }
        } catch (_: Throwable) {
            destination.cleanupRunning = false
            val callbacks = destination.closers.toList()
            destination.closers.clear()
            callbacks.forEach { unitReply(it, false) }
        }
    }

    override fun cancelExport(operationId: String) {
        try {
            if (!validUuid(operationId)) throw FlutterError("invalidInput", "Invalid export operation.")
            operations[operationId]?.cancelled?.set(true)
        } catch (safe: FlutterError) {
            throw safe
        } catch (_: Throwable) {
            throw FlutterError("unavailable", "Export cancellation unavailable.")
        }
    }

    /** Does not interrupt workers or issue an early completion while provider IO is still live. */
    fun dispose() {
        try {
            disposed = true
            operations.values.forEach { it.cancelled.set(true) }
            handles.values.forEach { it.closing = true; it.remaining?.clear() }
            executor.shutdown()
        } catch (_: Throwable) { /* never expose native failures during activity teardown */ }
    }

    private fun runExport(operation: Operation): AndroidExportReply {
        var target: Target? = null
        try {
            val request = operation.request
            checkCancelled(operation)
            val source = validatedSource(request.sourcePath)
            val original = sourceDigest(source, operation, verifyImage = request.kind == AndroidDestinationKind.PHOTOS)
            if (original != Digest(request.sha256, request.byteCount)) throw Stop(AndroidIoCode.INPUT_CHANGED)
            if (operation.closeFailed) throw Stop(AndroidIoCode.STORAGE)
            checkCancelled(operation)
            target = createTarget(operation)
            checkCancelled(operation)
            copySource(source, target, operation)
            if (operation.closeFailed) throw Stop(AndroidIoCode.STORAGE)
            if (target.written != original) throw Stop(AndroidIoCode.INPUT_CHANGED)
            val readback = targetDigest(target.uri, operation, request.byteCount)
            if (readback != original) throw Stop(AndroidIoCode.UNCONFIRMED)
            if (operation.closeFailed) throw Stop(AndroidIoCode.STORAGE)
            checkCancelled(operation)
            var details = metadata(target.uri)
            if (!validName(details.name) || details.mime != request.mimeType ||
                !target.media && details.size != null && details.size != request.byteCount)
                throw Stop(AndroidIoCode.UNCONFIRMED)
            checkCancelled(operation)
            if (target.media) {
                val values = ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) }
                if (resolver.update(target.uri, values, null, null) != 1) throw Stop(AndroidIoCode.UNCONFIRMED)
                // An update may have been published even if a subsequent observation fails.
                target.published = true
                if (!mediaStillOwned(target, pendingRequired = false)) throw Stop(AndroidIoCode.UNCONFIRMED)
                // Publishing performs the media scan and can choose a conflict-free name.
                // Return the published metadata, never the pre-scan requested display name.
                details = metadata(target.uri)
                if (!validName(details.name) || details.mime != request.mimeType ||
                    details.size != null && details.size != request.byteCount)
                    throw Stop(AndroidIoCode.UNCONFIRMED)
            } else target.published = true
            operation.destination?.published = true
            // Cancellation arriving after publication preserves the actual saved result.
            return AndroidExportReply(AndroidIoCode.OK, target.uri.toString(), details.name)
        } catch (failure: Throwable) {
            val code = when (failure) {
                is Stop -> failure.code
                is SecurityException -> AndroidIoCode.PERMISSION_DENIED
                is ErrnoException -> when (failure.errno) {
                    OsConstants.ENOENT -> AndroidIoCode.SOURCE_MISSING
                    OsConstants.EACCES, OsConstants.EPERM -> AndroidIoCode.PERMISSION_DENIED
                    else -> AndroidIoCode.STORAGE
                }
                else -> AndroidIoCode.STORAGE
            }
            if (target?.published == true) {
                operation.destination?.published = true
                return AndroidExportReply(AndroidIoCode.UNCONFIRMED)
            }
            if (target != null && !cleanupTarget(target, operation)) {
                operation.destination?.uncertain = true
                return AndroidExportReply(AndroidIoCode.CLEANUP_PENDING)
            }
            if (target != null) operation.destination?.cleaned = true
            return AndroidExportReply(code)
        }
    }

    private fun createTarget(operation: Operation): Target {
        val request = operation.request
        return when (request.kind) {
            AndroidDestinationKind.DOCUMENT -> {
                val uri = operation.destination!!.uri
                val details = metadata(uri)
                // ACTION_CREATE_DOCUMENT guarantees a newly created, non-overwritten document.
                // An externally modified nonempty result is never truncated, deleted, or adopted.
                if (details != operation.destination.selectedMetadata || details.mime != request.mimeType || details.size != 0L ||
                    targetDigest(uri, operation, 0) != Digest(EMPTY_SHA, 0)) throw Stop(AndroidIoCode.UNCONFIRMED)
                Target(uri, false, details.name).apply { written = Digest(EMPTY_SHA, 0) }
            }
            AndroidDestinationKind.TREE -> createTreeTarget(operation)
            AndroidDestinationKind.PHOTOS -> {
                val values = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, request.displayName)
                    put(MediaStore.Images.Media.MIME_TYPE, request.mimeType)
                    put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/ImageHub")
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
                val uri = resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
                    ?: throw Stop(AndroidIoCode.UNAVAILABLE)
                Target(uri, true, request.displayName).apply { written = Digest(EMPTY_SHA, 0) }
            }
        }
    }

    private fun createTreeTarget(operation: Operation): Target {
        val tree = operation.destination!!.uri
        val parentId = DocumentsContract.getTreeDocumentId(tree)
        val parent = DocumentsContract.buildDocumentUriUsingTree(tree, parentId)
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parentId)
        val ids = HashSet<String>()
        val names = HashSet<String>()
        val cursor = resolver.query(children, arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        ), null, null, null) ?: throw Stop(AndroidIoCode.UNCONFIRMED)
        try {
            while (cursor.moveToNext()) {
                if (ids.size >= MAX_CHILDREN) throw Stop(AndroidIoCode.UNAVAILABLE)
                ids.add(cursor.getString(0))
                names.add(cursor.getString(1))
            }
        } finally { closeReliably(cursor, operation) }
        checkCancelled(operation)
        val requested = operation.request.displayName
        var name = requested
        var number = 1
        while (names.contains(name)) {
            if (number > MAX_CHILDREN) throw Stop(AndroidIoCode.UNAVAILABLE)
            name = conflictName(requested, number++)
        }
        val uri = DocumentsContract.createDocument(resolver, parent, operation.request.mimeType, name)
            ?: throw Stop(AndroidIoCode.UNAVAILABLE)
        // A broken provider returning an old child never gains write/delete ownership.
        try {
            val id = DocumentsContract.getDocumentId(uri)
            if (ids.contains(id) || uri.authority != tree.authority ||
                !DocumentsContract.isChildDocument(resolver, parent, uri)) throw Stop(AndroidIoCode.CLEANUP_PENDING)
        } catch (_: Throwable) { throw Stop(AndroidIoCode.CLEANUP_PENDING) }
        return Target(uri, false, name).apply { written = Digest(EMPTY_SHA, 0) }
    }

    private fun copySource(source: File, target: Target, operation: Operation) {
        val input = openSource(source)
        try {
            // MediaStore insert creates a pending record; a first writer may be required
            // to create its bytes. Only this application's still-pending row is eligible.
            if (target.media && !mediaStillOwned(target, pendingRequired = true) ||
                !target.media && targetDigest(target.uri, operation, 0) != Digest(EMPTY_SHA, 0)) {
                target.owned = false
                throw Stop(AndroidIoCode.UNCONFIRMED)
            }
            // Append creates a new media file without truncating unexpected existing bytes.
            // Verify actual emptiness after creation and before the first byte is written.
            val output = resolver.openOutputStream(target.uri, if (target.media) "wa" else "w")
                ?: throw Stop(AndroidIoCode.UNAVAILABLE)
            val digest = MessageDigest.getInstance("SHA-256")
            var length = 0L
            try {
                if (target.media && (!mediaStillOwned(target, pendingRequired = true) ||
                    targetDigest(target.uri, operation, 0) != Digest(EMPTY_SHA, 0))) {
                    target.owned = false
                    throw Stop(AndroidIoCode.UNCONFIRMED)
                }
                val buffer = ByteArray(BUFFER_SIZE)
                while (true) {
                    checkCancelled(operation)
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (count == 0) continue
                    if (length > operation.request.byteCount - count) throw Stop(AndroidIoCode.INPUT_CHANGED)
                    // A throwing write has unknown partial effects; no guessed prefix is cleanup evidence.
                    target.written = null
                    output.write(buffer, 0, count)
                    digest.update(buffer, 0, count)
                    length += count
                }
                output.flush()
            } catch (failure: Throwable) {
                if (failure is Stop) {
                    target.written = Digest(hex(digest.digest()), length)
                }
                throw failure
            } finally {
                closeReliably(output, operation)
            }
            target.written = Digest(hex(digest.digest()), length)
        } finally { closeReliably(input, operation) }
    }

    private fun sourceDigest(source: File, operation: Operation, verifyImage: Boolean): Digest {
        val input = openSource(source)
        try {
            if (verifyImage) {
                val head = ByteArray(12)
                var used = 0
                while (used < head.size) {
                    checkCancelled(operation)
                    val count = input.read(head, used, head.size - used)
                    if (count < 0) break
                    if (count > 0) used += count
                }
                if (!imageHeaderMatches(head, used, operation.request.mimeType)) throw Stop(AndroidIoCode.INVALID_INPUT)
                val digest = MessageDigest.getInstance("SHA-256")
                digest.update(head, 0, used)
                return digestStream(input, operation, operation.request.byteCount, digest, used.toLong())
            }
            return digestStream(input, operation, operation.request.byteCount)
        } finally { closeReliably(input, operation) }
    }

    private fun targetDigest(uri: Uri, operation: Operation, maximum: Long, ignoreCancellation: Boolean = false): Digest {
        val input = resolver.openInputStream(uri) ?: throw Stop(AndroidIoCode.UNCONFIRMED)
        try { return digestStream(input, operation, maximum, ignoreCancellation = ignoreCancellation) }
        finally { closeReliably(input, operation) }
    }

    private fun digestStream(
        input: InputStream, operation: Operation, maximum: Long,
        digest: MessageDigest = MessageDigest.getInstance("SHA-256"), initial: Long = 0,
        ignoreCancellation: Boolean = false,
    ): Digest {
        val buffer = ByteArray(BUFFER_SIZE)
        var length = initial
        while (true) {
            if (!ignoreCancellation) checkCancelled(operation)
            val count = input.read(buffer)
            if (count < 0) break
            if (count == 0) continue
            if (length > maximum - count) throw Stop(AndroidIoCode.INPUT_CHANGED)
            digest.update(buffer, 0, count)
            length += count
        }
        return Digest(hex(digest.digest()), length)
    }

    private fun cleanupTarget(target: Target, operation: Operation): Boolean {
        try {
            if (!target.owned || target.published) return false
            val written = target.written ?: return false
            if (target.media && !mediaStillOwned(target, pendingRequired = true)) return false
            val before = metadata(target.uri)
            // Pending MediaStore SIZE is indexed metadata and may lag real bytes. The
            // bounded stream digest below supplies the actual byte/length evidence.
            if (before.name != target.name || !target.media && before.size != null && before.size != written.length) return false
            if (targetDigest(target.uri, operation, written.length, ignoreCancellation = true) != written) return false
            if (metadata(target.uri) != before) return false
            return if (target.media) resolver.delete(target.uri, null, null) == 1
                else DocumentsContract.deleteDocument(resolver, target.uri)
        } catch (_: Throwable) { return false }
    }

    private fun metadata(uri: Uri): Metadata {
        val cursor = resolver.query(uri, arrayOf(
            OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE, DocumentsContract.Document.COLUMN_MIME_TYPE,
        ), null, null, null) ?: throw Stop(AndroidIoCode.UNCONFIRMED)
        try {
            if (!cursor.moveToFirst()) throw Stop(AndroidIoCode.UNCONFIRMED)
            val name = cursor.getString(0) ?: throw Stop(AndroidIoCode.UNCONFIRMED)
            val size = if (cursor.isNull(1)) null else cursor.getLong(1)
            val mime = if (cursor.isNull(2)) null else cursor.getString(2)
            if (cursor.moveToNext()) throw Stop(AndroidIoCode.UNCONFIRMED)
            return Metadata(name, mime, size)
        } finally {
            // Cursor close is synchronous; unlike live streams it cannot retain source byte IO.
            try { cursor.close() } catch (_: Throwable) { throw Stop(AndroidIoCode.UNCONFIRMED) }
        }
    }

    private fun mediaStillOwned(target: Target, pendingRequired: Boolean): Boolean {
        val cursor = resolver.query(target.uri, arrayOf(
            MediaStore.Images.Media.OWNER_PACKAGE_NAME, MediaStore.Images.Media.IS_PENDING,
        ), null, null, null) ?: return false
        try {
            if (!cursor.moveToFirst()) return false
            return cursor.getString(0) == activity.packageName &&
                cursor.getInt(1) == (if (pendingRequired) 1 else 0) && !cursor.moveToNext()
        } finally { cursor.close() }
    }

    private fun validatedSource(path: String): File {
        if (path.indexOf('\u0000') >= 0) throw Stop(AndroidIoCode.INVALID_INPUT)
        val file = File(path)
        if (!file.isAbsolute) throw Stop(AndroidIoCode.INVALID_INPUT)
        val canonical = file.canonicalFile
        // Android may expose /data/user/0 as a system alias. Only the exact platform-provided
        // app root alias is trusted; symlinks added below that root are still refused.
        val roots = listOf(activity.filesDir, activity.cacheDir).flatMap {
            listOf(it.absoluteFile to it.canonicalFile, it.canonicalFile to it.canonicalFile)
        }
        val selected = roots.firstOrNull { file.absolutePath.startsWith(it.first.path + File.separator) }
            ?: throw Stop(AndroidIoCode.INVALID_INPUT)
        val root = selected.second
        val suffix = file.absolutePath.substring(selected.first.path.length + 1)
        if (suffix.split(File.separatorChar).any { it.isEmpty() || it == "." || it == ".." } ||
            canonical.path != File(root, suffix).absolutePath) throw Stop(AndroidIoCode.INVALID_INPUT)
        var current: File? = canonical
        while (current != null && current.path != root.path) {
            val stat = Os.lstat(current.path)
            if (OsConstants.S_ISLNK(stat.st_mode)) throw Stop(AndroidIoCode.INVALID_INPUT)
            if (current == canonical && !OsConstants.S_ISREG(stat.st_mode)) throw Stop(AndroidIoCode.SOURCE_MISSING)
            if (current != canonical && !OsConstants.S_ISDIR(stat.st_mode)) throw Stop(AndroidIoCode.INVALID_INPUT)
            current = current.parentFile
        }
        if (current == null) throw Stop(AndroidIoCode.INVALID_INPUT)
        return canonical
    }

    // FileInputStream(FileDescriptor) on Android does not own the descriptor.
    // Keep the O_NOFOLLOW descriptor explicitly owned through its real close.
    private class OwnedSourceInput(private val descriptor: FileDescriptor) : InputStream() {
        private var closed = false
        override fun read(): Int {
            val byte = ByteArray(1)
            return if (read(byte, 0, 1) < 0) -1 else byte[0].toInt() and 0xff
        }
        override fun read(bytes: ByteArray, offset: Int, count: Int): Int {
            check(!closed)
            if (count == 0) return 0
            val received = Os.read(descriptor, bytes, offset, count)
            return if (received == 0) -1 else received
        }
        override fun close() {
            if (closed) return
            Os.close(descriptor)
            // A throwing syscall cannot set this flag and become a later no-op.
            closed = true
        }
    }

    private fun openSource(source: File): InputStream {
        validatedSource(source.path)
        val before = Os.lstat(source.path)
        val fd = Os.open(source.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try {
            val actual = Os.fstat(fd)
            validatedSource(source.path)
            if (!OsConstants.S_ISREG(actual.st_mode) || before.st_dev != actual.st_dev ||
                before.st_ino != actual.st_ino) throw Stop(AndroidIoCode.INPUT_CHANGED)
            return OwnedSourceInput(fd)
        } catch (failure: Throwable) {
            // Retain the descriptor until close really succeeds; no worker completion shortcut.
            while (true) {
                try { Os.close(fd); break } catch (_: Throwable) { pauseCloseRetry() }
            }
            throw failure
        }
    }

    private fun closeReliably(closeable: Closeable, operation: Operation) {
        var uncertainClosure = false
        while (true) {
            try {
                closeable.close()
                if (!uncertainClosure || closeable is OwnedSourceInput) return
                // Several Java/provider streams set their closed flag before throwing. A later
                // successful no-op is not evidence that the original provider IO has drained.
                // Keep this operation and its Dart lease alive instead of inventing completion.
                pauseCloseRetry()
            }
            catch (_: Throwable) {
                operation.closeFailed = true
                uncertainClosure = true
                // No timeout or cancellation releases the Dart input lease before real closure.
                pauseCloseRetry()
            }
        }
    }

    private fun pauseCloseRetry() {
        try { Thread.sleep(250) } catch (_: InterruptedException) { /* interruption is not closure */ }
    }

    private fun checkCancelled(operation: Operation) {
        if (disposed || operation.cancelled.get()) throw Stop(AndroidIoCode.CANCELLED)
    }

    private fun complete(callback: (Result<AndroidExportReply>) -> Unit, reply: AndroidExportReply) {
        main.post { try { callback(Result.success(reply)) } catch (_: Throwable) { /* no raw error escapes */ } }
    }

    private fun selectionError(callback: (Result<AndroidDestination>) -> Unit, code: String) {
        try { callback(Result.failure(FlutterError(code, "Export destination unavailable.", null))) }
        catch (_: Throwable) { /* no provider error or path escapes */ }
    }

    private fun unitReply(callback: (Result<Unit>) -> Unit, success: Boolean, code: String = "unavailable") {
        try {
            callback(if (success) Result.success(Unit)
                else Result.failure(FlutterError(code, "Export destination cleanup unconfirmed.", null)))
        } catch (_: Throwable) { /* fixed errors only */ }
    }

    private fun validRequest(request: AndroidExportRequest): Boolean =
        validUuid(request.operationId) && validName(request.displayName) && validMime(request.mimeType) &&
            request.sha256.matches(Regex("[0-9a-f]{64}")) && request.byteCount > 0 &&
            (if (request.kind == AndroidDestinationKind.PHOTOS)
                request.destinationHandle == null && photoNameMatches(request.displayName, request.mimeType)
            else request.destinationHandle?.let(::validUuid) == true)

    private fun validUuid(value: String): Boolean =
        value.matches(Regex("[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"))

    private fun validName(value: String): Boolean = value.isNotBlank() && value.length <= 240 &&
        value != "." && value != ".." && value.none { it == '/' || it == '\\' || it.code < 32 || it.code == 127 }

    private fun validMime(value: String): Boolean = value in setOf(
        "image/jpeg", "image/png", "image/webp", "image/gif", "image/bmp",
        "application/zip", "application/json", "text/plain", "application/octet-stream",
    )

    private fun photoNameMatches(name: String, mime: String): Boolean {
        val extension = name.substringAfterLast('.', "").lowercase(java.util.Locale.ROOT)
        return when (mime) {
            "image/jpeg" -> extension == "jpg" || extension == "jpeg"
            "image/png" -> extension == "png"
            "image/webp" -> extension == "webp"
            else -> false
        }
    }

    private fun imageHeaderMatches(head: ByteArray, used: Int, mime: String): Boolean = when (mime) {
        "image/jpeg" -> used >= 3 && head[0] == 0xff.toByte() && head[1] == 0xd8.toByte() && head[2] == 0xff.toByte()
        "image/png" -> used >= 8 && head.take(8) == listOf(137, 80, 78, 71, 13, 10, 26, 10).map { it.toByte() }
        "image/webp" -> used >= 12 && String(head, 0, 4, Charsets.US_ASCII) == "RIFF" &&
            String(head, 8, 4, Charsets.US_ASCII) == "WEBP"
        else -> false
    }

    private fun conflictName(name: String, number: Int): String {
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        val suffix = " ($number)$extension"
        return stem.take(240 - suffix.length) + suffix
    }

    private fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    companion object {
        private const val CREATE = 47002
        private const val TREE = 47003
        private const val BUFFER_SIZE = 64 * 1024
        private const val MAX_HANDLES = 16
        private const val MAX_OPERATIONS = 4096
        private const val MAX_CHILDREN = 100000
        private const val EMPTY_SHA = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
}
