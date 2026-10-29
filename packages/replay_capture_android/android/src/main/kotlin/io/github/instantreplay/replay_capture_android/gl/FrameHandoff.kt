package io.github.instantreplay.replay_capture_android.gl

import android.opengl.GLES20
import android.opengl.GLES30

/**
 * Passes frames from a producer GL thread to a consumer GL thread (contexts in one share group)
 * through RGBA textures, latest wins. The producer never waits for the consumer: with three
 * slots one is always neither pending nor being read, and a pending frame that was not taken
 * yet is replaced ([dropped]).
 *
 * GPU ordering uses fence syncs when [useFences] (GLES 3), else glFinish before handing over.
 * Create and [release] on the producer thread.
 */
internal class FrameHandoff(val width: Int, val height: Int, private val useFences: Boolean) {
    private class Slot(val texture: Int, val framebuffer: Int) {
        var ready = 0L // producer's draw into the texture
        var read = 0L // consumer's last draw from the texture
    }

    private val slots: List<Slot>
    private val lock = Any()
    private var pending = -1
    private var reading = -1
    private var scheduled = false

    @Volatile var dropped = 0L
        private set

    init {
        slots = List(SLOTS) {
            val texture = TextureRenderer.create2dTexture(width, height)
            val ids = IntArray(1)
            GLES20.glGenFramebuffers(1, ids, 0)
            GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, ids[0])
            GLES20.glFramebufferTexture2D(
                GLES20.GL_FRAMEBUFFER, GLES20.GL_COLOR_ATTACHMENT0, GLES20.GL_TEXTURE_2D, texture, 0,
            )
            val status = GLES20.glCheckFramebufferStatus(GLES20.GL_FRAMEBUFFER)
            check(status == GLES20.GL_FRAMEBUFFER_COMPLETE) { "Framebuffer incomplete: 0x${Integer.toHexString(status)}" }
            Slot(texture, ids[0])
        }
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
    }

    /**
     * Producer: runs [draw] with a free slot bound as the framebuffer and publishes it. Returns
     * true when the consumer must be woken (no [consume] is scheduled yet).
     */
    fun publish(draw: () -> Unit): Boolean {
        val index = synchronized(lock) { slots.indices.first { it != pending && it != reading } }
        val slot = slots[index]
        waitGpu(slot.read)
        slot.read = 0L
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, slot.framebuffer)
        draw()
        GLES20.glBindFramebuffer(GLES20.GL_FRAMEBUFFER, 0)
        slot.ready = fence()

        var stale: Slot? = null
        val wake = synchronized(lock) {
            if (pending >= 0) {
                stale = slots[pending]
                dropped++
            }
            pending = index
            !scheduled.also { scheduled = true }
        }
        stale?.let { deleteSync(it.ready); it.ready = 0L }
        return wake
    }

    /**
     * Consumer: takes the latest published frame, if any, and passes its texture to [draw]. A
     * context of the share group must be current.
     */
    fun consume(draw: (texture: Int) -> Unit) {
        val index = synchronized(lock) {
            scheduled = false
            pending.also { if (it >= 0) { reading = it; pending = -1 } }
        }
        if (index < 0) return
        val slot = slots[index]
        try {
            waitGpu(slot.ready)
            slot.ready = 0L
            draw(slot.texture)
        } finally {
            val read = fence()
            synchronized(lock) {
                slot.read = read
                reading = -1
            }
        }
    }

    fun release() {
        for (slot in slots) {
            deleteSync(slot.ready)
            deleteSync(slot.read)
            GLES20.glDeleteFramebuffers(1, intArrayOf(slot.framebuffer), 0)
            GLES20.glDeleteTextures(1, intArrayOf(slot.texture), 0)
        }
    }

    private fun fence(): Long = if (useFences) {
        // The flush makes the fence visible to (and signalable for) the other context.
        GLES30.glFenceSync(GLES30.GL_SYNC_GPU_COMMANDS_COMPLETE, 0).also { GLES20.glFlush() }
    } else {
        GLES20.glFinish()
        0L
    }

    // Server-side wait: queues the dependency on the GPU, the calling thread does not block.
    private fun waitGpu(sync: Long) {
        if (sync == 0L) return
        GLES30.glWaitSync(sync, 0, GLES30.GL_TIMEOUT_IGNORED)
        GLES30.glDeleteSync(sync)
    }

    private fun deleteSync(sync: Long) {
        if (sync != 0L) GLES30.glDeleteSync(sync)
    }

    private companion object {
        const val SLOTS = 3
    }
}
