
package com.example.bisindo_mobile

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Log

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarker

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val CHANNEL = "bisindo/holistic"

    private var holisticLandmarker: HolisticLandmarker? = null

    private val inferenceExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var debugFrameSaved = false

    companion object {
        private const val TARGET_WIDTH = 640
        private const val TARGET_HEIGHT = 360

        // Dipertahankan sementara sampai orientasi kamera diverifikasi.
        private const val TEST_ROTATION = 0

        private const val TAG = "BISINDO_CAMERA"

        private const val BODY_FEATURES = 24
        private const val HAND_FEATURES = 42
        private const val BODY_RIGHT_FEATURES = 66
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "initializeHolistic" -> {
                    inferenceExecutor.execute {
                        try {
                            if (holisticLandmarker == null) {
                                val baseOptions = BaseOptions.builder()
                                    .setModelAssetPath("holistic_landmarker.task")
                                    .build()

                                val options =
                                    HolisticLandmarker.HolisticLandmarkerOptions.builder()
                                        .setBaseOptions(baseOptions)
                                        .setRunningMode(RunningMode.IMAGE)
                                        .setMinFaceDetectionConfidence(0.5f)
                                        .setMinPoseDetectionConfidence(0.5f)
                                        .build()

                                holisticLandmarker =
                                    HolisticLandmarker.createFromOptions(
                                        this,
                                        options
                                    )
                            }

                            mainHandler.post {
                                result.success(
                                    "MediaPipe berhasil diinisialisasi"
                                )
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error(
                                    "MEDIAPIPE_INIT_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        }
                    }
                }

                "processFrame" -> {

                    val width = call.argument<Int>("width")
                    val height = call.argument<Int>("height")

                    val yBytes = call.argument<ByteArray>("y")
                    val uBytes = call.argument<ByteArray>("u")
                    val vBytes = call.argument<ByteArray>("v")

                    val yRowStride = call.argument<Int>("yRowStride")
                    val uRowStride = call.argument<Int>("uRowStride")
                    val vRowStride = call.argument<Int>("vRowStride")

                    val yPixelStride = call.argument<Int>("yPixelStride")
                    val uPixelStride = call.argument<Int>("uPixelStride")
                    val vPixelStride = call.argument<Int>("vPixelStride")

                    val rotationFromCamera =
                        call.argument<Int>("rotation") ?: 0

                    if (
                        width == null || height == null ||
                        yBytes == null || uBytes == null || vBytes == null ||
                        yRowStride == null || uRowStride == null ||
                        vRowStride == null || yPixelStride == null ||
                        uPixelStride == null || vPixelStride == null
                    ) {
                        result.error(
                            "INVALID_FRAME",
                            "Data frame kamera tidak lengkap",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    inferenceExecutor.execute {

                        var bitmap: Bitmap? = null

                        try {
                            val landmarker = holisticLandmarker
                                ?: throw IllegalStateException(
                                    "MediaPipe belum diinisialisasi"
                                )

                            // 1. Convert YUV to NV21
                            val nv21 = yuv420ToNv21(
                                width,
                                height,
                                yBytes,
                                uBytes,
                                vBytes,
                                yRowStride,
                                uRowStride,
                                vRowStride,
                                yPixelStride,
                                uPixelStride,
                                vPixelStride
                            )

                            // 2. Convert NV21 to JPEG
                            val output = ByteArrayOutputStream()

                            val yuvImage = YuvImage(
                                nv21,
                                ImageFormat.NV21,
                                width,
                                height,
                                null
                            )

                            val compressed = yuvImage.compressToJpeg(
                                Rect(0, 0, width, height),
                                85,
                                output
                            )

                            if (!compressed) {
                                throw IllegalStateException(
                                    "Gagal mengubah frame menjadi JPEG"
                                )
                            }

                            // 3. Decode JPEG
                            val decodedBitmap =
                                BitmapFactory.decodeByteArray(
                                    output.toByteArray(),
                                    0,
                                    output.size()
                                ) ?: throw IllegalStateException(
                                    "Gagal membaca gambar kamera"
                                )

                            bitmap = decodedBitmap

                            Log.d(
                                TAG,
                                "Bitmap sebelum resize: " +
                                    "${decodedBitmap.width} x ${decodedBitmap.height}"
                            )

                            // 4. Save debug image
                            val picturesDir =
                                getExternalFilesDir(
                                    Environment.DIRECTORY_PICTURES
                                ) ?: throw IllegalStateException(
                                    "Folder penyimpanan tidak tersedia"
                                )

                            val debugDir = File(
                                picturesDir,
                                "bisindo_debug"
                            )

                            if (!debugDir.exists() && !debugDir.mkdirs()) {
                                throw IllegalStateException(
                                    "Gagal membuat folder debug"
                                )
                            }

                            if (!debugFrameSaved) {
                                val debugFile = File(
                                    debugDir,
                                    "frame_before_resize.jpg"
                                )

                                FileOutputStream(debugFile).use { stream ->
                                    val saved = decodedBitmap.compress(
                                        Bitmap.CompressFormat.JPEG,
                                        95,
                                        stream
                                    )

                                    if (!saved) {
                                        throw IllegalStateException(
                                            "Gagal menyimpan gambar debug"
                                        )
                                    }
                                }

                                debugFrameSaved = true

                                Log.d(
                                    TAG,
                                    "DEBUG IMAGE: ${debugFile.absolutePath}"
                                )
                            }

                            // 5. Resize
                            val resizedBitmap = Bitmap.createScaledBitmap(
                                decodedBitmap,
                                TARGET_WIDTH,
                                TARGET_HEIGHT,
                                true
                            )

                            if (resizedBitmap !== decodedBitmap) {
                                decodedBitmap.recycle()
                            }

                            bitmap = resizedBitmap

                            Log.d(
                                TAG,
                                "Input MediaPipe: " +
                                    "${resizedBitmap.width} x ${resizedBitmap.height}"
                            )

                            // 6. Save resized image
                            val resizedDebugFile = File(
                                debugDir,
                                "frame_after_resize.jpg"
                            )

                            if (!resizedDebugFile.exists()) {
                                FileOutputStream(resizedDebugFile).use { stream ->
                                    resizedBitmap.compress(
                                        Bitmap.CompressFormat.JPEG,
                                        95,
                                        stream
                                    )
                                }

                                Log.d(
                                    TAG,
                                    "DEBUG AFTER RESIZE: ${resizedDebugFile.absolutePath}"
                                )
                            }

                            // 7. MediaPipe image
                            val mpImage =
                                BitmapImageBuilder(resizedBitmap).build()

                            val imageOptions =
                                ImageProcessingOptions.builder()
                                    .setRotationDegrees(TEST_ROTATION)
                                    .build()

                            Log.d(
                                TAG,
                                "Rotation dari Flutter: $rotationFromCamera"
                            )

                            Log.d(
                                TAG,
                                "Rotation MediaPipe: $TEST_ROTATION"
                            )

                            // 8. Detection
                            val detection = landmarker.detect(
                                mpImage,
                                imageOptions
                            )

                            val pose = detection.poseLandmarks()
                            val leftHand = detection.leftHandLandmarks()
                            val rightHand = detection.rightHandLandmarks()

                            Log.d(
                                TAG,
                                "Pose=${pose.size}, " +
                                    "LeftHand=${leftHand.size}, " +
                                    "RightHand=${rightHand.size}"
                            )

                            // 9. Extract coordinates
                            val bodyCoordinates =
                                extractBodyCoordinates(pose)

                            val leftHandCoordinates =
                                extractHandCoordinates(leftHand)

                            val rightHandCoordinates =
                                extractHandCoordinates(rightHand)

                            val leftHandDetected = leftHand.size >= 21
                            val rightHandDetected = rightHand.size >= 21

                            // 10. Body + Right Hand
                            val bodyRightCoordinates =
                                bodyCoordinates + rightHandCoordinates

                            if (
                                bodyCoordinates.size != BODY_FEATURES ||
                                rightHandCoordinates.size != HAND_FEATURES ||
                                bodyRightCoordinates.size != BODY_RIGHT_FEATURES
                            ) {
                                throw IllegalStateException(
                                    "Jumlah fitur tidak sesuai. " +
                                        "Body=${bodyCoordinates.size}, " +
                                        "RightHand=${rightHandCoordinates.size}, " +
                                        "BodyRight=${bodyRightCoordinates.size}"
                                )
                            }

                            // 11. Response
                            val response = mapOf(
                                "pose" to pose.size,
                                "leftHand" to leftHand.size,
                                "rightHand" to rightHand.size,

                                "leftHandDetected" to leftHandDetected,
                                "rightHandDetected" to rightHandDetected,

                                "bodyCoordinates" to bodyCoordinates,
                                "leftHandCoordinates" to leftHandCoordinates,
                                "rightHandCoordinates" to rightHandCoordinates,

                                "bodyRightCoordinates" to bodyRightCoordinates,
                                "featureCount" to bodyRightCoordinates.size
                            )

                            mainHandler.post {
                                result.success(response)
                            }

                        } catch (e: Exception) {
                            Log.e(TAG, "ERROR PROCESS FRAME", e)

                            mainHandler.post {
                                result.error(
                                    "FRAME_PROCESSING_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        } finally {
                            bitmap?.recycle()
                        }
                    }
                }

                "closeHolistic" -> {
                    inferenceExecutor.execute {
                        try {
                            holisticLandmarker?.close()
                            holisticLandmarker = null

                            mainHandler.post {
                                result.success("MediaPipe ditutup")
                            }
                        } catch (e: Exception) {
                            mainHandler.post {
                                result.error(
                                    "MEDIAPIPE_CLOSE_ERROR",
                                    e.message,
                                    null
                                )
                            }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    // BODY 24D
    private fun extractBodyCoordinates(
        pose: List<NormalizedLandmark>
    ): List<Float> {

        val coordinates = mutableListOf<Float>()

        fun addBodyPoint(index: Int) {
            if (index < pose.size) {
                coordinates.add(pose[index].x())
                coordinates.add(pose[index].y())
            } else {
                coordinates.add(0f)
                coordinates.add(0f)
            }
        }

        // Nose
        addBodyPoint(0)

        // Neck
        if (pose.size > 12) {
            val neckX = (pose[12].x() + pose[11].x()) / 2f
            val neckY = (pose[12].y() + pose[11].y()) / 2f

            coordinates.add(neckX)
            coordinates.add(neckY)
        } else {
            coordinates.add(0f)
            coordinates.add(0f)
        }

        // Body mapping
        listOf(
            5, 2, 8, 7, 12, 11, 14, 13, 16, 15
        ).forEach { index ->
            addBodyPoint(index)
        }

        return coordinates
    }

    // HAND 42D
    private fun extractHandCoordinates(
        landmarks: List<NormalizedLandmark>
    ): List<Float> {

        if (landmarks.size < 21) {
            return List(42) { 0f }
        }

        val handMap = listOf(
            0, 8, 7, 6, 5,
            12, 11, 10, 9,
            16, 15, 14, 13,
            20, 19, 18, 17,
            4, 3, 2, 1
        )

        return handMap.flatMap { index ->
            listOf(
                landmarks[index].x(),
                landmarks[index].y()
            )
        }
    }

    // YUV420 TO NV21
    private fun yuv420ToNv21(
        width: Int,
        height: Int,
        yBytes: ByteArray,
        uBytes: ByteArray,
        vBytes: ByteArray,
        yRowStride: Int,
        uRowStride: Int,
        vRowStride: Int,
        yPixelStride: Int,
        uPixelStride: Int,
        vPixelStride: Int
    ): ByteArray {

        require(width % 2 == 0 && height % 2 == 0) {
            "Ukuran frame harus genap"
        }

        val frameSize = width * height
        val nv21 = ByteArray(frameSize + frameSize / 2)

        // Y
        for (row in 0 until height) {
            for (col in 0 until width) {
                val index =
                    row * yRowStride + col * yPixelStride

                require(index < yBytes.size) {
                    "Data Y tidak lengkap"
                }

                nv21[row * width + col] = yBytes[index]
            }
        }

        // UV
        var outputIndex = frameSize

        for (row in 0 until height / 2) {
            for (col in 0 until width / 2) {

                val uIndex =
                    row * uRowStride + col * uPixelStride

                val vIndex =
                    row * vRowStride + col * vPixelStride

                require(
                    uIndex < uBytes.size &&
                    vIndex < vBytes.size
                ) {
                    "Data UV tidak lengkap"
                }

                nv21[outputIndex++] = vBytes[vIndex]
                nv21[outputIndex++] = uBytes[uIndex]
            }
        }

        return nv21
    }

    override fun onDestroy() {
        inferenceExecutor.execute {
            holisticLandmarker?.close()
            holisticLandmarker = null
        }

        inferenceExecutor.shutdown()

        super.onDestroy()
    }
}
