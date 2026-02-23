using System.Drawing;
using System.Drawing.Drawing2D;
using System.ComponentModel;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;

namespace MixLink.App;

internal static class MixLinkTheme
{
    public static readonly Color Background = Color.FromArgb(20, 20, 20); // #141414
    public static readonly Color Cyan = Color.FromArgb(0, 212, 255); // #00D4FF
    public static readonly Color Teal = Color.FromArgb(0, 255, 212); // #00FFD4

    public static readonly Color White15 = Color.FromArgb(38, 255, 255, 255); // 0.15
    public static readonly Color White25 = Color.FromArgb(64, 255, 255, 255); // 0.25
    public static readonly Color White04 = Color.FromArgb(10, 255, 255, 255); // 0.04
    public static readonly Color White03 = Color.FromArgb(8, 255, 255, 255); // 0.03

    public static readonly Color GrayText = Color.FromArgb(136, 136, 136); // #888
    public static readonly Color DangerRed = Color.FromArgb(204, 239, 68, 68); // ~red 0.8

    public static LinearGradientBrush CreateCyanTealGradient(Rectangle bounds, LinearGradientMode mode)
        => new(bounds, Cyan, Teal, mode);
}

internal static class MixLinkPaint
{
    public static GraphicsPath RoundedRect(RectangleF rect, float radius)
    {
        var path = new GraphicsPath();
        if (radius <= 0.01f)
        {
            path.AddRectangle(rect);
            path.CloseFigure();
            return path;
        }

        var d = radius * 2f;
        path.AddArc(rect.X, rect.Y, d, d, 180, 90);
        path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
        path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
        path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
        path.CloseFigure();
        return path;
    }

    public static void FillRoundedRect(Graphics g, Brush brush, RectangleF rect, float radius)
    {
        using var path = RoundedRect(rect, radius);
        g.FillPath(brush, path);
    }

    public static void StrokeRoundedRect(Graphics g, Pen pen, RectangleF rect, float radius)
    {
        using var path = RoundedRect(rect, radius);
        g.DrawPath(pen, path);
    }
}

/// <summary>
/// Minimal SVG path parser (M/L/H/V/C/Z) sufficient for the CymaticsWordmark SVG.
/// </summary>
internal static class SvgPath
{
    public static GraphicsPath Parse(string d)
    {
        var p = new GraphicsPath();
        var s = new Scanner(d);
        char cmd = '\0';
        PointF cur = new(0, 0);
        PointF start = new(0, 0);

        while (s.SkipSeparators())
        {
            var c = s.PeekChar();
            if (c is >= 'A' and <= 'Z' or >= 'a' and <= 'z')
            {
                cmd = s.ReadChar();
            }
            else if (cmd == '\0')
            {
                // Invalid path
                break;
            }

            bool rel = char.IsLower(cmd);
            switch (char.ToUpperInvariant(cmd))
            {
                case 'M':
                {
                    var x = s.ReadFloat();
                    var y = s.ReadFloat();
                    cur = rel ? new(cur.X + x, cur.Y + y) : new(x, y);
                    start = cur;

                    // Subsequent pairs are treated as implicit lineTos
                    while (s.TryReadFloat(out var nx) && s.TryReadFloat(out var ny))
                    {
                        var next = rel ? new PointF(cur.X + nx, cur.Y + ny) : new PointF(nx, ny);
                        p.AddLine(cur, next);
                        cur = next;
                    }
                    break;
                }
                case 'L':
                {
                    while (s.TryReadFloat(out var x) && s.TryReadFloat(out var y))
                    {
                        var next = rel ? new PointF(cur.X + x, cur.Y + y) : new PointF(x, y);
                        p.AddLine(cur, next);
                        cur = next;
                    }
                    break;
                }
                case 'H':
                {
                    while (s.TryReadFloat(out var x))
                    {
                        var nx = rel ? cur.X + x : x;
                        var next = new PointF(nx, cur.Y);
                        p.AddLine(cur, next);
                        cur = next;
                    }
                    break;
                }
                case 'V':
                {
                    while (s.TryReadFloat(out var y))
                    {
                        var ny = rel ? cur.Y + y : y;
                        var next = new PointF(cur.X, ny);
                        p.AddLine(cur, next);
                        cur = next;
                    }
                    break;
                }
                case 'C':
                {
                    while (s.TryReadFloat(out var x1) && s.TryReadFloat(out var y1) &&
                           s.TryReadFloat(out var x2) && s.TryReadFloat(out var y2) &&
                           s.TryReadFloat(out var x) && s.TryReadFloat(out var y))
                    {
                        var c1 = rel ? new PointF(cur.X + x1, cur.Y + y1) : new PointF(x1, y1);
                        var c2 = rel ? new PointF(cur.X + x2, cur.Y + y2) : new PointF(x2, y2);
                        var end = rel ? new PointF(cur.X + x, cur.Y + y) : new PointF(x, y);
                        p.AddBezier(cur, c1, c2, end);
                        cur = end;
                    }
                    break;
                }
                case 'Z':
                {
                    p.CloseFigure();
                    cur = start;
                    break;
                }
                default:
                    // Unsupported command; stop parsing.
                    return p;
            }
        }

        return p;
    }

