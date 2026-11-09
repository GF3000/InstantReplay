package io.github.instantreplay.replay_capture_android.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.opengl.GLES20
import android.opengl.GLUtils
import android.opengl.Matrix
import io.github.instantreplay.replay_capture_android.broadcast.Scoreboard

/**
 * A text badge drawn top-right over the program, e.g. `REPETICIÓN` during a replay on air
 * (SPEC §12.6). [text] may be set from any thread; [draw] runs on the GL thread and uploads the
 * bitmap only when the text changed. Sized for a [referenceHeight]-high frame like the scoreboard.
 */
internal class LabelRenderer(private val referenceHeight: Int) {
    @Volatile var text: String? = null

    private val renderer = TextureRenderer(external = false)
    private val texture = TextureRenderer.create2dTexture(1, 1)
    private var uploaded: String? = null
    private var textureWidth = 0
    private var textureHeight = 0
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        color = 0xFFFFFFFF.toInt()
        textAlign = Paint.Align.CENTER
    }
    private val fill = Paint().apply { color = BACKGROUND }

    /** Draws the badge into the current target of [frameWidth]×[frameHeight]; nothing without text. */
    fun draw(frameWidth: Int, frameHeight: Int) {
        val t = text ?: return
        if (t != uploaded) upload(t)
        if (textureWidth == 0) return
        val height = Scoreboard.barHeight(frameHeight)
        val width = textureWidth * height / textureHeight
        val x = frameWidth - Scoreboard.margin(frameWidth) - width
        val y = frameHeight - Scoreboard.margin(frameHeight) - height
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        renderer.draw(texture, x, y, width, height, FLIP_Y)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    fun release() {
        renderer.release()
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
    }

    private fun upload(t: String) {
        val height = Scoreboard.barHeight(referenceHeight)
        paint.textSize = height * Scoreboard.TEXT_SIZE
        val width = (paint.measureText(t) + height * 0.8f).toInt()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), fill)
        val m = paint.fontMetrics
        canvas.drawText(t, width / 2f, height / 2f - (m.ascent + m.descent) / 2, paint)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        bitmap.recycle()
        textureWidth = width
        textureHeight = height
        uploaded = t
    }

    private companion object {
        /** Broadcast red, opaque enough to read over any picture. */
        const val BACKGROUND = 0xE6C62828.toInt()

        val FLIP_Y = FloatArray(16).also {
            Matrix.setIdentityM(it, 0)
            Matrix.translateM(it, 0, 0f, 1f, 0f)
            Matrix.scaleM(it, 0, 1f, -1f, 1f)
        }
    }
}
