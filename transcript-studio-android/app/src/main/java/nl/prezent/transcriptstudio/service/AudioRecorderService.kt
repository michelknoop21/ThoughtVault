package nl.prezent.transcriptstudio.service

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.sqrt

private const val TAG = "AudioRecorderService"
private const val SAMPLE_RATE = 16000
private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT

/**
 * Wraps Android AudioRecord to capture raw PCM and write WAV files.
 * 16kHz mono 16-bit, matching the backend Whisper requirements.
 *
 * This is NOT an Android Service — it is a plain service class for audio capture logic.
 * The foreground Service is [RecordingForegroundService].
 */
@Singleton
class AudioRecorderService @Inject constructor() {

    enum class State {
        IDLE,
        RECORDING,
        PAUSED,
    }

    private var audioRecord: AudioRecord? = null
    private var outputFile: File? = null
    private var outputStream: FileOutputStream? = null
    private var totalBytesWritten = 0L

    private val _state = MutableStateFlow(State.IDLE)
    val state: StateFlow<State> = _state.asStateFlow()

    /** Audio level (RMS normalized 0..1) updated at ~60 Hz. */
    private val _audioLevel = MutableStateFlow(0f)
    val audioLevel: StateFlow<Float> = _audioLevel.asStateFlow()

    /** Elapsed recording time in milliseconds (excludes paused time). */
    private val _elapsedMs = MutableStateFlow(0L)
    val elapsedMs: StateFlow<Long> = _elapsedMs.asStateFlow()

    val bufferSizeBytes: Int by lazy {
        val minBuffer = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        // Use a larger buffer for smooth reading, but at least minBuffer
        maxOf(minBuffer, SAMPLE_RATE * 2) // 1 second of 16-bit mono
    }

    /**
     * Start recording to a WAV file in the given directory.
     * Returns the output file path.
     * Must be called with RECORD_AUDIO permission already granted.
     */
    @SuppressLint("MissingPermission")
    fun start(outputDir: File): File {
        check(_state.value == State.IDLE) { "Already recording" }

        val file = File(outputDir, "recording_${System.currentTimeMillis()}.wav")
        outputFile = file
        totalBytesWritten = 0L
        _elapsedMs.value = 0L

        // Write WAV header placeholder (44 bytes)
        val fos = FileOutputStream(file)
        outputStream = fos
        writeWavHeader(fos, 0)

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            CHANNEL_CONFIG,
            AUDIO_FORMAT,
            bufferSizeBytes,
        ).also { recorder ->
            if (recorder.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "AudioRecord failed to initialize")
                fos.close()
                file.delete()
                throw IllegalStateException("AudioRecord failed to initialize")
            }
            recorder.startRecording()
        }

        _state.value = State.RECORDING
        Log.d(TAG, "Recording started: ${file.absolutePath}")
        return file
    }

    /**
     * Read audio data in a loop. Call this from a coroutine on Dispatchers.IO.
     * Returns when stop() or cancel() is called.
     */
    suspend fun readLoop() = withContext(Dispatchers.IO) {
        val buffer = ShortArray(bufferSizeBytes / 2)
        val byteBuffer = ByteArray(bufferSizeBytes)

        while (isActive && _state.value != State.IDLE) {
            val recorder = audioRecord ?: break

            if (_state.value == State.PAUSED) {
                // During pause, keep reading but discard (to keep AudioRecord alive)
                recorder.read(buffer, 0, buffer.size)
                _audioLevel.value = 0f
                continue
            }

            val shortsRead = recorder.read(buffer, 0, buffer.size)
            if (shortsRead <= 0) continue

            // Calculate RMS for audio level visualization
            var sumSquares = 0.0
            for (i in 0 until shortsRead) {
                val sample = buffer[i].toDouble()
                sumSquares += sample * sample
            }
            val rms = sqrt(sumSquares / shortsRead)
            // Normalize to 0..1 (Short.MAX_VALUE = 32767)
            _audioLevel.value = (rms / 32767.0).toFloat().coerceIn(0f, 1f)

            // Convert shorts to bytes (little-endian) and write
            val bytesToWrite = shortsRead * 2
            ByteBuffer.wrap(byteBuffer).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                .put(buffer, 0, shortsRead)

            outputStream?.write(byteBuffer, 0, bytesToWrite)
            totalBytesWritten += bytesToWrite

            // Update elapsed time based on bytes written
            // bytes = samples * 2 (16-bit), time = samples / sampleRate
            val totalSamples = totalBytesWritten / 2
            _elapsedMs.value = (totalSamples * 1000) / SAMPLE_RATE
        }
    }

    fun pause() {
        if (_state.value == State.RECORDING) {
            _state.value = State.PAUSED
            Log.d(TAG, "Recording paused")
        }
    }

    fun resume() {
        if (_state.value == State.PAUSED) {
            _state.value = State.RECORDING
            Log.d(TAG, "Recording resumed")
        }
    }

    /**
     * Stop recording and finalize the WAV file.
     * Returns the output file path.
     */
    fun stop(): File? {
        val file = outputFile ?: return null
        finishRecording()

        // Update WAV header with final data size
        try {
            RandomAccessFile(file, "rw").use { raf ->
                updateWavHeader(raf, totalBytesWritten)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update WAV header", e)
        }

        Log.d(TAG, "Recording stopped: ${file.absolutePath} (${totalBytesWritten} bytes)")
        return file
    }

    /**
     * Cancel recording and delete the file.
     */
    fun cancel() {
        val file = outputFile
        finishRecording()
        file?.delete()
        Log.d(TAG, "Recording cancelled")
    }

    private fun finishRecording() {
        audioRecord?.apply {
            try {
                stop()
            } catch (e: Exception) {
                Log.w(TAG, "Error stopping AudioRecord", e)
            }
            release()
        }
        audioRecord = null

        outputStream?.apply {
            try {
                flush()
                close()
            } catch (e: Exception) {
                Log.w(TAG, "Error closing output stream", e)
            }
        }
        outputStream = null

        _state.value = State.IDLE
        _audioLevel.value = 0f
    }

    /**
     * Write a WAV file header. dataSize=0 is used initially; updated after recording.
     */
    private fun writeWavHeader(out: FileOutputStream, dataSize: Long) {
        val totalSize = dataSize + 36
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN).apply {
            // RIFF chunk
            put("RIFF".toByteArray())
            putInt(totalSize.toInt())
            put("WAVE".toByteArray())
            // fmt sub-chunk
            put("fmt ".toByteArray())
            putInt(16) // Sub-chunk size
            putShort(1) // PCM format
            putShort(1) // Mono
            putInt(SAMPLE_RATE)
            putInt(SAMPLE_RATE * 2) // Byte rate (sampleRate * channels * bitsPerSample/8)
            putShort(2) // Block align (channels * bitsPerSample/8)
            putShort(16) // Bits per sample
            // data sub-chunk
            put("data".toByteArray())
            putInt(dataSize.toInt())
        }
        out.write(header.array())
    }

    /**
     * Update the WAV header with the actual data size after recording.
     */
    private fun updateWavHeader(raf: RandomAccessFile, dataSize: Long) {
        val totalSize = dataSize + 36
        // Update RIFF chunk size at offset 4
        raf.seek(4)
        raf.write(intToByteArrayLE(totalSize.toInt()))
        // Update data sub-chunk size at offset 40
        raf.seek(40)
        raf.write(intToByteArrayLE(dataSize.toInt()))
    }

    private fun intToByteArrayLE(value: Int): ByteArray {
        return ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(value).array()
    }
}