    private sealed class Scanner
    {
        private readonly string _s;
        private int _i;
        public Scanner(string s) => _s = s;

        public bool SkipSeparators()
        {
            while (_i < _s.Length)
            {
                char c = _s[_i];
                if (char.IsWhiteSpace(c) || c == ',') { _i++; continue; }
                return true;
            }
            return false;
        }

        public char PeekChar() => _i < _s.Length ? _s[_i] : '\0';

        public char ReadChar() => _i < _s.Length ? _s[_i++] : '\0';

        public float ReadFloat()
        {
            if (!TryReadFloat(out var v)) throw new FormatException("Expected float");
            return v;
        }

        public bool TryReadFloat(out float value)
        {
            value = 0;
            SkipSeparators();
            if (_i >= _s.Length) return false;

            int start = _i;
            bool hasDot = false;
            bool hasExp = false;

            if (_s[_i] is '+' or '-') _i++;

            while (_i < _s.Length)
            {
                char c = _s[_i];
                if (char.IsDigit(c)) { _i++; continue; }
                if (c == '.' && !hasDot) { hasDot = true; _i++; continue; }
                if ((c == 'e' || c == 'E') && !hasExp)
                {
                    hasExp = true;
                    _i++;
                    if (_i < _s.Length && (_s[_i] is '+' or '-')) _i++;
                    continue;
                }
                break;
            }

            if (_i == start) return false;
            var token = _s.Substring(start, _i - start);
            return float.TryParse(token, NumberStyles.Float, CultureInfo.InvariantCulture, out value);
        }
    }
}

