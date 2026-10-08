package io.imagehost.imagehost

import androidx.annotation.Keep

/** The caller validates both closed private paths before the exclusive syscall. */
@Keep
internal object AndroidPublication {
    init { System.loadLibrary("imagehost_storage") }
    external fun renameExclusive(source: ByteArray, destination: ByteArray): Int
}
