using System.Globalization;

namespace DSHDesktop
{
    internal sealed class Localizer
    {
        private readonly bool _chinese;

        private Localizer(bool chinese)
        {
            _chinese = chinese;
        }

        public string WebViewLanguage { get { return _chinese ? "zh-CN" : "en-US"; } }

        public static Localizer FromSystem()
        {
            return new Localizer(
                CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "zh"
            );
        }

        public static Localizer Create(string configuredLanguage)
        {
            if (string.Equals(configuredLanguage, "zh-CN", System.StringComparison.OrdinalIgnoreCase) ||
                string.Equals(configuredLanguage, "zh", System.StringComparison.OrdinalIgnoreCase))
            {
                return new Localizer(true);
            }
            if (string.Equals(configuredLanguage, "en-US", System.StringComparison.OrdinalIgnoreCase) ||
                string.Equals(configuredLanguage, "en", System.StringComparison.OrdinalIgnoreCase))
            {
                return new Localizer(false);
            }
            return FromSystem();
        }

        public string Text(string chinese, string english)
        {
            return _chinese ? chinese : english;
        }
    }
}
