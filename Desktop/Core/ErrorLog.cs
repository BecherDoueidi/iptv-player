using System.IO;

namespace IPTVPlayer.Desktop.Core;

/// <summary>
/// Appends failures to a file next to the cache.
///
/// Exists because the first crash on this machine left nothing behind but a Windows
/// Error Reporting entry saying "unhandled .NET exception" — no message, no stack, no
/// clue which action caused it. A desktop app with no log is as hard to diagnose as
/// the iOS one was, and there is no excuse for that here.
/// </summary>
public static class ErrorLog
{
    private static readonly string Directory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "IPTVPlayer");

    public static string FilePath { get; } = Path.Combine(Directory, "error.log");

    private static readonly object Gate = new();

    public static void Write(string context, Exception error)
    {
        var detail = $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}  {context}\n"
                   + $"  {error.GetType().Name}: {error.Message}\n"
                   + $"{Indent(error.StackTrace)}\n";

        if (error.InnerException is { } inner)
        {
            detail += $"  caused by {inner.GetType().Name}: {inner.Message}\n{Indent(inner.StackTrace)}\n";
        }

        Append(detail);
    }

    public static void Note(string message)
        => Append($"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}  {message}\n");

    private static void Append(string text)
    {
        lock (Gate)
        {
            try
            {
                System.IO.Directory.CreateDirectory(Directory);
                File.AppendAllText(FilePath, text);
            }
            catch (IOException)
            {
                // Logging must never itself take the app down.
            }
        }
    }

    private static string Indent(string? stackTrace)
        => string.Join('\n', (stackTrace ?? "").Split('\n').Select(line => "    " + line.TrimEnd()));
}
