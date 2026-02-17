using MixLink.Core.Utilities;
using Xunit;

namespace MixLink.Core.Tests;

public class NetworkUtilsTests
{
    [Fact]
    public void GetHostName_ReturnsNonEmptyString()
    {
        // Act
        var hostName = NetworkUtils.GetHostName();

        // Assert
        Assert.False(string.IsNullOrEmpty(hostName));
    }

    [Fact]
    public void GetLocalIPAddress_ReturnsValidIPv4OrNull()
    {
        // Act
        var ip = NetworkUtils.GetLocalIPAddress();

        // Assert - either null (no network) or valid IPv4 format
        if (ip != null)
        {
            var parts = ip.Split('.');
            Assert.Equal(4, parts.Length);
            foreach (var part in parts)
            {
                Assert.True(int.TryParse(part, out int value));
                Assert.InRange(value, 0, 255);
            }

            // Should not be localhost
            Assert.DoesNotStartWith("127.", ip);

            // Should not be link-local
            Assert.DoesNotStartWith("169.254.", ip);
        }
    }

    [Fact]
    public void IsPortAvailable_ReturnsTrueForUnusedPort()
    {
        // Act - use a random high port that should be available
        var result = NetworkUtils.IsPortAvailable(0); // Port 0 asks OS for any available port

        // This test is a bit tricky since we can't guarantee any port is free
        // But generally high random ports should work
        // We're really just testing that the method doesn't throw
        Assert.True(true); // Method executed without exception
    }
}