internal static class CymaticsWordmark
{
    // Extracted from macOS `CymaticsWordmark.svg` (paths only).
    private static readonly string[] Paths =
    [
        "M5.99133 6.81148C5.89922 6.58331 5.77665 6.37951 5.62333 6.20051C5.47 6.02181 5.29521 5.87022 5.09953 5.74562C4.90342 5.62131 4.69121 5.52673 4.46289 5.46189C4.23457 5.39735 4.00104 5.36471 3.76257 5.36471C3.41835 5.36471 3.09532 5.42955 2.79389 5.55908C2.49233 5.68861 2.22905 5.8666 2.00407 6.09332C1.77909 6.32004 1.60097 6.58839 1.46984 6.89837C1.33871 7.20864 1.27314 7.54256 1.27314 7.90041C1.27314 8.25826 1.33871 8.59144 1.46984 8.89983C1.60082 9.20836 1.77909 9.47599 2.00407 9.70242C2.22905 9.92928 2.49233 10.1071 2.79389 10.2367C3.09532 10.3662 3.41835 10.4309 3.76257 10.4309C4.00104 10.4309 4.2337 10.3994 4.46028 10.3364C4.68685 10.2734 4.8982 10.1805 5.09417 10.0578C5.29014 9.93494 5.46493 9.78423 5.6181 9.60552C5.77143 9.42652 5.894 9.22272 5.98611 8.99455H7.29479C7.18223 9.40346 7.00424 9.76552 6.76055 10.0809C6.51672 10.3961 6.23401 10.6611 5.9117 10.8758C5.58982 11.0904 5.24314 11.2533 4.87165 11.364C4.50017 11.4747 4.13043 11.5301 3.76228 11.5301C3.41473 11.5301 3.08067 11.4875 2.76039 11.4023C2.44011 11.3172 2.14115 11.1953 1.86337 11.0369C1.58545 10.8784 1.3316 10.6892 1.10154 10.4695C0.871632 10.2496 0.675664 10.0051 0.513638 9.73578C0.351902 9.4667 0.22556 9.17688 0.135481 8.86676C0.0451119 8.55678 0 8.23302 0 7.89562C0 7.55822 0.0449669 7.23431 0.135481 6.92433C0.22556 6.61421 0.351902 6.32468 0.513638 6.05531C0.675519 5.78624 0.871632 5.54167 1.10154 5.32177C1.3316 5.10187 1.58545 4.91359 1.86337 4.75678C2.14115 4.60013 2.44011 4.47901 2.76039 4.39386C3.08067 4.30871 3.41473 4.26607 3.76228 4.26607C4.13043 4.26607 4.50017 4.31959 4.87165 4.42693C5.24299 4.53427 5.58982 4.6947 5.9117 4.90735C6.23401 5.12044 6.51672 5.38632 6.76055 5.70486C7.00424 6.02355 7.18208 6.39416 7.29479 6.81685L5.99133 6.81148Z",
        "M16.6684 4.42937L13.9281 8.73372V11.3818H12.6553V8.7388L9.91534 4.42937H11.403L13.2842 7.57328H13.2995L15.1756 4.42937H16.6684Z",
        "M45.859 10.0583H42.6537L42.1067 11.3823H40.7624L43.6558 4.42479H44.862L47.7554 11.3823H46.4057L45.859 10.0583ZM43.1037 8.96427H45.404L44.2998 6.28047L44.259 6.10162H44.254L44.2129 6.28047L43.1037 8.96427Z",
        "M51.4648 5.52845H49.3994V4.42937H54.8082V5.52845H52.7377V11.3818H51.465L51.4648 5.52845Z",
        "M57.9703 4.42937H59.2432V11.3818H57.9703V4.42937Z",
        "M68.6423 6.81148C68.5503 6.58331 68.4277 6.37951 68.2744 6.20051C68.1209 6.02181 67.9463 5.87022 67.7503 5.74562C67.5542 5.62131 67.3421 5.52673 67.114 5.46189C66.8854 5.39735 66.6521 5.36471 66.4133 5.36471C66.0693 5.36471 65.7464 5.42955 65.4447 5.55908C65.1432 5.68861 64.8801 5.8666 64.6549 6.09332C64.43 6.31989 64.252 6.58839 64.1208 6.89837C63.9896 7.20864 63.9239 7.54256 63.9239 7.90041C63.9239 8.25826 63.9896 8.59144 64.1208 8.89983C64.2519 9.20836 64.43 9.47599 64.6549 9.70242C64.8801 9.92928 65.1432 10.1071 65.4447 10.2367C65.7464 10.3662 66.0693 10.4309 66.4133 10.4309C66.652 10.4309 66.8845 10.3994 67.1112 10.3364C67.3378 10.2734 67.549 10.1805 67.7451 10.0578C67.9412 9.93494 68.1159 9.78423 68.269 9.60552C68.4225 9.42652 68.5451 9.22272 68.637 8.99455H69.9457C69.8333 9.40346 69.655 9.76552 69.4115 10.0809C69.1676 10.3961 68.8849 10.6611 68.5628 10.8758C68.2406 11.0904 67.8939 11.2533 67.5224 11.364C67.1511 11.4747 66.7813 11.5301 66.4131 11.5301C66.0657 11.5301 65.7317 11.4875 65.4113 11.4023C65.0909 11.3172 64.7919 11.1953 64.514 11.0369C64.2364 10.8784 63.9824 10.6892 63.7525 10.4695C63.5224 10.2496 63.3264 10.0051 63.1646 9.73578C63.0025 9.4667 62.8765 9.17688 62.7861 8.86676C62.6959 8.55678 62.6506 8.23302 62.6506 7.89562C62.6506 7.55822 62.6957 7.23431 62.7861 6.92433C62.8765 6.61421 63.0025 6.32468 63.1646 6.05531C63.3263 5.78624 63.5224 5.54167 63.7525 5.32177C63.9824 5.10187 64.2364 4.91359 64.514 4.75678C64.7919 4.60013 65.0909 4.47901 65.4113 4.39386C65.7317 4.30871 66.0657 4.26607 66.4131 4.26607C66.7813 4.26607 67.1511 4.31959 67.5224 4.42693C67.8939 4.53427 68.2406 4.6947 68.5628 4.90735C68.8849 5.12044 69.1676 5.38632 69.4115 5.70486C69.655 6.02355 69.8331 6.39416 69.9457 6.81685L68.6423 6.81148Z",
        "M74.2889 9.29104C74.2889 9.45133 74.3263 9.60117 74.4013 9.741C74.4762 9.88069 74.5818 10.0025 74.7181 10.1064C74.8545 10.2104 75.0181 10.2922 75.2091 10.3517C75.3997 10.4113 75.6111 10.4412 75.8429 10.4412C76.3951 10.4412 76.8004 10.3534 77.0596 10.1779C77.3185 10.0024 77.4482 9.75275 77.4482 9.42899C77.4482 9.23157 77.4038 9.07027 77.315 8.94596C77.2267 8.82165 77.1011 8.71677 76.9393 8.63163C76.7776 8.54648 76.5842 8.47482 76.3591 8.41694C76.1343 8.35907 75.8872 8.2993 75.6182 8.23809C75.4715 8.20734 75.3121 8.17412 75.1401 8.13829C74.968 8.10261 74.7941 8.05576 74.6187 7.99774C74.4431 7.93971 74.2734 7.86907 74.1099 7.78552C73.9464 7.70212 73.8022 7.59811 73.6781 7.47366C73.5536 7.34934 73.4532 7.20284 73.3765 7.03414C73.2998 6.86544 73.2615 6.66527 73.2615 6.43347C73.2615 6.11638 73.3125 5.82511 73.4149 5.55937C73.5171 5.29349 73.6788 5.06532 73.9004 4.87428C74.1219 4.68353 74.4067 4.53427 74.7541 4.42693C75.1019 4.31959 75.521 4.26607 76.012 4.26607C76.4035 4.26607 76.7523 4.31625 77.0573 4.41678C77.3622 4.5173 77.6204 4.6596 77.8317 4.84367C78.043 5.0276 78.2039 5.24823 78.3147 5.50541C78.4256 5.76288 78.481 6.0482 78.481 6.36181H77.203C77.203 6.22213 77.1758 6.09245 77.1212 5.97307C77.0667 5.85398 76.9857 5.75012 76.8784 5.66134C76.7711 5.57272 76.6356 5.50266 76.472 5.45174C76.3083 5.40068 76.1174 5.37501 75.8996 5.37501C75.6302 5.37501 75.4077 5.40242 75.2323 5.45696C75.0567 5.5115 74.917 5.58214 74.813 5.66918C74.709 5.75621 74.6367 5.85572 74.5957 5.96813C74.5549 6.08055 74.5345 6.19471 74.5345 6.31061C74.5345 6.46408 74.577 6.59448 74.6623 6.70168C74.7474 6.80902 74.8649 6.89938 75.015 6.97264C75.1649 7.04603 75.3428 7.10652 75.5493 7.15424C75.7554 7.20182 75.9812 7.24273 76.2265 7.27682C76.5571 7.34847 76.8742 7.43115 77.1774 7.52486C77.4808 7.61856 77.7477 7.74476 77.9775 7.90302C78.2075 8.06142 78.3916 8.26261 78.5297 8.50615C78.6676 8.74984 78.7368 9.0575 78.7368 9.42884C78.7368 9.76624 78.6663 10.0664 78.5246 10.3286C78.3832 10.591 78.1848 10.8116 77.9292 10.9905C77.6736 11.1694 77.3668 11.3057 77.0089 11.3994C76.6511 11.4931 76.2542 11.54 75.8179 11.54C75.3372 11.54 74.9207 11.4737 74.568 11.3407C74.2152 11.2078 73.9241 11.0349 73.6937 10.8218C73.4637 10.6089 73.2934 10.3685 73.1827 10.101C73.072 9.8334 73.0168 9.56331 73.0168 9.29075L74.2889 9.29104Z",
        "M38.4953 11.0722C36.8449 11.0722 36.2011 9.10434 35.5709 7.20456C35.0131 5.50424 34.4827 3.89921 33.2131 3.89921C32.1567 3.89921 31.4676 5.01453 30.7965 6.09374C30.1844 7.08214 29.5541 8.10231 28.7199 8.10231C27.4504 8.10231 27.0151 6.0801 26.5979 4.12143C26.1673 2.09473 25.7183 0 24.2357 0C22.8483 0 22.0685 2.24892 21.1662 4.85149C20.1552 7.78043 19.0035 11.0994 16.8816 11.0994C16.7637 11.0949 16.6685 11.1946 16.6685 11.3125C16.6685 11.4304 16.7637 11.5301 16.8861 11.5301C18.6136 11.5301 19.9647 10.9996 21.1572 10.5325C22.1955 10.1245 23.1749 9.7436 24.2676 9.7436C25.8046 9.7436 26.6343 10.1426 27.4369 10.5281C28.1035 10.8454 28.7337 11.1492 29.6677 11.1492C30.7197 11.1492 31.2772 10.9225 31.7716 10.723C32.2069 10.5462 32.5877 10.3965 33.2542 10.3965C33.8845 10.3965 34.4013 10.5914 35.0089 10.8182C35.8296 11.1265 36.8452 11.5073 38.4911 11.5073C38.609 11.5073 38.7087 11.4122 38.7087 11.2897C38.7087 11.1673 38.6135 11.0722 38.4911 11.0722M29.0373 9.40809C30.1119 9.40809 30.7648 8.56474 31.395 7.75316C31.9528 7.03224 32.4741 6.35672 33.2268 6.35672C34.0565 6.35672 34.5371 7.318 35.0903 8.43332C35.3307 8.91389 35.58 9.41273 35.8747 9.86602C35.6934 9.68006 35.5256 9.48975 35.3579 9.2993C34.7413 8.601 34.1564 7.93912 33.2451 7.93912C32.3337 7.93912 31.8395 8.42433 31.3182 8.89126C30.7741 9.38096 30.2617 9.8434 29.3548 9.8434C28.4027 9.8434 27.8904 9.11348 27.3009 8.27013C26.6253 7.30436 25.859 6.20717 24.2585 6.20717C22.998 6.20717 22.0413 7.29087 21.0257 8.43332C20.6494 8.85949 20.264 9.28566 19.8604 9.67571C20.4726 8.84151 20.9894 7.82583 21.4791 6.8692C22.3542 5.15538 23.1794 3.53672 24.2449 3.53672C25.4873 3.53672 25.9949 4.93316 26.539 6.40676C27.0786 7.88037 27.6362 9.40823 29.0418 9.40823M28.7199 8.53762C29.79 8.53762 30.4881 7.41315 31.1638 6.32495C31.7714 5.34555 32.3971 4.33452 33.2131 4.33452C34.1698 4.33452 34.6505 5.79449 35.1582 7.34063C35.2443 7.59911 35.3305 7.8621 35.4212 8.12508C34.8499 6.97799 34.2877 5.92156 33.2266 5.92156C32.2609 5.92156 31.6442 6.71501 31.0502 7.48583C30.4562 8.25215 29.8986 8.97292 29.0372 8.97292C28.5475 8.97292 28.1848 8.70095 27.8809 8.28827C28.1213 8.44696 28.3979 8.53762 28.7199 8.53762ZM21.5788 4.99205C22.3903 2.64797 23.1567 0.435308 24.2357 0.435308C25.3692 0.435308 25.7774 2.35772 26.1763 4.21224C26.2035 4.33916 26.2307 4.47072 26.2579 4.59765C25.8091 3.74066 25.2196 3.10141 24.2449 3.10141C22.9118 3.10141 22.0277 4.83336 21.0937 6.66975C20.9486 6.95086 20.8036 7.24097 20.6494 7.52673C20.9849 6.70601 21.2885 5.8354 21.5788 4.99205ZM33.2584 9.95683C32.5012 9.95683 32.0478 10.1381 31.6126 10.315C31.132 10.5099 30.6378 10.7094 29.6676 10.7094C28.8334 10.7094 28.2711 10.4419 27.6227 10.129C26.8157 9.7436 25.8998 9.30379 24.2675 9.30379C23.0931 9.30379 22.0776 9.70284 20.9984 10.1245C20.4317 10.3467 19.8513 10.5733 19.2302 10.7503C20.0373 10.1972 20.7128 9.43086 21.3475 8.71908C22.2952 7.64901 23.1884 6.63798 24.2539 6.63798C25.6277 6.63798 26.2942 7.59012 26.9426 8.51513C27.5502 9.38111 28.1758 10.2744 29.3547 10.2744C30.4248 10.2744 31.055 9.71212 31.6081 9.21342C32.1115 8.75998 32.5421 8.37008 33.2449 8.37008C33.9477 8.37008 34.46 8.93231 35.0359 9.5852C35.385 9.98424 35.7794 10.4194 36.2783 10.7822C35.8658 10.6689 35.5075 10.5373 35.1675 10.4059C34.5236 10.1656 33.9705 9.95712 33.2632 9.95712",
    ];

