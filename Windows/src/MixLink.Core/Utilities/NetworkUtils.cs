using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace MixLink.Core.Utilities;

/// <summary>
/// Network utility functions for detecting local IP addresses.
/// </summary>
public static class NetworkUtils
{
    /// <summary>
    /// Get the local IP address that can be used by other devices on the network.
    /// Prefers WiFi/Ethernet connections over virtual adapters.
    /// </summary>
    public static string? GetLocalIPAddress()
    {
        try
        {
            // First try: Get the IP used for outbound connections
            // This is the most reliable method
            using var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
            socket.Connect("8.8.8.8", 65530); // Google DNS - doesn't actually send anything
            var endPoint = socket.LocalEndPoint as IPEndPoint;
            if (endPoint != null && !IsLocalOnly(endPoint.Address))
            {
                return endPoint.Address.ToString();
            }
        }
        catch
        {
            // Fall through to alternative method
        }

        // Second try: Enumerate network interfaces
        try
        {
            var candidates = new List<(IPAddress Address, int Priority)>();

            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up)
                    continue;

                // Skip loopback, tunnel, and virtual adapters
                if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback ||
                    ni.NetworkInterfaceType == NetworkInterfaceType.Tunnel)
                    continue;

                // Skip common virtual adapter names
                var name = ni.Name.ToLowerInvariant();
                var description = ni.Description.ToLowerInvariant();
                if (name.Contains("virtual") || name.Contains("vmware") || name.Contains("vbox") ||
                    name.Contains("hyper-v") || name.Contains("loopback") ||
                    description.Contains("virtual") || description.Contains("vmware") ||
                    description.Contains("vbox") || description.Contains("hyper-v"))
                    continue;

                var ipProps = ni.GetIPProperties();
                foreach (var addr in ipProps.UnicastAddresses)
                {
                    if (addr.Address.AddressFamily != AddressFamily.InterNetwork)
                        continue;

                    if (IsLocalOnly(addr.Address))
                        continue;

                    // Prioritize by interface type
                    int priority = ni.NetworkInterfaceType switch
                    {
                        NetworkInterfaceType.Wireless80211 => 1, // WiFi first
                        NetworkInterfaceType.Ethernet => 2,
                        NetworkInterfaceType.GigabitEthernet => 2,
                        _ => 10
                    };

                    candidates.Add((addr.Address, priority));
                }
            }

            if (candidates.Count > 0)
            {
                return candidates.OrderBy(c => c.Priority).First().Address.ToString();
            }
        }
        catch
        {
            // Fall through
        }

        // Last resort: Get any local IPv4 address
        try
        {
            var host = Dns.GetHostEntry(Dns.GetHostName());
            foreach (var ip in host.AddressList)
            {
                if (ip.AddressFamily == AddressFamily.InterNetwork && !IsLocalOnly(ip))
                {
                    return ip.ToString();
                }
            }
        }
        catch
        {
            // Give up
        }

        return null;
    }

    /// <summary>
    /// Check if an IP address is local-only (loopback or link-local).
    /// </summary>
    private static bool IsLocalOnly(IPAddress address)
    {
        var bytes = address.GetAddressBytes();

        // 127.x.x.x (loopback)
        if (bytes[0] == 127)
            return true;

        // 169.254.x.x (link-local / APIPA)
        if (bytes[0] == 169 && bytes[1] == 254)
            return true;

        return false;
    }

    /// <summary>
    /// Get the computer's hostname.
    /// </summary>
    public static string GetHostName()
    {
        try
        {
            return Environment.MachineName;
        }
        catch
        {
            return "Windows PC";
        }
    }

    /// <summary>
    /// Check if a port is available for listening.
    /// </summary>
    public static bool IsPortAvailable(int port)
    {
        try
        {
            using var listener = new TcpListener(IPAddress.Any, port);
            listener.Start();
            listener.Stop();
            return true;
        }
        catch
        {
            return false;
        }
    }
}
