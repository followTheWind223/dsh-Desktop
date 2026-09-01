using System;
using System.IO;
using System.Web.Script.Serialization;

namespace DSHDesktop
{
    internal sealed class LauncherConfiguration
    {
        public int SchemaVersion { get; set; }
        public string HarnessDir { get; set; }
        public string DataDir { get; set; }
        public string NodePath { get; set; }
        public string Language { get; set; }
        public bool HarnessManaged { get; set; }
        public bool DataManaged { get; set; }
        public bool NodeManaged { get; set; }

        [ScriptIgnore]
        public string HarnessEntryPath { get; private set; }

        [ScriptIgnore]
        public bool HarnessEntryRequiresTsx { get; private set; }

        public static LauncherConfiguration Load(string path)
        {
            string json;
            try
            {
                json = File.ReadAllText(path);
            }
            catch (Exception exception)
            {
                throw new InvalidOperationException("Unable to read launcher.config.json.", exception);
            }

            try
            {
                LauncherConfiguration configuration = new JavaScriptSerializer()
                    .Deserialize<LauncherConfiguration>(json);
                if (configuration == null)
                {
                    throw new InvalidOperationException("launcher.config.json is empty.");
                }
                return configuration;
            }
            catch (Exception exception)
            {
                throw new InvalidOperationException("launcher.config.json is not valid JSON.", exception);
            }
        }

        public void Validate(Localizer localizer)
        {
            if (SchemaVersion != 2)
            {
                throw new InvalidOperationException(localizer.Text(
                    "启动配置版本不受支持，请重新运行安装程序。",
                    "The launcher configuration version is unsupported. Run the installer again."
                ));
            }

            HarnessDir = RequireAbsolutePath(HarnessDir, "HarnessDir", true, localizer);
            DataDir = RequireAbsolutePath(DataDir, "DataDir", true, localizer);
            NodePath = RequireAbsolutePath(NodePath, "NodePath", false, localizer);

            if (!string.Equals(Path.GetFileName(NodePath), "node.exe", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(localizer.Text(
                    "配置的 NodePath 必须指向 node.exe。",
                    "The configured NodePath must point to node.exe."
                ));
            }

            string packagedEntry = Path.Combine(
                HarnessDir,
                "node_modules",
                "@deepseek-ai",
                "dsh",
                "lib",
                "bin.js"
            );
            string sourceEntry = Path.Combine(HarnessDir, "apps", "cli", "src", "bin.ts");
            if (File.Exists(packagedEntry))
            {
                HarnessEntryPath = packagedEntry;
                HarnessEntryRequiresTsx = false;
                return;
            }

            string[] requiredHarnessPaths =
            {
                sourceEntry,
                Path.Combine(HarnessDir, "apps", "web", "dist", "index.html"),
                Path.Combine(HarnessDir, "node_modules", "tsx", "package.json")
            };
            foreach (string requiredPath in requiredHarnessPaths)
            {
                if (!File.Exists(requiredPath) && !Directory.Exists(requiredPath))
                {
                    throw new InvalidOperationException(localizer.Text(
                        "DeepSeek Harness 尚未完成构建：" + requiredPath,
                        "DeepSeek Harness is not fully built: " + requiredPath
                    ));
                }
            }
            HarnessEntryPath = sourceEntry;
            HarnessEntryRequiresTsx = true;
        }

        private static string RequireAbsolutePath(
            string value,
            string name,
            bool directory,
            Localizer localizer)
        {
            if (string.IsNullOrWhiteSpace(value) || !Path.IsPathRooted(value))
            {
                throw new InvalidOperationException(localizer.Text(
                    "配置项 " + name + " 必须是绝对路径。",
                    "Configuration value " + name + " must be an absolute path."
                ));
            }

            string fullPath = Path.GetFullPath(value);
            bool exists = directory ? Directory.Exists(fullPath) : File.Exists(fullPath);
            if (!exists)
            {
                throw new InvalidOperationException(localizer.Text(
                    "配置路径不存在：" + fullPath,
                    "A configured path does not exist: " + fullPath
                ));
            }
            return fullPath;
        }
    }
}
