using MixLink.Core.Network;
using Xunit;

namespace MixLink.Core.Tests;

public class WebPlayerHtmlTests
{
    [Fact]
    public void GetHtml_ContainsHostIP()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("192.168.1.100", html);
    }

    [Fact]
    public void GetHtml_ContainsPort()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("19621", html);
    }

    [Fact]
    public void GetHtml_ContainsHostName()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "My Windows PC");

        // Assert
        Assert.Contains("My Windows PC", html);
    }

    [Fact]
    public void GetHtml_ContainsMixLinkTitle()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("<title>Mix Link</title>", html);
        Assert.Contains("Mix <span", html); // Title in body
    }

    [Fact]
    public void GetHtml_ContainsPlayButton()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("play-button", html);
        Assert.Contains("togglePlay()", html);
    }

    [Fact]
    public void GetHtml_ContainsWebSocketConnection()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("WebSocket", html);
        Assert.Contains("ws://", html);
    }

    [Fact]
    public void GetHtml_ContainsVisualizerBars()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("viz-bar", html);
        Assert.Contains("bar0", html);
        Assert.Contains("bar15", html);
    }

    [Fact]
    public void GetHtml_ContainsHTTPStreamFallback()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("/stream", html);
        Assert.Contains("connectHTTPStream", html);
    }

    [Fact]
    public void GetHtml_ContainsMediaSessionAPI()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert
        Assert.Contains("mediaSession", html);
        Assert.Contains("setupMediaSession", html);
    }

    [Fact]
    public void GetHtml_IsValidHTML()
    {
        // Act
        var html = WebPlayerHtml.GetHtml(19621, "192.168.1.100", "TestPC");

        // Assert - basic structure
        Assert.StartsWith("<!DOCTYPE html>", html);
        Assert.Contains("<html", html);
        Assert.Contains("</html>", html);
        Assert.Contains("<head>", html);
        Assert.Contains("</head>", html);
        Assert.Contains("<body>", html);
        Assert.Contains("</body>", html);
    }
}
