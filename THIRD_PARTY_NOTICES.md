# Third-Party Notices

## DeepSeek Harness icon

`assets/deepseek-harness.svg` is copied from:

- Project: DeepSeek Harness
- Upstream path: `apps/web/public/favicon.svg`
- Repository: <https://github.com/deepseek-ai/deepseek-harness>
- Verified source commit used for the bundled Harness package: `dd6322d604e00eec1ba5e0c8541159906a21094a`

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

## DeepSeek Harness runtime

The installer bundles the production dependency tree for:

- Package: `@deepseek-ai/dsh` 0.1.2-alpha.3
- Repository: <https://github.com/deepseek-ai/deepseek-harness>
- Reviewed source commit: `dd6322d604e00eec1ba5e0c8541159906a21094a`
- License: MIT

The exact npm integrity and transitive dependency lock are recorded in `runtime/runtime.lock.json` and `runtime/package-lock.json`. Individual transitive packages retain their own licenses included in their installed package directories.

## Node.js

The installer bundles a private Windows runtime from Node.js v24.20.0. Node.js is distributed under the MIT license with additional third-party notices contained in the bundled `runtime/node/LICENSE` file. The archive name and SHA-256 are recorded in `runtime/runtime.lock.json`.

## Microsoft WebView2 SDK

The desktop host redistributes managed assemblies and native loader files from:

- Package: `Microsoft.Web.WebView2` 1.0.4129.50
- Source: <https://www.nuget.org/packages/Microsoft.Web.WebView2/1.0.4129.50>
- License: BSD-3-Clause

The WebView2 Runtime itself is not bundled. The installer includes Microsoft's Evergreen Bootstrapper obtained from Microsoft's official distribution URL after validating its Microsoft Authenticode signature. It is executed only when no usable installed WebView2 Runtime is detected.
