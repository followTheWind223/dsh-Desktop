using System.Text.RegularExpressions;

namespace DSHDesktop
{
    internal static class DiagnosticText
    {
        private static readonly Regex TokenPattern = new Regex(
            @"(?i)([?&]token=)[^\s&#]+",
            RegexOptions.Compiled
        );

        public static string Redact(string value)
        {
            if (string.IsNullOrEmpty(value))
            {
                return value;
            }
            return TokenPattern.Replace(value, "$1<redacted>");
        }
    }
}
