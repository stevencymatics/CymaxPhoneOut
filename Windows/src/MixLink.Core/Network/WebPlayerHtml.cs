namespace MixLink.Core.Network;

/// <summary>
/// Embedded HTML/JavaScript for the web audio player.
/// Matches the Mac implementation exactly.
/// </summary>
public static class WebPlayerHtml
{
    /// <summary>
    /// Get the HTML content for the web audio player.
    /// </summary>
    /// <param name="wsPort">WebSocket/HTTP port to connect to</param>
    /// <param name="hostIP">IP address of the Windows PC</param>
    /// <param name="hostName">Name of the PC</param>
    public static string GetHtml(int wsPort, string hostIP, string hostName)
    {
        return $@"<!DOCTYPE html>
<html lang=""en"">
<head>
    <meta charset=""UTF-8"">
    <meta name=""viewport"" content=""width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no, viewport-fit=cover"">
    <title>Cymatics Mix Link</title>
    <link rel=""icon"" href=""data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><circle cx='50' cy='50' r='45' fill='none' stroke='%2300d4ff' stroke-width='6'/><polygon points='40,30 40,70 72,50' fill='%2300d4ff'/></svg>"">
    <style>
        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }}

        html {{
            touch-action: manipulation;
            -ms-touch-action: manipulation;
        }}

        html, body {{
            height: 100%;
            height: 100dvh;
            overflow: hidden;
        }}

        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #000;
            display: flex;
            flex-direction: column;
            align-items: center;
            color: #fff;
            margin: 0;
            padding: 0;
            touch-action: manipulation;
            -webkit-touch-callout: none;
            -webkit-user-select: none;
            user-select: none;
            overscroll-behavior: none;
        }}

        .container {{
            text-align: center;
            max-width: 100%;
            width: 100%;
            height: 100%;
            padding: 0 10px;
            padding-top: env(safe-area-inset-top, 10px);
            padding-bottom: env(safe-area-inset-bottom, 10px);
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: space-evenly;
        }}

        .branding {{
            margin-bottom: 4px;
        }}
        .branding svg {{
            display: block;
            margin: 0 auto;
        }}
        .branding svg path {{
            fill: #fff;
        }}
        .mixlink-text {{
            font-size: 1.6rem;
            font-weight: 700;
            color: #00d4ff;
            margin-top: 6px;
            letter-spacing: 0.02em;
        }}

        .subtitle {{
            color: #888;
            margin: 0;
            font-size: 1.2rem;
        }}

        .play-button {{
            width: 130px;
            height: 130px;
            border-radius: 50%;
            border: none;
            background: linear-gradient(135deg, #00d4ff 0%, #00ffd4 100%);
            cursor: pointer;
            margin: 0;
            flex-shrink: 0;
            transition: all 0.2s;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 0;
            box-shadow: 0 0 30px rgba(0, 212, 255, 0.4);
        }}

        .play-button:hover {{
            background: linear-gradient(135deg, #00e5ff 0%, #00ffe5 100%);
            transform: scale(1.05);
            box-shadow: 0 0 40px rgba(0, 212, 255, 0.6);
        }}

        .play-button:active {{
            transform: scale(0.95);
        }}

        .play-button svg {{
            width: 55px;
            height: 55px;
            fill: #000;
        }}

        .play-button .play-icon {{
            margin-left: 10px;
        }}

        .play-button .pause-icon {{
            display: none;
        }}

        .play-button.playing .play-icon {{
            display: none;
        }}

        .play-button.playing .pause-icon {{
            display: block;
        }}

        .visualizer-container {{
            width: 100%;
            height: 100px;
            flex-shrink: 1;
            min-height: 60px;
            margin: 0;
            display: flex;
            align-items: flex-end;
            justify-content: center;
            gap: 6px;
        }}

        .viz-bar {{
            width: 14px;
            min-height: 6px;
            background: linear-gradient(to top, #00d4ff, #00ffd4);
            border-radius: 3px;
            transition: height 0.05s ease-out;
        }}

        .hidden {{
            display: none !important;
        }}

        .status {{
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            margin: 0;
        }}

        .status-dot {{
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #666;
        }}

        .status-dot.connected {{
            background: #4ade80;
            box-shadow: 0 0 10px rgba(74, 222, 128, 0.5);
        }}

        .status-dot.connecting {{
            background: #fbbf24;
            animation: pulse 1s infinite;
        }}

        .status-dot.error {{
            background: #ef4444;
        }}

        @keyframes pulse {{
            0%, 100% {{ opacity: 1; }}
            50% {{ opacity: 0.5; }}
        }}

        .status-text {{
            color: #a0a0a0;
            font-size: 0.85rem;
        }}

        .stats {{
            margin: 0;
            display: flex;
            align-items: flex-end;
            justify-content: center;
        }}

        .signal-bars {{
            display: flex;
            align-items: flex-end;
            gap: 2px;
            height: 18px;
        }}

        .signal-bars .bar {{
            width: 5px;
            border-radius: 1px;
            background: #333;
            transition: background 0.3s;
        }}

        .signal-bars .bar:nth-child(1) {{ height: 5px; }}
        .signal-bars .bar:nth-child(2) {{ height: 10px; }}
        .signal-bars .bar:nth-child(3) {{ height: 16px; }}

        .signal-bars.good .bar {{ background: #4ade80; }}
        .signal-bars.fair .bar:nth-child(1),
        .signal-bars.fair .bar:nth-child(2) {{ background: #fbbf24; }}
        .signal-bars.poor .bar:nth-child(1) {{ background: #ef4444; }}

        .error-message {{
            color: #ef4444;
            margin-top: 20px;
            font-size: 0.85rem;
        }}

        .reconnect-overlay {{
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.85);
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            z-index: 1000;
            opacity: 0;
            visibility: hidden;
            transition: opacity 0.2s, visibility 0.2s;
        }}

        .reconnect-overlay.visible {{
            opacity: 1;
            visibility: visible;
        }}

        .spinner {{
            width: 50px;
            height: 50px;
            border: 4px solid #333;
            border-top-color: #00d4ff;
            border-radius: 50%;
            animation: spin 0.8s linear infinite;
        }}

        @keyframes spin {{
            to {{ transform: rotate(360deg); }}
        }}

        .reconnect-text {{
            margin-top: 20px;
            color: #888;
            font-size: 1rem;
        }}
    </style>
</head>
<body>
    <div class=""container"">
        <div class=""branding"">
            <svg width=""200"" viewBox=""0 0 79 12"" fill=""none"" xmlns=""http://www.w3.org/2000/svg"">
                <path d=""M5.99133 6.81148C5.89922 6.58331 5.77665 6.37951 5.62333 6.20051C5.47 6.02181 5.29521 5.87022 5.09953 5.74562C4.90342 5.62131 4.69121 5.52673 4.46289 5.46189C4.23457 5.39735 4.00104 5.36471 3.76257 5.36471C3.41835 5.36471 3.09532 5.42955 2.79389 5.55908C2.49233 5.68861 2.22905 5.8666 2.00407 6.09332C1.77909 6.32004 1.60097 6.58839 1.46984 6.89837C1.33871 7.20864 1.27314 7.54256 1.27314 7.90041C1.27314 8.25826 1.33871 8.59144 1.46984 8.89983C1.60082 9.20836 1.77909 9.47599 2.00407 9.70242C2.22905 9.92928 2.49233 10.1071 2.79389 10.2367C3.09532 10.3662 3.41835 10.4309 3.76257 10.4309C4.00104 10.4309 4.2337 10.3994 4.46028 10.3364C4.68685 10.2734 4.8982 10.1805 5.09417 10.0578C5.29014 9.93494 5.46493 9.78423 5.6181 9.60552C5.77143 9.42652 5.894 9.22272 5.98611 8.99455H7.29479C7.18223 9.40346 7.00424 9.76552 6.76055 10.0809C6.51672 10.3961 6.23401 10.6611 5.9117 10.8758C5.58982 11.0904 5.24314 11.2533 4.87165 11.364C4.50017 11.4747 4.13043 11.5301 3.76228 11.5301C3.41473 11.5301 3.08067 11.4875 2.76039 11.4023C2.44011 11.3172 2.14115 11.1953 1.86337 11.0369C1.58545 10.8784 1.3316 10.6892 1.10154 10.4695C0.871632 10.2496 0.675664 10.0051 0.513638 9.73578C0.351902 9.4667 0.22556 9.17688 0.135481 8.86676C0.0451119 8.55678 0 8.23302 0 7.89562C0 7.55822 0.0449669 7.23431 0.135481 6.92433C0.22556 6.61421 0.351902 6.32468 0.513638 6.05531C0.675519 5.78624 0.871632 5.54167 1.10154 5.32177C1.3316 5.10187 1.58545 4.91359 1.86337 4.75678C2.14115 4.60013 2.44011 4.47901 2.76039 4.39386C3.08067 4.30871 3.41473 4.26607 3.76228 4.26607C4.13043 4.26607 4.50017 4.31959 4.87165 4.42693C5.24299 4.53427 5.58982 4.6947 5.9117 4.90735C6.23401 5.12044 6.51672 5.38632 6.76055 5.70486C7.00424 6.02355 7.18208 6.39416 7.29479 6.81685L5.99133 6.81148Z""/>
                <path d=""M16.6684 4.42937L13.9281 8.73372V11.3818H12.6553V8.7388L9.91534 4.42937H11.403L13.2842 7.57328H13.2995L15.1756 4.42937H16.6684Z""/>
                <path d=""M45.859 10.0583H42.6537L42.1067 11.3823H40.7624L43.6558 4.42479H44.862L47.7554 11.3823H46.4057L45.859 10.0583ZM43.1037 8.96427H45.404L44.2998 6.28047L44.259 6.10162H44.254L44.2129 6.28047L43.1037 8.96427Z""/>
                <path d=""M51.4648 5.52845H49.3994V4.42937H54.8082V5.52845H52.7377V11.3818H51.465L51.4648 5.52845Z""/>
                <path d=""M57.9703 4.42937H59.2432V11.3818H57.9703V4.42937Z""/>
                <path d=""M68.6423 6.81148C68.5503 6.58331 68.4277 6.37951 68.2744 6.20051C68.1209 6.02181 67.9463 5.87022 67.7503 5.74562C67.5542 5.62131 67.3421 5.52673 67.114 5.46189C66.8854 5.39735 66.6521 5.36471 66.4133 5.36471C66.0693 5.36471 65.7464 5.42955 65.4447 5.55908C65.1432 5.68861 64.8801 5.8666 64.6549 6.09332C64.43 6.31989 64.252 6.58839 64.1208 6.89837C63.9896 7.20864 63.9239 7.54256 63.9239 7.90041C63.9239 8.25826 63.9896 8.59144 64.1208 8.89983C64.2519 9.20836 64.43 9.47599 64.6549 9.70242C64.8801 9.92928 65.1432 10.1071 65.4447 10.2367C65.7464 10.3662 66.0693 10.4309 66.4133 10.4309C66.652 10.4309 66.8845 10.3994 67.1112 10.3364C67.3378 10.2734 67.549 10.1805 67.7451 10.0578C67.9412 9.93494 68.1159 9.78423 68.269 9.60552C68.4225 9.42652 68.5451 9.22272 68.637 8.99455H69.9457C69.8333 9.40346 69.655 9.76552 69.4115 10.0809C69.1676 10.3961 68.8849 10.6611 68.5628 10.8758C68.2406 11.0904 67.8939 11.2533 67.5224 11.364C67.1511 11.4747 66.7813 11.5301 66.4131 11.5301C66.0657 11.5301 65.7317 11.4875 65.4113 11.4023C65.0909 11.3172 64.7919 11.1953 64.514 11.0369C64.2364 10.8784 63.9824 10.6892 63.7525 10.4695C63.5224 10.2496 63.3264 10.0051 63.1646 9.73578C63.0025 9.4667 62.8765 9.17688 62.7861 8.86676C62.6959 8.55678 62.6506 8.23302 62.6506 7.89562C62.6506 7.55822 62.6957 7.23431 62.7861 6.92433C62.8765 6.61421 63.0025 6.32468 63.1646 6.05531C63.3263 5.78624 63.5224 5.54167 63.7525 5.32177C63.9824 5.10187 64.2364 4.91359 64.514 4.75678C64.7919 4.60013 65.0909 4.47901 65.4113 4.39386C65.7317 4.30871 66.0657 4.26607 66.4131 4.26607C66.7813 4.26607 67.1511 4.31959 67.5224 4.42693C67.8939 4.53427 68.2406 4.6947 68.5628 4.90735C68.8849 5.12044 69.1676 5.38632 69.4115 5.70486C69.655 6.02355 69.8331 6.39416 69.9457 6.81685L68.6423 6.81148Z""/>
                <path d=""M74.2889 9.29104C74.2889 9.45133 74.3263 9.60117 74.4013 9.741C74.4762 9.88069 74.5818 10.0025 74.7181 10.1064C74.8545 10.2104 75.0181 10.2922 75.2091 10.3517C75.3997 10.4113 75.6111 10.4412 75.8429 10.4412C76.3951 10.4412 76.8004 10.3534 77.0596 10.1779C77.3185 10.0024 77.4482 9.75275 77.4482 9.42899C77.4482 9.23157 77.4038 9.07027 77.315 8.94596C77.2267 8.82165 77.1011 8.71677 76.9393 8.63163C76.7776 8.54648 76.5842 8.47482 76.3591 8.41694C76.1343 8.35907 75.8872 8.2993 75.6182 8.23809C75.4715 8.20734 75.3121 8.17412 75.1401 8.13829C74.968 8.10261 74.7941 8.05576 74.6187 7.99774C74.4431 7.93971 74.2734 7.86907 74.1099 7.78552C73.9464 7.70212 73.8022 7.59811 73.6781 7.47366C73.5536 7.34934 73.4532 7.20284 73.3765 7.03414C73.2998 6.86544 73.2615 6.66527 73.2615 6.43347C73.2615 6.11638 73.3125 5.82511 73.4149 5.55937C73.5171 5.29349 73.6788 5.06532 73.9004 4.87428C74.1219 4.68353 74.4067 4.53427 74.7541 4.42693C75.1019 4.31959 75.521 4.26607 76.012 4.26607C76.4035 4.26607 76.7523 4.31625 77.0573 4.41678C77.3622 4.5173 77.6204 4.6596 77.8317 4.84367C78.043 5.0276 78.2039 5.24823 78.3147 5.50541C78.4256 5.76288 78.481 6.0482 78.481 6.36181H77.203C77.203 6.22213 77.1758 6.09245 77.1212 5.97307C77.0667 5.85398 76.9857 5.75012 76.8784 5.66134C76.7711 5.57272 76.6356 5.50266 76.472 5.45174C76.3083 5.40068 76.1174 5.37501 75.8996 5.37501C75.6302 5.37501 75.4077 5.40242 75.2323 5.45696C75.0567 5.5115 74.917 5.58214 74.813 5.66918C74.709 5.75621 74.6367 5.85572 74.5957 5.96813C74.5549 6.08055 74.5345 6.19471 74.5345 6.31061C74.5345 6.46408 74.577 6.59448 74.6623 6.70168C74.7474 6.80902 74.8649 6.89938 75.015 6.97264C75.1649 7.04603 75.3428 7.10652 75.5493 7.15424C75.7554 7.20182 75.9812 7.24273 76.2265 7.27682C76.5571 7.34847 76.8742 7.43115 77.1774 7.52486C77.4808 7.61856 77.7477 7.74476 77.9775 7.90302C78.2075 8.06142 78.3916 8.26261 78.5297 8.50615C78.6676 8.74984 78.7368 9.0575 78.7368 9.42884C78.7368 9.76624 78.6663 10.0664 78.5246 10.3286C78.3832 10.591 78.1848 10.8116 77.9292 10.9905C77.6736 11.1694 77.3668 11.3057 77.0089 11.3994C76.6511 11.4931 76.2542 11.54 75.8179 11.54C75.3372 11.54 74.9207 11.4737 74.568 11.3407C74.2152 11.2078 73.9241 11.0349 73.6937 10.8218C73.4637 10.6089 73.2934 10.3685 73.1827 10.101C73.072 9.8334 73.0168 9.56331 73.0168 9.29075L74.2889 9.29104Z""/>
                <path d=""M38.4953 11.0722C36.8449 11.0722 36.2011 9.10434 35.5709 7.20456C35.0131 5.50424 34.4827 3.89921 33.2131 3.89921C32.1567 3.89921 31.4676 5.01453 30.7965 6.09374C30.1844 7.08214 29.5541 8.10231 28.7199 8.10231C27.4504 8.10231 27.0151 6.0801 26.5979 4.12143C26.1673 2.09473 25.7183 0 24.2357 0C22.8483 0 22.0685 2.24892 21.1662 4.85149C20.1552 7.78043 19.0035 11.0994 16.8816 11.0994C16.7637 11.0949 16.6685 11.1946 16.6685 11.3125C16.6685 11.4304 16.7637 11.5301 16.8861 11.5301C18.6136 11.5301 19.9647 10.9996 21.1572 10.5325C22.1955 10.1245 23.1749 9.7436 24.2676 9.7436C25.8046 9.7436 26.6343 10.1426 27.4369 10.5281C28.1035 10.8454 28.7337 11.1492 29.6677 11.1492C30.7197 11.1492 31.2772 10.9225 31.7716 10.723C32.2069 10.5462 32.5877 10.3965 33.2542 10.3965C33.8845 10.3965 34.4013 10.5914 35.0089 10.8182C35.8296 11.1265 36.8452 11.5073 38.4911 11.5073C38.609 11.5073 38.7087 11.4122 38.7087 11.2897C38.7087 11.1673 38.6135 11.0722 38.4911 11.0722M29.0373 9.40809C30.1119 9.40809 30.7648 8.56474 31.395 7.75316C31.9528 7.03224 32.4741 6.35672 33.2268 6.35672C34.0565 6.35672 34.5371 7.318 35.0903 8.43332C35.3307 8.91389 35.58 9.41273 35.8747 9.86602C35.6934 9.68006 35.5256 9.48975 35.3579 9.2993C34.7413 8.601 34.1564 7.93912 33.2451 7.93912C32.3337 7.93912 31.8395 8.42433 31.3182 8.89126C30.7741 9.38096 30.2617 9.8434 29.3548 9.8434C28.4027 9.8434 27.8904 9.11348 27.3009 8.27013C26.6253 7.30436 25.859 6.20717 24.2585 6.20717C22.998 6.20717 22.0413 7.29087 21.0257 8.43332C20.6494 8.85949 20.264 9.28566 19.8604 9.67571C20.4726 8.84151 20.9894 7.82583 21.4791 6.8692C22.3542 5.15538 23.1794 3.53672 24.2449 3.53672C25.4873 3.53672 25.9949 4.93316 26.539 6.40676C27.0786 7.88037 27.6362 9.40823 29.0418 9.40823M28.7199 8.53762C29.79 8.53762 30.4881 7.41315 31.1638 6.32495C31.7714 5.34555 32.3971 4.33452 33.2131 4.33452C34.1698 4.33452 34.6505 5.79449 35.1582 7.34063C35.2443 7.59911 35.3305 7.8621 35.4212 8.12508C34.8499 6.97799 34.2877 5.92156 33.2266 5.92156C32.2609 5.92156 31.6442 6.71501 31.0502 7.48583C30.4562 8.25215 29.8986 8.97292 29.0372 8.97292C28.5475 8.97292 28.1848 8.70095 27.8809 8.28827C28.1213 8.44696 28.3979 8.53762 28.7199 8.53762ZM21.5788 4.99205C22.3903 2.64797 23.1567 0.435308 24.2357 0.435308C25.3692 0.435308 25.7774 2.35772 26.1763 4.21224C26.2035 4.33916 26.2307 4.47072 26.2579 4.59765C25.8091 3.74066 25.2196 3.10141 24.2449 3.10141C22.9118 3.10141 22.0277 4.83336 21.0937 6.66975C20.9486 6.95086 20.8036 7.24097 20.6494 7.52673C20.9849 6.70601 21.2885 5.8354 21.5788 4.99205ZM33.2584 9.95683C32.5012 9.95683 32.0478 10.1381 31.6126 10.315C31.132 10.5099 30.6378 10.7094 29.6676 10.7094C28.8334 10.7094 28.2711 10.4419 27.6227 10.129C26.8157 9.7436 25.8998 9.30379 24.2675 9.30379C23.0931 9.30379 22.0776 9.70284 20.9984 10.1245C20.4317 10.3467 19.8513 10.5733 19.2302 10.7503C20.0373 10.1972 20.7128 9.43086 21.3475 8.71908C22.2952 7.64901 23.1884 6.63798 24.2539 6.63798C25.6277 6.63798 26.2942 7.59012 26.9426 8.51513C27.5502 9.38111 28.1758 10.2744 29.3547 10.2744C30.4248 10.2744 31.055 9.71212 31.6081 9.21342C32.1115 8.75998 32.5421 8.37008 33.2449 8.37008C33.9477 8.37008 34.46 8.93231 35.0359 9.5852C35.385 9.98424 35.7794 10.4194 36.2783 10.7822C35.8658 10.6689 35.5075 10.5373 35.1675 10.4059C34.5236 10.1656 33.9705 9.95712 33.2632 9.95712""/>
            </svg>
            <div class=""mixlink-text"">Mix Link</div>
        </div>
        <p class=""subtitle"" id=""subtitle"">Stream audio from your Computer.</p>

        <button class=""play-button"" id=""playBtn"" onclick=""togglePlay()"">
            <svg class=""play-icon"" viewBox=""0 0 24 24"" xmlns=""http://www.w3.org/2000/svg"">
                <polygon points=""5,3 19,12 5,21""/>
            </svg>
            <svg class=""pause-icon"" viewBox=""0 0 24 24"" xmlns=""http://www.w3.org/2000/svg"">
                <rect x=""5"" y=""3"" width=""4"" height=""18""/>
                <rect x=""15"" y=""3"" width=""4"" height=""18""/>
            </svg>
        </button>

        <div class=""visualizer-container"" id=""visualizer"">
            <div class=""viz-bar"" id=""bar0""></div>
            <div class=""viz-bar"" id=""bar1""></div>
            <div class=""viz-bar"" id=""bar2""></div>
            <div class=""viz-bar"" id=""bar3""></div>
            <div class=""viz-bar"" id=""bar4""></div>
            <div class=""viz-bar"" id=""bar5""></div>
            <div class=""viz-bar"" id=""bar6""></div>
            <div class=""viz-bar"" id=""bar7""></div>
            <div class=""viz-bar"" id=""bar8""></div>
            <div class=""viz-bar"" id=""bar9""></div>
            <div class=""viz-bar"" id=""bar10""></div>
            <div class=""viz-bar"" id=""bar11""></div>
            <div class=""viz-bar"" id=""bar12""></div>
            <div class=""viz-bar"" id=""bar13""></div>
            <div class=""viz-bar"" id=""bar14""></div>
            <div class=""viz-bar"" id=""bar15""></div>
        </div>


        <div class=""stats"" id=""statsDisplay"">
            <div class=""signal-bars"" id=""signalBars"">
                <div class=""bar""></div>
                <div class=""bar""></div>
                <div class=""bar""></div>
            </div>
        </div>

        <div class=""error-message"" id=""errorMsg""></div>

        <div style=""display:none"">
            <span id=""wsStatus"">Not connected</span>
            <span id=""audioState"">Not started</span>
            <span id=""sampleRate"">-</span>
        </div>

    </div>

    <audio id=""outputAudio"" playsinline style=""display:none""></audio>

    <div class=""reconnect-overlay"" id=""reconnectOverlay"">
        <div class=""spinner""></div>
        <div class=""reconnect-text"">Reconnecting...</div>
    </div>

    <script>
        const WS_HOST = '{hostIP}';
        const WS_PORT = {wsPort};
        const HOST_NAME = '{hostName}';

        let audioContext = null;
        let gainNode = null;
        let scriptNode = null;
        let mediaStreamDest = null;
        let ws = null;
        let isPlaying = false;
        let packetsReceived = 0;
        let reconnectAttempts = 0;

        let sourceRate = 48000;
        let outputRate = 48000;
        let resampleRatio = 1.0;
        let sourceRateSet = false;

        let BUFFER_SIZE = 48000 * 2;
        let audioBuffer = new Float32Array(BUFFER_SIZE);
        let writePos = 0;
        let readPos = 0;
        let bufferedSamples = 0;

        const TARGET_BUFFER_MS = 80;
        const INITIAL_PREBUFFER_MS = 5;
        const REBUFFER_MS = 45;
        let targetBufferSamples = 48000 * 2 * (TARGET_BUFFER_MS / 1000);
        let prebufferSamples = 48000 * 2 * (INITIAL_PREBUFFER_MS / 1000);
        let rebufferSamples = 48000 * 2 * (REBUFFER_MS / 1000);
        let isPrebuffering = true;
        let isInitialStart = true;

        const NUM_BARS = 16;
        let vizBars = [];
        let vizLevels = new Array(NUM_BARS).fill(0);
        let vizAnimFrame = null;

        function initVisualizer() {{
            vizBars = [];
            for (let i = 0; i < NUM_BARS; i++) {{
                vizBars.push(document.getElementById('bar' + i));
            }}
        }}

        function updateVisualizer(samples) {{
            if (!samples || samples.length === 0) return;

            const samplesPerBar = Math.floor(samples.length / NUM_BARS);
            for (let i = 0; i < NUM_BARS; i++) {{
                let sum = 0;
                const start = i * samplesPerBar;
                for (let j = 0; j < samplesPerBar && (start + j) < samples.length; j++) {{
                    sum += Math.abs(samples[start + j]);
                }}
                const avg = sum / samplesPerBar;
                vizLevels[i] = vizLevels[i] * 0.7 + avg * 0.3;
            }}
        }}

        function animateVisualizer() {{
            for (let i = 0; i < NUM_BARS; i++) {{
                if (vizBars[i]) {{
                    const height = Math.max(6, Math.min(110, vizLevels[i] * 400));
                    vizBars[i].style.height = height + 'px';
                }}
            }}
            if (isPlaying) {{
                vizAnimFrame = requestAnimationFrame(animateVisualizer);
            }}
        }}

        function resetVisualizer() {{
            vizLevels.fill(0);
            for (let i = 0; i < NUM_BARS; i++) {{
                if (vizBars[i]) {{
                    vizBars[i].style.height = '6px';
                }}
            }}
            if (vizAnimFrame) {{
                cancelAnimationFrame(vizAnimFrame);
                vizAnimFrame = null;
            }}
        }}

        function debugLog(msg, level = 'info') {{
            if (level !== 'info') console.log('[Cymax] ' + msg);
        }}

        function updateStatus(status, text) {{
            const playBtn = document.getElementById('playBtn');

            if (status === 'connected' || isPlaying) {{
                playBtn.classList.add('playing');
            }} else {{
                playBtn.classList.remove('playing');
            }}
        }}

        function updateSubtitle(connected, customMessage) {{
            const subtitle = document.getElementById('subtitle');
            if (connected) {{
                const connectedIcon = '<svg style=""width:14px;height:14px;vertical-align:middle;margin-right:6px;"" viewBox=""0 0 24 24"" fill=""none"" stroke=""#4ade80"" stroke-width=""2.5""><path d=""M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71""/><path d=""M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71""/></svg>';
                subtitle.innerHTML = connectedIcon + 'Connected to <span style=""color: #fff; font-weight: 600;"">' + HOST_NAME + '</span>';
            }} else {{
                const disconnectedIcon = '<svg style=""width:14px;height:14px;vertical-align:middle;margin-right:6px;"" viewBox=""0 0 24 24"" fill=""none"" stroke=""#ef4444"" stroke-width=""2.5""><circle cx=""12"" cy=""12"" r=""9""/><line x1=""8"" y1=""8"" x2=""16"" y2=""16""/></svg>';
                const message = customMessage || 'Not connected to a computer.';
                subtitle.innerHTML = disconnectedIcon + message;
            }}
        }}

        function showError(msg) {{
            document.getElementById('errorMsg').textContent = msg;
            debugLog(msg, 'error');
        }}

        function togglePlay() {{
            if (isPlaying) {{
                stopAudio();
            }} else {{
                startAudio();
            }}
        }}

        async function startAudio() {{
            try {{
                showError('');
                updateStatus('connecting', 'Starting...');
                debugLog('Starting audio...');

                audioContext = new (window.AudioContext || window.webkitAudioContext)();
                outputRate = audioContext.sampleRate;

                debugLog('AudioContext created, state: ' + audioContext.state);
                debugLog('Output rate: ' + outputRate + 'Hz (waiting for source rate from packet)');

                BUFFER_SIZE = Math.ceil(outputRate * 2);
                audioBuffer = new Float32Array(BUFFER_SIZE);
                targetBufferSamples = Math.ceil(outputRate * 2 * (TARGET_BUFFER_MS / 1000));

                document.getElementById('audioState').textContent = audioContext.state;
                document.getElementById('sampleRate').textContent = outputRate + 'Hz (waiting for src)';

                if (audioContext.state === 'suspended') {{
                    debugLog('Resuming suspended AudioContext...');

                    const resumePromise = audioContext.resume();
                    const timeoutPromise = new Promise(resolve => setTimeout(resolve, 300));

                    await Promise.race([resumePromise, timeoutPromise]);

                    debugLog('AudioContext state after resume: ' + audioContext.state);
                    document.getElementById('audioState').textContent = audioContext.state;
                }}

                gainNode = audioContext.createGain();

                if (isAndroid) {{
                    // Android: connect directly to speakers
                    // MediaStreamDestination is unreliable on many Android Chrome versions
                    gainNode.connect(audioContext.destination);
                    debugLog('Android detected - using direct audioContext.destination');
                }} else {{
                    // iOS/other: route through <audio> element to bypass iOS silent mode
                    mediaStreamDest = audioContext.createMediaStreamDestination();
                    gainNode.connect(mediaStreamDest);
                    debugLog('MediaStream destination created (silent mode bypass)');

                    const outputAudio = document.getElementById('outputAudio');
                    outputAudio.srcObject = mediaStreamDest.stream;
                    outputAudio.play().then(() => {{
                        debugLog('Audio element playing (silent mode bypass active)');
                    }}).catch(e => {{
                        debugLog('Audio element play failed: ' + e.message, 'warn');
                    }});
                }}

                scriptNode = audioContext.createScriptProcessor(512, 0, 2);
                scriptNode.onaudioprocess = processAudio;
                scriptNode.connect(gainNode);
                debugLog('Script processor created (buffer: 512 frames, ~11ms)');

                connectWebSocket();

                isPlaying = true;
                updateStatus('connected', 'Playing');

                setupMediaSession();
                updateMediaSessionState(true);

                initVisualizer();
                animateVisualizer();

            }} catch (err) {{
                showError('Audio error: ' + err.message);
                updateStatus('error', 'Error');
                debugLog('Audio start error: ' + err.message, 'error');
            }}
        }}

        function stopAudio() {{
            debugLog('Stopping audio...');

            if (mediaStreamDest) {{
                try {{
                    const outputAudio = document.getElementById('outputAudio');
                    outputAudio.pause();
                    outputAudio.srcObject = null;
                }} catch (e) {{}}
            }}

            if (ws) {{
                ws.close();
                ws = null;
            }}

            if (httpWatchdog) {{
                clearInterval(httpWatchdog);
                httpWatchdog = null;
            }}
            if (httpStreamController) {{
                httpStreamController.abort();
                httpStreamController = null;
            }}
            if (httpStreamReader) {{
                try {{ httpStreamReader.cancel(); }} catch (e) {{}}
                httpStreamReader = null;
            }}

            if (audioContext) {{
                audioContext.close();
                audioContext = null;
            }}

            mediaStreamDest = null;

            isPlaying = false;
            packetsReceived = 0;
            bufferedSamples = 0;
            writePos = 0;
            readPos = 0;
            isPrebuffering = true;
            isInitialStart = true;

            updateMediaSessionState(false);

            updateStatus('', 'Stopped');
            updateSubtitle(false);
            resetVisualizer();
            document.getElementById('wsStatus').textContent = 'Not connected';
            document.getElementById('audioState').textContent = 'Stopped';
            debugLog('Audio stopped');
        }}

        let wsConnectionTimeout = null;
        let networkWarmedUp = false;

        async function warmUpNetwork() {{
            if (networkWarmedUp) {{
                debugLog('Network already warmed up, skipping');
                return true;
            }}

            const httpUrl = 'http://' + WS_HOST + ':19621/health';
            debugLog('Network warmup: fetching ' + httpUrl);
            const warmupStart = Date.now();

            try {{
                const response = await fetch(httpUrl, {{
                    method: 'GET',
                    cache: 'no-store'
                }});
                const elapsed = Date.now() - warmupStart;
                networkWarmedUp = true;
                debugLog('Network warmup SUCCESS in ' + elapsed + 'ms (status: ' + response.status + ')');
                return true;
            }} catch (err) {{
                const elapsed = Date.now() - warmupStart;
                debugLog('Network warmup FAILED in ' + elapsed + 'ms: ' + err.message, 'warn');
                return true;
            }}
        }}

        let httpStreamReader = null;
        let httpStreamController = null;

        const isSafari = /Safari/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent);
        const isIOSSafari = isSafari && /iPhone|iPad|iPod/.test(navigator.userAgent);
        const isAndroid = /Android/i.test(navigator.userAgent);

        async function connectWebSocket() {{
            await warmUpNetwork();

            const startTime = Date.now();

            // HTTP chunked streaming is more reliable than WebSocket across
            // all platforms — no handshake failures, no FD limits, works
            // through stricter browser security policies.
            debugLog('Using HTTP stream transport', 'info');
            connectHTTPStream();
            return;

            const url = 'ws://' + WS_HOST + ':' + WS_PORT;

            debugLog('=== CONNECTION ATTEMPT ===');
            debugLog('URL: ' + url);
            debugLog('Browser: ' + (isSafari ? 'Safari' : 'Chrome/Other'));
            debugLog('User-Agent: ' + navigator.userAgent.substring(0, 80));
            debugLog('Online: ' + navigator.onLine);
            debugLog('Attempt #' + (reconnectAttempts + 1));
            document.getElementById('wsStatus').textContent = 'Connecting...';

            try {{
                debugLog('Creating WebSocket object...');
                ws = new WebSocket(url);
                ws.binaryType = 'arraybuffer';
                debugLog('WebSocket created in ' + (Date.now() - startTime) + 'ms, readyState: ' + ws.readyState);

                const timeout = isSafari ? 2000 : 4000;
                wsConnectionTimeout = setTimeout(() => {{
                    if (ws && ws.readyState === 0) {{
                        const elapsed = Date.now() - startTime;
                        debugLog('TIMEOUT after ' + elapsed + 'ms (readyState still 0)', 'warn');
                        ws.close();
                    }}
                }}, timeout);

                ws.onopen = () => {{
                    clearTimeout(wsConnectionTimeout);
                    const elapsed = Date.now() - startTime;
                    debugLog('WebSocket CONNECTED in ' + elapsed + 'ms!', 'info');
                    document.getElementById('wsStatus').textContent = 'Connected (WebSocket)';
                    updateStatus('connected', 'Connected - Waiting for audio');
                    updateSubtitle(true);
                    reconnectAttempts = 0;
                    document.getElementById('reconnectOverlay').classList.remove('visible');

                    // Flush audio buffer on reconnect — stale data causes glitches
                    writePos = 0;
                    readPos = 0;
                    bufferedSamples = 0;
                    isPrebuffering = true;
                }};

                ws.onclose = (event) => {{
                    clearTimeout(wsConnectionTimeout);
                    const elapsed = Date.now() - startTime;
                    debugLog('CLOSED after ' + elapsed + 'ms - code: ' + event.code + ', wasClean: ' + event.wasClean, 'warn');
                    document.getElementById('wsStatus').textContent = 'Disconnected';

                    if (isPlaying) {{
                        reconnectAttempts++;
                        if (reconnectAttempts <= 2) {{
                            debugLog('Reconnect ' + reconnectAttempts + '/2...', 'info');
                            document.getElementById('reconnectOverlay').classList.add('visible');
                            updateStatus('connecting', 'Reconnecting...');
                            setTimeout(connectWebSocket, 1000);
                        }} else {{
                            debugLog('No connection found', 'warn');
                            document.getElementById('reconnectOverlay').classList.remove('visible');
                            updateSubtitle(false, 'No connection found. Please check computer.');
                            stopAudio();
                        }}
                    }}
                }};

                ws.onerror = (err) => {{
                    const elapsed = Date.now() - startTime;
                    debugLog('ERROR after ' + elapsed + 'ms - readyState: ' + (ws ? ws.readyState : 'null'), 'error');
                    document.getElementById('wsStatus').textContent = 'Error';
                    updateStatus('error', 'Connection error');
                }};

                ws.onmessage = (event) => {{
                    handleAudioPacket(event.data);
                }};
            }} catch (err) {{
                debugLog('WebSocket creation EXCEPTION: ' + err.message, 'error');
            }}
        }}

        let httpWatchdog = null;
        let lastPacketTime = 0;

        async function connectHTTPStream() {{
            if (httpStreamReader) {{
                try {{
                    await httpStreamReader.cancel();
                }} catch (e) {{}}
                httpStreamReader = null;
            }}
            if (httpWatchdog) {{
                clearInterval(httpWatchdog);
                httpWatchdog = null;
            }}

            const url = 'http://' + WS_HOST + ':' + WS_PORT + '/stream';
            debugLog('=== HTTP STREAM ===');
            debugLog('URL: ' + url);
            document.getElementById('wsStatus').textContent = 'Connecting...';

            try {{
                const controller = new AbortController();
                httpStreamController = controller;

                const response = await fetch(url, {{
                    method: 'GET',
                    cache: 'no-store',
                    signal: controller.signal
                }});

                if (!response.ok) {{
                    throw new Error('HTTP ' + response.status);
                }}

                debugLog('HTTP stream connected!', 'info');
                document.getElementById('wsStatus').textContent = 'Connected';
                updateStatus('connected', 'Connected - Waiting for audio');
                updateSubtitle(true);
                reconnectAttempts = 0;
                document.getElementById('reconnectOverlay').classList.remove('visible');
                lastPacketTime = Date.now();

                // Flush audio buffer on reconnect — stale data causes glitches
                writePos = 0;
                readPos = 0;
                bufferedSamples = 0;
                isPrebuffering = true;

                httpWatchdog = setInterval(() => {{
                    const staleDuration = Date.now() - lastPacketTime;

                    if (isPlaying && staleDuration > 1000) {{
                        document.getElementById('reconnectOverlay').classList.add('visible');
                        updateStatus('connecting', 'Reconnecting...');
                    }}

                    if (isPlaying && staleDuration > 2000) {{
                        debugLog('Stream stale - no data for 2s', 'warn');
                        clearInterval(httpWatchdog);
                        httpWatchdog = null;
                        if (httpStreamController) {{
                            httpStreamController.abort();
                        }}
                        handleStreamDisconnect();
                    }}
                }}, 500);

                const reader = response.body.getReader();
                httpStreamReader = reader;
                let buffer = new Uint8Array(0);

                while (isPlaying) {{
                    const {{ done, value }} = await reader.read();
                    if (done) {{
                        debugLog('HTTP stream ended', 'warn');
                        break;
                    }}

                    lastPacketTime = Date.now();

                    const newBuffer = new Uint8Array(buffer.length + value.length);
                    newBuffer.set(buffer);
                    newBuffer.set(value, buffer.length);
                    buffer = newBuffer;

                    while (buffer.length >= 16) {{
                        const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.length);
                        const frameCount = view.getUint16(14, true);
                        const channels = view.getUint16(12, true);
                        const packetSize = 16 + (frameCount * channels * 4);

                        if (buffer.length >= packetSize) {{
                            const packetData = new ArrayBuffer(packetSize);
                            new Uint8Array(packetData).set(buffer.subarray(0, packetSize));
                            handleAudioPacket(packetData);
                            buffer = buffer.slice(packetSize);
                        }} else {{
                            break;
                        }}
                    }}
                }}

                handleStreamDisconnect();

            }} catch (err) {{
                if (err.name === 'AbortError') {{
                    debugLog('HTTP stream aborted', 'info');
                    return;
                }}
                debugLog('HTTP stream error: ' + err.message, 'error');
                handleStreamDisconnect();
            }}
        }}

        function handleStreamDisconnect() {{
            if (httpWatchdog) {{
                clearInterval(httpWatchdog);
                httpWatchdog = null;
            }}

            if (isPlaying) {{
                reconnectAttempts++;
                if (reconnectAttempts <= 2) {{
                    debugLog('Reconnect ' + reconnectAttempts + '/2...', 'info');
                    document.getElementById('reconnectOverlay').classList.add('visible');
                    updateStatus('connecting', 'Reconnecting...');
                    setTimeout(connectHTTPStream, 1000);
                }} else {{
                    debugLog('No connection found', 'warn');
                    document.getElementById('reconnectOverlay').classList.remove('visible');
                    updateSubtitle(false, 'No connection found. Please check computer.');
                    stopAudio();
                }}
            }}
        }}

        function handleAudioPacket(data) {{
            packetsReceived++;

            if (packetsReceived === 1) {{
                debugLog('First packet received! Size: ' + data.byteLength + ' bytes');
            }}

            const view = new DataView(data);
            const sequence = view.getUint32(0, true);
            const timestamp = view.getUint32(4, true);
            const packetSampleRate = view.getUint32(8, true);
            const channels = view.getUint16(12, true);
            const frameCount = view.getUint16(14, true);

            if (!sourceRateSet && packetSampleRate > 0) {{
                sourceRate = packetSampleRate;
                sourceRateSet = true;
                resampleRatio = outputRate / sourceRate;
                debugLog('Source rate set from packet: ' + sourceRate + 'Hz, Ratio: ' + resampleRatio.toFixed(4));
                document.getElementById('sampleRate').textContent = outputRate + 'Hz (src:' + sourceRate + ')';

            }}

            if (packetsReceived === 1) {{
                debugLog('Packet header: seq=' + sequence + ', rate=' + packetSampleRate + ', ch=' + channels + ', frames=' + frameCount);
            }}

            const audioData = new Float32Array(data, 16);
            const inputFrames = audioData.length / 2;

            if (packetsReceived === 1) {{
                debugLog('Audio samples: ' + audioData.length + ' (' + inputFrames + ' frames)');
                debugLog('First samples: ' + audioData.slice(0, 8).map(x => x.toFixed(4)).join(', '));
            }}

            let samplesToWrite;
            if (Math.abs(resampleRatio - 1.0) > 0.001) {{
                const outputFrames = Math.floor(inputFrames * resampleRatio);
                samplesToWrite = outputFrames * 2;

                // Overflow protection: advance readPos to discard oldest data
                const spaceAvailable = BUFFER_SIZE - bufferedSamples;
                if (samplesToWrite > spaceAvailable) {{
                    const overflow = samplesToWrite - spaceAvailable;
                    readPos = (readPos + overflow) % BUFFER_SIZE;
                    bufferedSamples -= overflow;
                }}

                for (let outFrame = 0; outFrame < outputFrames; outFrame++) {{
                    const inFrameF = outFrame / resampleRatio;
                    const inFrame0 = Math.floor(inFrameF);
                    const inFrame1 = Math.min(inFrame0 + 1, inputFrames - 1);
                    const frac = inFrameF - inFrame0;

                    const l0 = audioData[inFrame0 * 2];
                    const l1 = audioData[inFrame1 * 2];
                    const left = l0 + (l1 - l0) * frac;

                    const r0 = audioData[inFrame0 * 2 + 1];
                    const r1 = audioData[inFrame1 * 2 + 1];
                    const right = r0 + (r1 - r0) * frac;

                    audioBuffer[writePos] = left;
                    writePos = (writePos + 1) % BUFFER_SIZE;
                    audioBuffer[writePos] = right;
                    writePos = (writePos + 1) % BUFFER_SIZE;
                }}

                bufferedSamples += samplesToWrite;
            }} else {{
                samplesToWrite = audioData.length;

                // Overflow protection: advance readPos to discard oldest data
                const spaceAvailable = BUFFER_SIZE - bufferedSamples;
                if (samplesToWrite > spaceAvailable) {{
                    const overflow = samplesToWrite - spaceAvailable;
                    readPos = (readPos + overflow) % BUFFER_SIZE;
                    bufferedSamples -= overflow;
                }}

                for (let i = 0; i < audioData.length; i++) {{
                    audioBuffer[writePos] = audioData[i];
                    writePos = (writePos + 1) % BUFFER_SIZE;
                }}
                bufferedSamples += samplesToWrite;
            }}

            if (packetsReceived % 50 === 0) {{
                const bufferMs = Math.round((bufferedSamples / 2) / outputRate * 1000);
                const bars = document.getElementById('signalBars');
                if (bufferMs > 60) {{
                    bars.className = 'signal-bars good';
                }} else if (bufferMs < 20) {{
                    bars.className = 'signal-bars poor';
                }} else {{
                    bars.className = 'signal-bars fair';
                }}
            }}

            const leftChannel = new Float32Array(audioData.length / 2);
            for (let i = 0; i < leftChannel.length; i++) {{
                leftChannel[i] = audioData[i * 2];
            }}
            updateVisualizer(leftChannel);
        }}

        let underrunCount = 0;

        function processAudio(e) {{
            const outputL = e.outputBuffer.getChannelData(0);
            const outputR = e.outputBuffer.getChannelData(1);
            const frameCount = outputL.length;

            const samplesNeeded = frameCount * 2;

            const currentThreshold = isInitialStart ? prebufferSamples : rebufferSamples;

            if (isPrebuffering) {{
                if (bufferedSamples < currentThreshold) {{
                    for (let i = 0; i < frameCount; i++) {{
                        outputL[i] = 0;
                        outputR[i] = 0;
                    }}
                    if (packetsReceived > 0 && packetsReceived % 200 === 0) {{
                        const pct = Math.round((bufferedSamples / currentThreshold) * 100);
                        const mode = isInitialStart ? 'Starting' : 'Rebuffering';
                        debugLog(mode + ': ' + pct + '% (' + Math.round(bufferedSamples/2/outputRate*1000) + 'ms)');
                    }}
                    return;
                }} else {{
                    isPrebuffering = false;
                    isInitialStart = false;
                    debugLog('Playback started with ' + Math.round(bufferedSamples/2/outputRate*1000) + 'ms buffer', 'info');
                }}
            }}

            if (bufferedSamples < samplesNeeded) {{
                underrunCount++;
                isPrebuffering = true;
                debugLog('Buffer underrun #' + underrunCount + ', need ' + samplesNeeded + ', have ' + bufferedSamples + ' - rebuffering...', 'warn');
                for (let i = 0; i < frameCount; i++) {{
                    outputL[i] = 0;
                    outputR[i] = 0;
                }}
                return;
            }}

            for (let i = 0; i < frameCount; i++) {{
                outputL[i] = audioBuffer[readPos];
                readPos = (readPos + 1) % BUFFER_SIZE;

                outputR[i] = audioBuffer[readPos];
                readPos = (readPos + 1) % BUFFER_SIZE;
            }}

            bufferedSamples -= samplesNeeded;

            updateVisualizer(outputL);
        }}

        function setVolume(value) {{
            if (gainNode) {{
                gainNode.gain.value = value / 100;
                debugLog('Volume set to ' + value + '%');
            }}
        }}

        if ('wakeLock' in navigator) {{
            navigator.wakeLock.request('screen').catch(() => {{}});
        }}

        document.addEventListener('gesturestart', function(e) {{ e.preventDefault(); }}, {{ passive: false }});
        document.addEventListener('gesturechange', function(e) {{ e.preventDefault(); }}, {{ passive: false }});
        document.addEventListener('gestureend', function(e) {{ e.preventDefault(); }}, {{ passive: false }});

        let lastTouchEnd = 0;
        document.addEventListener('touchend', function(e) {{
            const now = Date.now();
            if (now - lastTouchEnd <= 300) {{ e.preventDefault(); }}
            lastTouchEnd = now;
        }}, {{ passive: false }});

        function setupMediaSession() {{
            if ('mediaSession' in navigator) {{
                navigator.mediaSession.metadata = new MediaMetadata({{
                    title: 'Cymatics Mix Link',
                    artist: 'Streaming from PC',
                    album: 'System Audio',
                    artwork: [
                        {{ src: 'data:image/svg+xml,<svg xmlns=""http://www.w3.org/2000/svg"" viewBox=""0 0 512 512""><rect fill=""%23000"" width=""512"" height=""512""/><circle cx=""256"" cy=""256"" r=""180"" fill=""none"" stroke=""%2300d4ff"" stroke-width=""24""/><polygon points=""220,160 220,352 360,256"" fill=""%2300d4ff""/></svg>', sizes: '512x512', type: 'image/svg+xml' }}
                    ]
                }});

                navigator.mediaSession.setActionHandler('play', () => {{
                    debugLog('Media Session: play', 'info');
                    if (gainNode) gainNode.gain.value = 1;
                    navigator.mediaSession.playbackState = 'playing';
                    document.getElementById('playBtn').classList.add('playing');
                }});

                navigator.mediaSession.setActionHandler('pause', () => {{
                    debugLog('Media Session: pause', 'info');
                    if (gainNode) gainNode.gain.value = 0;
                    navigator.mediaSession.playbackState = 'paused';
                    document.getElementById('playBtn').classList.remove('playing');
                }});

                debugLog('Media Session API configured');
            }}
        }}

        function updateMediaSessionState(playing) {{
            if ('mediaSession' in navigator) {{
                navigator.mediaSession.playbackState = playing ? 'playing' : 'paused';
            }}
        }}
    </script>
</body>
</html>";
    }
}
