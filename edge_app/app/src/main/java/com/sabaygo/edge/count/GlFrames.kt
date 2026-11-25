package com.sabaygo.edge.count

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Decoded video read back as pixels through OpenGL ES: the decoder draws
 * into [surface] (a SurfaceTexture, the way video reaches any screen), and
 * each frame is drawn scaled into an off-screen [width] x [height] buffer
 * and, when asked, read back as RGBA rows, top row first.
 *
 * Not an ImageReader: on the realme 8 5G (MediaTek) a decoded H.264 frame
 * cannot be locked for the CPU as YUV; `Image.getPlanes` aborted the app
 * on its first frame (24 Nov).
 *
 * Made, used and released on one thread, which keeps its GL context.
 * [onFrame] runs on that thread for every frame; calling the reader it is
 * given costs a draw and a read-back, so it is called only for frames
 * that will be looked at.
 */
class GlFrames(
    val width: Int,
    val height: Int,
    handler: Handler,
    private val onFrame: (read: () -> ByteBuffer) -> Unit,
) {
    private val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
    private val context: EGLContext
    private val buffer: EGLSurface
    private val program: Int
    private val texture: Int
    private val aPos: Int
    private val aTex: Int
    private val uSt: Int
    private val st = FloatArray(16)
    private val pixels = ByteBuffer.allocateDirect(width * height * 4).order(ByteOrder.nativeOrder())
    private var released = false
    private val textureIn: SurfaceTexture
    val surface: Surface

    init {
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }
        val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
        val found = IntArray(1)
        EGL14.eglChooseConfig(display, intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8, EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT, EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE), 0, configs, 0, 1, found, 0)
        val config = configs[0].takeIf { found[0] > 0 } ?: error("no EGL config for an RGBA pbuffer")
        context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0)
        check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }
        buffer = EGL14.eglCreatePbufferSurface(display, config,
            intArrayOf(EGL14.EGL_WIDTH, width, EGL14.EGL_HEIGHT, height, EGL14.EGL_NONE), 0)
        check(buffer != EGL14.EGL_NO_SURFACE) { "eglCreatePbufferSurface failed" }
        check(EGL14.eglMakeCurrent(display, buffer, buffer, context)) { "eglMakeCurrent failed" }

        program = link(shader(GLES20.GL_VERTEX_SHADER, VERTEX), shader(GLES20.GL_FRAGMENT_SHADER, FRAGMENT))
        aPos = GLES20.glGetAttribLocation(program, "aPos")
        aTex = GLES20.glGetAttribLocation(program, "aTex")
        uSt = GLES20.glGetUniformLocation(program, "uSt")
        texture = IntArray(1).also { GLES20.glGenTextures(1, it, 0) }[0]
        GLES20.glBindTexture(OES, texture)
        GLES20.glTexParameteri(OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glViewport(0, 0, width, height)

        textureIn = SurfaceTexture(texture).apply { setOnFrameAvailableListener({ onAvailable() }, handler) }
        surface = Surface(textureIn)
    }

    fun release() {
        if (released) return
        released = true
        surface.release()
        textureIn.release()
        GLES20.glDeleteTextures(1, intArrayOf(texture), 0)
        GLES20.glDeleteProgram(program)
        EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
        EGL14.eglDestroySurface(display, buffer)
        EGL14.eglDestroyContext(display, context)
        EGL14.eglReleaseThread()
    }

    /** Every frame is taken off the decoder, looked at or not, so it never waits. */
    private fun onAvailable() {
        if (released) return
        textureIn.updateTexImage()
        onFrame(::read)
    }

    private fun read(): ByteBuffer {
        textureIn.getTransformMatrix(st)
        GLES20.glUseProgram(program)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(OES, texture)
        GLES20.glUniformMatrix4fv(uSt, 1, false, st, 0)
        QUAD.position(0)
        GLES20.glVertexAttribPointer(aPos, 2, GLES20.GL_FLOAT, false, 16, QUAD)
        GLES20.glEnableVertexAttribArray(aPos)
        QUAD.position(2)
        GLES20.glVertexAttribPointer(aTex, 2, GLES20.GL_FLOAT, false, 16, QUAD)
        GLES20.glEnableVertexAttribArray(aTex)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        pixels.clear()
        GLES20.glReadPixels(0, 0, width, height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
        pixels.rewind()
        return pixels
    }

    private fun shader(type: Int, source: String): Int {
        val s = GLES20.glCreateShader(type)
        GLES20.glShaderSource(s, source)
        GLES20.glCompileShader(s)
        val ok = IntArray(1).also { GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, it, 0) }[0]
        check(ok != 0) { "shader: ${GLES20.glGetShaderInfoLog(s)}" }
        return s
    }

    private fun link(vertex: Int, fragment: Int): Int {
        val p = GLES20.glCreateProgram()
        GLES20.glAttachShader(p, vertex)
        GLES20.glAttachShader(p, fragment)
        GLES20.glLinkProgram(p)
        val ok = IntArray(1).also { GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, it, 0) }[0]
        check(ok != 0) { "program: ${GLES20.glGetProgramInfoLog(p)}" }
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        return p
    }

    private companion object {
        const val OES = GLES11Ext.GL_TEXTURE_EXTERNAL_OES

        /**
         * x, y, s, t. The picture's top (t = 1) is drawn at the buffer's
         * bottom row, which glReadPixels returns first: rows come back top
         * first, as a Bitmap holds them.
         */
        val QUAD = ByteBuffer.allocateDirect(16 * 4).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
            put(floatArrayOf(
                -1f, -1f, 0f, 1f,
                1f, -1f, 1f, 1f,
                -1f, 1f, 0f, 0f,
                1f, 1f, 1f, 0f,
            ))
        }

        const val VERTEX = """
            attribute vec4 aPos;
            attribute vec4 aTex;
            uniform mat4 uSt;
            varying vec2 vTex;
            void main() { gl_Position = aPos; vTex = (uSt * aTex).xy; }
        """
        const val FRAGMENT = """#extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 vTex;
            uniform samplerExternalOES sTex;
            void main() { gl_FragColor = texture2D(sTex, vTex); }
        """
    }
}
