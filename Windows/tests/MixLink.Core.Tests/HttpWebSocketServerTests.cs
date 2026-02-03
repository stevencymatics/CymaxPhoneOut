using MixLink.Core.Network;
using Xunit;

namespace MixLink.Core.Tests;

public class HttpWebSocketServerTests
{
    [Fact]
    public void Constructor_WithDefaultPort_Uses19621()
    {
        // Act
        using var server = new HttpWebSocketServer();

        // Assert
        Assert.Equal(19621, server.Port);
    }

    [Fact]
    public void Constructor_WithCustomPort_UsesSpecifiedPort()
    {
        // Act
        using var server = new HttpWebSocketServer(8080);

        // Assert
        Assert.Equal(8080, server.Port);
    }

    [Fact]
    public void IsRunning_BeforeStart_IsFalse()
    {
        // Act
        using var server = new HttpWebSocketServer();

        // Assert
        Assert.False(server.IsRunning);
    }

    [Fact]
    public void ConnectedClients_Initially_IsZero()
    {
        // Act
        using var server = new HttpWebSocketServer();

        // Assert
        Assert.Equal(0, server.ConnectedClients);
    }

    [Fact]
    public void HtmlContent_CanBeSetAndRetrieved()
    {
        // Arrange
        using var server = new HttpWebSocketServer();
        var html = "<html><body>Test</body></html>";

        // Act
        server.HtmlContent = html;

        // Assert
        Assert.Equal(html, server.HtmlContent);
    }

    [Fact]
    public void Stop_BeforeStart_DoesNotThrow()
    {
        // Arrange
        using var server = new HttpWebSocketServer();

        // Act & Assert - should not throw
        server.Stop();
        Assert.False(server.IsRunning);
    }

    [Fact]
    public void Dispose_CanBeCalledMultipleTimes()
    {
        // Arrange
        var server = new HttpWebSocketServer();

        // Act & Assert - should not throw
        server.Dispose();
        server.Dispose();
    }
}
