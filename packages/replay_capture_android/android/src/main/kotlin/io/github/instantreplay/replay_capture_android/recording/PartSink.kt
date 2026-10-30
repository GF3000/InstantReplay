package io.github.instantreplay.replay_capture_android.recording

import android.content.ContentResolver
import android.content.ContentValues
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.MediaStore
import java.io.Closeable
import java.nio.ByteBuffer
import java.nio.channels.FileChannel

/**
 * One file of a session recording while it is being written. Hidden from the gallery until
 * [publish]. Not thread-safe: the recorder uses it from its own thread only.
 */
internal interface PartSink : Closeable {
    /** Display name as stored (the store may rename on collision). */
    val name: String

    /** Persisted for crash recovery and passed back to [PartStore.open]. */
    val id: String

    fun size(): Long

    fun append(data: ByteArray)

    fun writeAt(position: Long, data: ByteArray)

    fun truncate(size: Long)

    /** Closes the file and makes it visible. */
    fun publish()

    /** Closes and deletes the file. */
    fun discard()
}

/** Where the recorder creates its parts: the gallery on a device, a plain directory in tests. */
internal interface PartStore {
    fun create(displayName: String): PartSink

    /** Reopens a part left unpublished by a crash; null when it no longer exists. */
    fun open(id: String, displayName: String): PartSink?
}

/** [PartSink] over a seekable channel; subclasses decide what publishing and discarding mean. */
internal abstract class ChannelPartSink(private val channel: FileChannel) : PartSink {

    override fun size(): Long = channel.size()

    override fun append(data: ByteArray) = writeAt(channel.size(), data)

    override fun writeAt(position: Long, data: ByteArray) {
        val buffer = ByteBuffer.wrap(data)
        var at = position
        while (buffer.hasRemaining()) at += channel.write(buffer, at)
    }

    override fun truncate(size: Long) {
        channel.truncate(size)
    }

    override fun close() = channel.close()
}

/**
 * Parts in the shared `Movies/InstantReplay` collection, created pending (`IS_PENDING = 1`) so the
 * gallery ignores them until they are finalized. No storage permission is needed for own items on
 * API 29+. Pending items survive an app kill and are reopened by URI on recovery.
 */
internal class MediaStorePartStore(private val resolver: ContentResolver) : PartStore {

    override fun create(displayName: String): PartSink {
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            put(MediaStore.Video.Media.RELATIVE_PATH, RELATIVE_PATH)
            put(MediaStore.Video.Media.DATE_TAKEN, System.currentTimeMillis())
            put(MediaStore.Video.Media.IS_PENDING, 1)
        }
        val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values) ?: error("MediaStore refused to create $displayName")
        return try {
            open(uri, queryName(uri) ?: displayName)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    override fun open(id: String, displayName: String): PartSink? {
        val uri = Uri.parse(id)
        return try {
            open(uri, displayName)
        } catch (_: Exception) {
            null // Deleted by the user or by the system (pending items expire after a week).
        }
    }

    private fun open(uri: Uri, displayName: String): PartSink {
        // "rw" never truncates, unlike "w" on some versions.
        val fd = resolver.openFileDescriptor(uri, "rw") ?: error("Cannot open $uri")
        val channel = ParcelFileDescriptor.AutoCloseOutputStream(fd).channel
        return object : ChannelPartSink(channel) {
            override val name = displayName
            override val id = uri.toString()

            override fun publish() {
                close()
                val values = ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) }
                resolver.update(uri, values, null, null)
            }

            override fun discard() {
                try {
                    close()
                } finally {
                    resolver.delete(uri, null, null)
                }
            }
        }
    }

    private fun queryName(uri: Uri): String? =
        resolver.query(uri, arrayOf(MediaStore.Video.Media.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0) else null
        }

    private companion object {
        const val RELATIVE_PATH = "Movies/InstantReplay"
    }
}