    private static readonly GraphicsPath[] Parsed = Paths.Select(SvgPath.Parse).ToArray();

    public static void Draw(Graphics g, RectangleF bounds, Color color)
    {
        // SVG viewBox is 0..79 x 0..12 (from file header)
        const float vbW = 79f;
        const float vbH = 12f;

        var sx = bounds.Width / vbW;
        var sy = bounds.Height / vbH;
        var s = Math.Min(sx, sy);
        var w = vbW * s;
        var h = vbH * s;
        var ox = bounds.X + (bounds.Width - w) / 2f;
        var oy = bounds.Y + (bounds.Height - h) / 2f;

        using var brush = new SolidBrush(color);
        using var m = new Matrix();
        m.Translate(ox, oy);
        m.Scale(s, s);

        foreach (var path in Parsed)
        {
            using var p = (GraphicsPath)path.Clone();
            p.Transform(m);
            g.FillPath(brush, p);
        }
    }
}

internal sealed class MixLinkButton : Button
{
    [Browsable(false)]
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public bool UseDangerStyle { get; set; }

    public MixLinkButton()
    {
        FlatStyle = FlatStyle.Flat;
        FlatAppearance.BorderSize = 0;
        BackColor = Color.Transparent;
        ForeColor = Color.Black;
        Cursor = Cursors.Hand;
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);

