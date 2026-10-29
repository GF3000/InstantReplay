package io.github.instantreplay.replay_capture_android.gl

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.view.Surface

/**
 * One EGL context (GLES 3, else GLES 2) able to render into several window surfaces, including
 * encoder inputs. With [shared], the context joins that context's share group (textures and sync
 * objects are visible to both) and reuses its display; release it before [shared].
 */
internal class EglCore(shared: EglCore? = null) {
    private val display: EGLDisplay
    private val config: EGLConfig
    private val context: EGLContext
    private val ownsDisplay = shared == null

    /** 3 when the context supports GLES 3 (fence syncs), else 2. */
    val glVersion: Int

    init {
        if (shared != null) {
            display = shared.display
            config = shared.config
            glVersion = shared.glVersion
            context = createContext(config, glVersion, shared.context)
            check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext (shared) failed" }
        } else {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            check(display != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay failed" }
            val version = IntArray(2)
            check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }

            var chosen: Triple<EGLConfig, EGLContext, Int>? = null
            for (v in intArrayOf(3, 2)) {
                val c = chooseConfig(v) ?: continue
                val ctx = createContext(c, v, EGL14.EGL_NO_CONTEXT)
                if (ctx != EGL14.EGL_NO_CONTEXT) {
                    chosen = Triple(c, ctx, v)
                    break
                }
            }
            checkNotNull(chosen) { "No usable EGL config: EGL error 0x${Integer.toHexString(EGL14.eglGetError())}" }
            config = chosen.first
            context = chosen.second
            glVersion = chosen.third
        }
    }

    private fun chooseConfig(version: Int): EGLConfig? {
        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE,
            if (version == 3) EGLExt.EGL_OPENGL_ES3_BIT_KHR else EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT or EGL14.EGL_PBUFFER_BIT,
            EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val count = IntArray(1)
        return if (EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, count, 0) && count[0] > 0) configs[0] else null
    }

    private fun createContext(config: EGLConfig, version: Int, share: EGLContext): EGLContext =
        EGL14.eglCreateContext(display, config, share, intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, version, EGL14.EGL_NONE), 0)

    fun createWindowSurface(surface: Surface): EGLSurface =
        EGL14.eglCreateWindowSurface(display, config, surface, intArrayOf(EGL14.EGL_NONE), 0)
            .also { checkEgl("eglCreateWindowSurface") }

    /** For making the context current when it has no window surface. */
    fun createPbufferSurface(width: Int, height: Int): EGLSurface =
        EGL14.eglCreatePbufferSurface(display, config, intArrayOf(EGL14.EGL_WIDTH, width, EGL14.EGL_HEIGHT, height, EGL14.EGL_NONE), 0)
            .also { checkEgl("eglCreatePbufferSurface") }

    fun makeCurrent(surface: EGLSurface) {
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) { "eglMakeCurrent failed" }
    }

    /** 0 makes swaps on [surface] non-blocking, so a slow consumer can't stall the render thread. */
    fun setSwapInterval(surface: EGLSurface, interval: Int) {
        makeCurrent(surface)
        EGL14.eglSwapInterval(display, interval)
    }

    fun swapBuffers(surface: EGLSurface): Boolean = EGL14.eglSwapBuffers(display, surface)

    fun setPresentationTime(surface: EGLSurface, nanos: Long) {
        EGLExt.eglPresentationTimeANDROID(display, surface, nanos)
    }

    fun releaseSurface(surface: EGLSurface) {
        EGL14.eglDestroySurface(display, surface)
    }

    fun release() {
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroyContext(display, context)
        EGL14.eglReleaseThread()
        if (ownsDisplay) EGL14.eglTerminate(display)
    }

    private fun checkEgl(op: String) {
        val error = EGL14.eglGetError()
        check(error == EGL14.EGL_SUCCESS) { "$op: EGL error 0x${Integer.toHexString(error)}" }
    }

    private companion object {
        const val EGL_RECORDABLE_ANDROID = 0x3142
    }
}
