using NAudio.CoreAudioApi;
using NAudio.Wave;

namespace MixLink.Core.Audio;

/// <summary>
/// Captures system audio using WASAPI loopback.
/// Windows equivalent of Mac's ScreenCaptureKit audio capture.
/// </summary>
public sealed class WasapiLoopbackCapture : IDisposable
{
    private NAudio.Wave.WasapiLoopbackCapture? _capture;
    private WaveFormat? _captureFormat;
    private bool _isCapturing;
    private bool _disposed;

    // Target format: 48kHz, stereo, Float32
    private const int TargetSampleRate = 48000;
    private const int TargetChannels = 2;

    // Resampling state
    private MediaFoundationResampler? _resampler;
    private WaveBuffer? _resampleBuffer;

    // Packet building
    private uint _sequenceNumber;
    private readonly List<float> _sampleBuffer = new();
    private readonly object _bufferLock = new();

    /// <summary>
    /// Called when audio samples are captured.
    /// Parameters: samples (interleaved Float32), sampleRate, channels
    /// </summary>
    public event Action<float[], int, int>? OnAudioSamples;

    /// <summary>
    /// Called when a complete audio packet is ready for transmission.
    /// </summary>
    public event Action<AudioPacket>? OnAudioPacket;

    /// <summary>
    /// Called when capture status changes.
    /// </summary>
    public event Action<string>? OnStatusUpdate;

    /// <summary>
    /// Called when an error occurs.
    /// </summary>
    public event Action<string>? OnError;

    /// <summary>
    /// Whether audio is currently being captured.
    /// </summary>
    public bool IsCapturing => _isCapturing;

    /// <summary>
    /// Current capture sample rate.
    /// </summary>
    public int SampleRate => TargetSampleRate;

    /// <summary>
    /// Current capture channels.
    /// </summary>
    public int Channels => TargetChannels;

    /// <summary>
    /// Start capturing system audio.
    /// </summary>
    public void Start()
    {
        if (_isCapturing)
            return;

        try
        {
            OnStatusUpdate?.Invoke("Starting...");

            _capture = new NAudio.Wave.WasapiLoopbackCapture();
            _captureFormat = _capture.WaveFormat;

            OnStatusUpdate?.Invoke($"Device format: {_captureFormat.SampleRate}Hz, {_captureFormat.Channels}ch, {_captureFormat.BitsPerSample}bit");

            // Setup resampling if needed
            if (_captureFormat.SampleRate != TargetSampleRate || _captureFormat.Channels != TargetChannels)
            {
                SetupResampling();
            }

            _capture.DataAvailable += OnDataAvailable;
            _capture.RecordingStopped += OnRecordingStopped;

            _capture.StartRecording();
            _isCapturing = true;
            _sequenceNumber = 0;

            OnStatusUpdate?.Invoke("Capturing");
        }
        catch (Exception ex)
        {
            OnError?.Invoke($"Failed to start capture: {ex.Message}");
            throw;
        }
    }

    /// <summary>
    /// Stop capturing.
    /// </summary>
    public void Stop()
    {
        if (!_isCapturing)
            return;

        _isCapturing = false;

        try
        {
            _capture?.StopRecording();
        }
        catch
        {
            // Ignore errors during shutdown
        }

        CleanupCapture();
        OnStatusUpdate?.Invoke("Stopped");
    }

    private void SetupResampling()
    {
        // For now, we'll do manual resampling in OnDataAvailable
        // NAudio's resampler requires a provider, which complicates real-time capture
        OnStatusUpdate?.Invoke($"Will resample from {_captureFormat!.SampleRate}Hz to {TargetSampleRate}Hz");
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        if (e.BytesRecorded == 0)
            return;

        try
        {
            // Convert captured audio to target format
            var samples = ConvertToTargetFormat(e.Buffer, e.BytesRecorded);

            if (samples.Length > 0)
            {
                // Invoke raw samples callback
                OnAudioSamples?.Invoke(samples, TargetSampleRate, TargetChannels);

                // Build and send packets
                BuildAndSendPackets(samples);
            }
        }
        catch (Exception ex)
        {
            OnError?.Invoke($"Audio processing error: {ex.Message}");
        }
    }

