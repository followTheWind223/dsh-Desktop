# Third-Party Notices

## DeepSeek Harness icon

`assets/deepseek-harness.svg` is copied from:

- Project: DeepSeek Harness
- Upstream path: `apps/web/public/favicon.svg`
- Repository: <https://github.com/deepseek-ai/deepseek-harness>
- Verified source commit used for this package: `cd5ef8148158c3a752a658978873241fdf8e2bbc`

`assets/deepseek-harness.ico` is an unmodified multi-size Windows icon conversion of that SVG. The upstream project is licensed under MIT:

```text
MIT License

Copyright (c) 2026 DeepSeek

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The upstream name and icon are used only to identify compatibility with DeepSeek Harness. This community launcher is not endorsed by DeepSeek. The MIT license does not grant trademark rights.

## Microsoft WebView2 SDK

The desktop host redistributes managed assemblies and native loader files from:

- Package: `Microsoft.Web.WebView2` 1.0.4129.50
- Source: <https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4129.50>
- License: BSD-3-Clause

The WebView2 Runtime itself is not bundled. When missing, the installer obtains Microsoft's Evergreen Bootstrapper from Microsoft's official distribution URL and verifies its Microsoft Authenticode signature before execution.
