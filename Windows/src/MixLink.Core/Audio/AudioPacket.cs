namespace MixLink.Core.Audio;

/// <summary>
/// Audio packet structure matching the Mac implementation exactly.
/// 16-byte header followed by Float32 interleaved audio samples.
/// </summary>
public readonly struct AudioPacket
{
    /// <summary>
    /// Packet sequence number (UInt32, little-endian)
    /// </summary>
    public uint Sequence { get; }

    /// <summary>
    /// Timestamp in milliseconds (UInt32, little-endian)
    /// </summary>
    public uint Timestamp { get; }

    /// <summary>
    /// Sample rate in Hz (UInt32, little-endian)
    /// </summary>
    public uint SampleRate { get; }

    /// <summary>
    /// Number of audio channels (UInt16, little-endian)
    /// </summary>
    public ushort Channels { get; }

    /// <summary>
    /// Number of frames in this packet (UInt16, little-endian)
    /// </summary>
    public ushort FrameCount { get; }

    /// <summary>
    /// Interleaved Float32 audio samples
    /// </summary>
    public ReadOnlyMemory<byte> AudioData { get; }

    /// <summary>
    /// Header size in bytes
    /// </summary>
    public const int HeaderSize = 16;

    /// <summary>
    /// Target frames per packet (2.67ms @ 48kHz)
    /// </summary>
    public const int TargetFramesPerPacket = 128;

    public AudioPacket(uint sequence, uint timestamp, uint sampleRate, ushort channels, ushort frameCount, ReadOnlyMemory<byte> audioData)
    {
        Sequence = sequence;
        Timestamp = timestamp;
        SampleRate = sampleRate;
        Channels = channels;
        FrameCount = frameCount;
        AudioData = audioData;
    }

    /// <summary>
    /// Total size of the packet including header and audio data
    /// </summary>
    public int TotalSize => HeaderSize + AudioData.Length;

    /// <summary>
    /// Convert to binary data for WebSocket/HTTP transmission.
    /// Format matches Mac implementation exactly.
    /// </summary>
    public byte[] ToBytes()
    {
        var result = new byte[TotalSize];
        var span = result.AsSpan();

        // Write 16-byte header (all little-endian)
        BitConverter.TryWriteBytes(span[0..4], Sequence);
        BitConverter.TryWriteBytes(span[4..8], Timestamp);
        BitConverter.TryWriteBytes(span[8..12], SampleRate);
        BitConverter.TryWriteBytes(span[12..14], Channels);
        BitConverter.TryWriteBytes(span[14..16], FrameCount);

        // Copy audio data
        AudioData.Span.CopyTo(span[HeaderSize..]);

        return result;
    }

    /// <summary>
    /// Create an AudioPacket from Float32 samples.
    /// </summary>
    public static AudioPacket Create(uint sequence, float[] samples, int sampleRate, int channels)
    {
        var frameCount = samples.Length / channels;
        var timestamp = (uint)(DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() & 0xFFFFFFFF);

        // Convert float array to bytes
        var audioBytes = new byte[samples.Length * sizeof(float)];
        Buffer.BlockCopy(samples, 0, audioBytes, 0, audioBytes.Length);

        return new AudioPacket(
            sequence,
            timestamp,
            (uint)sampleRate,
            (ushort)channels,
            (ushort)frameCount,
            audioBytes
        );
    }

    /// <summary>
    /// Parse an AudioPacket from raw bytes (for testing/debugging).
    /// </summary>
    public static AudioPacket? Parse(ReadOnlySpan<byte> data)
    {
        if (data.Length < HeaderSize)
            return null;

        var sequence = BitConverter.ToUInt32(data[0..4]);
        var timestamp = BitConverter.ToUInt32(data[4..8]);
        var sampleRate = BitConverter.ToUInt32(data[8..12]);
        var channels = BitConverter.ToUInt16(data[12..14]);
        var frameCount = BitConverter.ToUInt16(data[14..16]);

        var audioData = data[HeaderSize..].ToArray();

        return new AudioPacket(sequence, timestamp, sampleRate, channels, frameCount, audioData);
    }
}
