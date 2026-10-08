package io.imagehost.imagehost

import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.file.FileAlreadyExistsException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.Paths
import java.nio.file.attribute.BasicFileAttributes

class MainActivity : FlutterActivity() {
    private var networkBridge: NetworkTypeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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

                        // createLink is exclusive and cannot copy across volumes or replace a
                        // racing destination. The upper layer owns the closed, immutable stage.
                        Files.createLink(destination, source)
                        try {
                            Files.delete(source)
                        } catch (_: Exception) {
                            // The destination is already committed. Keep its evidence and let
                            // the owned-stage cleanup/recovery retry removal of the source.
                        }
                        result.success(true)
                    } catch (_: FileAlreadyExistsException) {
                        result.success(false)
                    } catch (_: Exception) {
                        result.error("publish_error", "Unable to publish the backup file.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        networkBridge?.dispose()
        networkBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        networkBridge?.dispose()
        networkBridge = null
        super.onDestroy()
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