    private float[] ConvertToTargetFormat(byte[] buffer, int bytesRecorded)
    {
        if (_captureFormat == null)
            return Array.Empty<float>();

        // First, convert bytes to float samples based on capture format
        float[] inputSamples;

        if (_captureFormat.Encoding == WaveFormatEncoding.IeeeFloat)
        {
            // Already float
            var floatCount = bytesRecorded / sizeof(float);
            inputSamples = new float[floatCount];
            Buffer.BlockCopy(buffer, 0, inputSamples, 0, bytesRecorded);
        }
        else if (_captureFormat.BitsPerSample == 16)
        {
            // 16-bit PCM
            var sampleCount = bytesRecorded / 2;
            inputSamples = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                var sample = BitConverter.ToInt16(buffer, i * 2);
                inputSamples[i] = sample / 32768f;
            }
        }
        else if (_captureFormat.BitsPerSample == 24)
        {
            // 24-bit PCM
            var sampleCount = bytesRecorded / 3;
            inputSamples = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                var sample = (buffer[i * 3 + 2] << 16) | (buffer[i * 3 + 1] << 8) | buffer[i * 3];
                if ((sample & 0x800000) != 0)
                    sample |= unchecked((int)0xFF000000); // Sign extend
                inputSamples[i] = sample / 8388608f;
            }
        }
        else if (_captureFormat.BitsPerSample == 32 && _captureFormat.Encoding == WaveFormatEncoding.Pcm)
        {
            // 32-bit PCM
            var sampleCount = bytesRecorded / 4;
            inputSamples = new float[sampleCount];
            for (int i = 0; i < sampleCount; i++)
            {
                var sample = BitConverter.ToInt32(buffer, i * 4);
                inputSamples[i] = sample / 2147483648f;
            }
        }
        else
        {
            // Unknown format - try treating as float
            var floatCount = bytesRecorded / sizeof(float);
            inputSamples = new float[floatCount];
            Buffer.BlockCopy(buffer, 0, inputSamples, 0, bytesRecorded);
        }

        // Now resample if needed
        if (_captureFormat.SampleRate != TargetSampleRate || _captureFormat.Channels != TargetChannels)
        {
            return ResampleAndConvertChannels(inputSamples, _captureFormat.SampleRate, _captureFormat.Channels);
        }

        return inputSamples;
    }

    private float[] ResampleAndConvertChannels(float[] input, int inputRate, int inputChannels)
    {
        var inputFrames = input.Length / inputChannels;
        var ratio = (double)TargetSampleRate / inputRate;
        var outputFrames = (int)(inputFrames * ratio);
        var output = new float[outputFrames * TargetChannels];

        for (int outFrame = 0; outFrame < outputFrames; outFrame++)
        {
            // Linear interpolation for resampling
            var inFrameF = outFrame / ratio;
            var inFrame0 = (int)inFrameF;
            var inFrame1 = Math.Min(inFrame0 + 1, inputFrames - 1);
            var frac = (float)(inFrameF - inFrame0);

            // Handle channel conversion
            if (inputChannels == 1)
            {
                // Mono to stereo
                var sample = input[inFrame0] * (1 - frac) + input[inFrame1] * frac;
                output[outFrame * 2] = sample;
                output[outFrame * 2 + 1] = sample;
            }
            else if (inputChannels >= 2)
            {
                // Take first two channels (stereo or downmix from surround)
                var left0 = input[inFrame0 * inputChannels];
                var left1 = input[inFrame1 * inputChannels];
                var right0 = input[inFrame0 * inputChannels + 1];
                var right1 = input[inFrame1 * inputChannels + 1];

                output[outFrame * 2] = left0 * (1 - frac) + left1 * frac;
                output[outFrame * 2 + 1] = right0 * (1 - frac) + right1 * frac;
            }
        }

        return output;
    }

    private void BuildAndSendPackets(float[] samples)
    {
        const int framesPerPacket = AudioPacket.TargetFramesPerPacket;
        const int samplesPerPacket = framesPerPacket * TargetChannels;

        lock (_bufferLock)
        {
            _sampleBuffer.AddRange(samples);

            // Send complete packets
            while (_sampleBuffer.Count >= samplesPerPacket)
            {
                var packetSamples = _sampleBuffer.GetRange(0, samplesPerPacket).ToArray();
                _sampleBuffer.RemoveRange(0, samplesPerPacket);

                var packet = AudioPacket.Create(_sequenceNumber++, packetSamples, TargetSampleRate, TargetChannels);
                OnAudioPacket?.Invoke(packet);
            }
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        if (e.Exception != null)
        {
            OnError?.Invoke($"Recording stopped with error: {e.Exception.Message}");
        }

        _isCapturing = false;
        OnStatusUpdate?.Invoke("Stopped");
    }

    private void CleanupCapture()
    {
        if (_capture != null)
        {
            _capture.DataAvailable -= OnDataAvailable;
            _capture.RecordingStopped -= OnRecordingStopped;
            _capture.Dispose();
            _capture = null;
        }

        _resampler?.Dispose();
        _resampler = null;

        lock (_bufferLock)
        {
            _sampleBuffer.Clear();
        }
    }

    public void Dispose()
    {
        if (_disposed)
            return;

        _disposed = true;
        Stop();
        CleanupCapture();
    }
}