        var rect = ClientRectangle;
        rect.Inflate(-1, -1);
        var radius = 10f;

        if (UseDangerStyle)
        {
            using var b = new SolidBrush(MixLinkTheme.DangerRed);
            MixLinkPaint.FillRoundedRect(e.Graphics, b, rect, radius);
        }
        else
        {
            using var grad = MixLinkTheme.CreateCyanTealGradient(rect, LinearGradientMode.Horizontal);
            MixLinkPaint.FillRoundedRect(e.Graphics, grad, rect, radius);
        }

        if (!Enabled)
        {
            using var overlay = new SolidBrush(Color.FromArgb(120, 0, 0, 0));
            MixLinkPaint.FillRoundedRect(e.Graphics, overlay, rect, radius);
        }

        var textColor = UseDangerStyle ? Color.White : Color.Black;
        TextRenderer.DrawText(
            e.Graphics,
            Text,
            Font,
            rect,
            Enabled ? textColor : Color.FromArgb(180, textColor),
            TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis
        );
    }
}

internal enum TrafficLightKind
{
    Close,
    Minimize
}

internal sealed class TrafficLightButton : Control
{
    public TrafficLightKind Kind { get; }
    [Browsable(false)]
    [DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
    public bool ShowGlyphOnHover { get; set; } = true;

    private bool _hover;

    public TrafficLightButton(TrafficLightKind kind)
    {
        Kind = kind;
        Size = new Size(12, 12);
        Cursor = Cursors.Hand;
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        _hover = true;
        Invalidate();
        base.OnMouseEnter(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        _hover = false;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);

        Color fill = Kind == TrafficLightKind.Close
            ? Color.FromArgb(255, 97, 87)
            : Color.FromArgb(255, 189, 43);

        using var b = new SolidBrush(fill);
        e.Graphics.FillEllipse(b, 0, 0, Width - 1, Height - 1);

        if (!ShowGlyphOnHover || !_hover) return;

        if (Kind == TrafficLightKind.Close)
        {
            using var pen = new Pen(Color.FromArgb(102, 0, 0), 2f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            e.Graphics.DrawLine(pen, 3, 3, Width - 4, Height - 4);
            e.Graphics.DrawLine(pen, Width - 4, 3, 3, Height - 4);
        }
        else
        {
            using var pen = new Pen(Color.FromArgb(102, 77, 0), 2.2f) { StartCap = LineCap.Round, EndCap = LineCap.Round };
            e.Graphics.DrawLine(pen, 3, Height / 2f, Width - 4, Height / 2f);
        }
    }
}

internal sealed class HamburgerButton : Control
{
    private bool _hover;

    public HamburgerButton()
    {
        Size = new Size(28, 28);
        Cursor = Cursors.Hand;
        SetStyle(ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint, true);
    }

    protected override void OnMouseEnter(EventArgs e)
    {
        _hover = true;
        Invalidate();
        base.OnMouseEnter(e);
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        _hover = false;
        Invalidate();
        base.OnMouseLeave(e);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        e.Graphics.Clear(Parent?.BackColor ?? MixLinkTheme.Background);

        var alpha = _hover ? 217 : 102; // ~0.85 / 0.4
        using var b = new SolidBrush(Color.FromArgb(alpha, 255, 255, 255));

        float size = 18f;
        float barW = 14f;
        float barH = 2.25f;
        float cr = 1.1f;
        float xOff = (Width - barW) / 2f;
        float yOff = (Height - size) / 2f;

        foreach (float yTop in new[] { 3.375f, 7.875f, 12.375f })
        {
            float y = yOff + yTop;
            var rect = new RectangleF(xOff, y, barW, barH);
            MixLinkPaint.FillRoundedRect(e.Graphics, b, rect, cr);
        }
    }
}

