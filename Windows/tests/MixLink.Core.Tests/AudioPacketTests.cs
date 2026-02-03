using MixLink.Core.Audio;
using Xunit;

namespace MixLink.Core.Tests;

public class AudioPacketTests
{
    [Fact]
    public void Create_WithValidSamples_ProducesCorrectPacket()
    {
        // Arrange
        var samples = new float[] { 0.5f, -0.5f, 0.25f, -0.25f }; // 2 frames, stereo
        uint sequence = 42;
        int sampleRate = 48000;
        int channels = 2;

        // Act
        var packet = AudioPacket.Create(sequence, samples, sampleRate, channels);

        // Assert
        Assert.Equal(sequence, packet.Sequence);
        Assert.Equal((uint)sampleRate, packet.SampleRate);
        Assert.Equal((ushort)channels, packet.Channels);
        Assert.Equal((ushort)2, packet.FrameCount); // 4 samples / 2 channels = 2 frames
        Assert.Equal(samples.Length * sizeof(float), packet.AudioData.Length);
    }

    [Fact]
    public void ToBytes_ProducesCorrectFormat()
    {
        // Arrange
        var samples = new float[] { 1.0f, -1.0f };
        var packet = AudioPacket.Create(1, samples, 48000, 2);

        // Act
        var bytes = packet.ToBytes();

        // Assert
        Assert.Equal(AudioPacket.HeaderSize + samples.Length * sizeof(float), bytes.Length);

        // Check header (all little-endian)
        Assert.Equal(1u, BitConverter.ToUInt32(bytes, 0)); // sequence
        // timestamp is dynamic, skip
        Assert.Equal(48000u, BitConverter.ToUInt32(bytes, 8)); // sampleRate
        Assert.Equal((ushort)2, BitConverter.ToUInt16(bytes, 12)); // channels
        Assert.Equal((ushort)1, BitConverter.ToUInt16(bytes, 14)); // frameCount (2 samples / 2 channels = 1)
    }

    [Fact]
    public void ToBytes_HeaderSize_Is16Bytes()
    {
        Assert.Equal(16, AudioPacket.HeaderSize);
    }

    [Fact]
    public void Parse_RoundTrips_Correctly()
    {
        // Arrange
        var samples = new float[] { 0.1f, 0.2f, 0.3f, 0.4f, 0.5f, 0.6f, 0.7f, 0.8f };
        var original = AudioPacket.Create(123, samples, 48000, 2);
        var bytes = original.ToBytes();

        // Act
        var parsed = AudioPacket.Parse(bytes);

        // Assert
        Assert.NotNull(parsed);
        Assert.Equal(original.Sequence, parsed.Value.Sequence);
        Assert.Equal(original.Timestamp, parsed.Value.Timestamp);
        Assert.Equal(original.SampleRate, parsed.Value.SampleRate);
        Assert.Equal(original.Channels, parsed.Value.Channels);
        Assert.Equal(original.FrameCount, parsed.Value.FrameCount);
        Assert.Equal(original.AudioData.Length, parsed.Value.AudioData.Length);
    }

    [Fact]
    public void Parse_WithInsufficientData_ReturnsNull()
    {
        // Arrange
        var shortData = new byte[10]; // Less than header size

        // Act
        var result = AudioPacket.Parse(shortData);

        // Assert
        Assert.Null(result);
    }

    [Fact]
    public void TotalSize_IsCorrect()
    {
        // Arrange
        var samples = new float[] { 0.5f, 0.5f, 0.5f, 0.5f };
        var packet = AudioPacket.Create(0, samples, 48000, 2);

        // Act & Assert
        Assert.Equal(AudioPacket.HeaderSize + samples.Length * sizeof(float), packet.TotalSize);
    }

    [Fact]
    public void AudioData_ContainsCorrectSampleValues()
    {
        // Arrange
        var samples = new float[] { 0.123f, 0.456f, 0.789f, 0.012f };
        var packet = AudioPacket.Create(0, samples, 48000, 2);

        // Act
        var bytes = packet.ToBytes();
        var reconstructedSamples = new float[4];
        Buffer.BlockCopy(bytes, AudioPacket.HeaderSize, reconstructedSamples, 0, 16);

        // Assert
        for (int i = 0; i < samples.Length; i++)
        {
            Assert.Equal(samples[i], reconstructedSamples[i], 6); // 6 decimal precision
        }
    }

    [Fact]
    public void Create_WithTargetFramesPerPacket_ProducesExpectedFrameCount()
    {
        // Arrange - create samples for exactly one packet worth
        var framesPerPacket = AudioPacket.TargetFramesPerPacket; // 128
        var samples = new float[framesPerPacket * 2]; // stereo

        // Act
        var packet = AudioPacket.Create(0, samples, 48000, 2);

        // Assert
        Assert.Equal((ushort)framesPerPacket, packet.FrameCount);
    }

    [Fact]
    public void Sequence_Increments_Correctly()
    {
        // Arrange
        var samples = new float[] { 0f, 0f };

        // Act
        var packet1 = AudioPacket.Create(0, samples, 48000, 2);
        var packet2 = AudioPacket.Create(1, samples, 48000, 2);
        var packet3 = AudioPacket.Create(2, samples, 48000, 2);

        // Assert
        Assert.Equal(0u, packet1.Sequence);
        Assert.Equal(1u, packet2.Sequence);
        Assert.Equal(2u, packet3.Sequence);
    }
}
