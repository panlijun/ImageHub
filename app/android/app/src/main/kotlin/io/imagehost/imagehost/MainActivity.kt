package io.imagehost.imagehost

import android.os.StatFs
import android.content.Intent
import android.system.OsConstants
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.file.FileSystemException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.attribute.BasicFileAttributes

class MainActivity : FlutterActivity() {
    private var networkBridge: NetworkTypeBridge? = null
    private var resourceBridge: AndroidResourceBridge? = null
    private var exportBridge: AndroidExportBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        resourceBridge?.dispose()
        exportBridge?.dispose()
        resourceBridge = AndroidResourceBridge(this)
        exportBridge = AndroidExportBridge(this)
        AndroidResourceHost.setUp(flutterEngine.dartExecutor.binaryMessenger, resourceBridge)
        AndroidExportHost.setUp(flutterEngine.dartExecutor.binaryMessenger, exportBridge)
        networkBridge?.dispose()
        networkBridge = NetworkTypeBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "io.imagehost/storage_capacity",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "availableBytes" -> {
                    try {
                        val directory = absolutePath(call.arguments)
                        checkDirectories(directory)
                        val bytes = StatFs(directory.toString()).availableBytes
                        check(bytes >= 0)
                        result.success(bytes)
                    } catch (_: Exception) {
                        result.error("read_error", "Unable to read available storage.", null)
                    }
                }
                "publishExclusive" -> {
                    var step = "validate"
                    try {
                        val arguments = call.arguments as? Map<*, *>
                            ?: throw IllegalArgumentException()
                        val source = absolutePath(arguments["source"])
                        val destination = absolutePath(arguments["destination"])
                        val sourceAttributes = Files.readAttributes(
                            source, BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS,
                        )
                        check(sourceAttributes.isRegularFile && !sourceAttributes.isSymbolicLink)
                        checkDirectories(source.parent ?: throw IllegalArgumentException())
                        checkDirectories(destination.parent ?: throw IllegalArgumentException())

                        step = "publish"
                        val errno = AndroidPublication.renameExclusive(
                            source.toString().toByteArray(Charsets.UTF_8),
                            destination.toString().toByteArray(Charsets.UTF_8),
                        )
                        if (errno == 0 || errno == OsConstants.EEXIST) {
                            result.success(errno == 0)
                        } else {
                            result.error("publish_error", "Unable to publish the backup file.",
                                mapOf("step" to step, "kind" to "syscall", "errno" to errno))
                        }
                    } catch (_: LinkageError) {
                        result.error("publish_error", "Unable to publish the backup file.",
                            mapOf("step" to step, "kind" to "unavailable"))
                    } catch (failure: Exception) {
                        // Only fixed classifications cross the channel. Paths and SDK
                        // exception messages must never become ordinary diagnostics.
                        val kind = when (failure) {
                            is UnsupportedOperationException -> "unsupported"
                            is SecurityException -> "permission"
                            is FileSystemException -> "filesystem"
                            is IllegalArgumentException, is IllegalStateException -> "validation"
                            else -> "unavailable"
                        }
                        result.error("publish_error", "Unable to publish the backup file.",
                            mapOf("step" to step, "kind" to kind))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        AndroidResourceHost.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        AndroidExportHost.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        resourceBridge?.dispose()
        exportBridge?.dispose()
        resourceBridge = null
        exportBridge = null
        networkBridge?.dispose()
        networkBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        resourceBridge?.dispose()
        exportBridge?.dispose()
        networkBridge?.dispose()
        networkBridge = null
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (resourceBridge?.onActivityResult(requestCode, resultCode, data) == true ||
            exportBridge?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun absolutePath(value: Any?): Path {
        val text = value as? String ?: throw IllegalArgumentException()
        require(text.isNotEmpty() && !text.contains('\u0000'))
        val path = Paths.get(text)
        require(path.isAbsolute && path == path.normalize())
        return path
    }

    private fun checkDirectories(directory: Path) {
        var current: Path? = directory
        while (current != null) {
            val attributes = Files.readAttributes(
                current, BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS,
            )
            check(attributes.isDirectory && !attributes.isSymbolicLink)
            current = current.parent
        }
    }
}
