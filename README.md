# react-native-client

[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Platform - Android](https://img.shields.io/badge/platform-Android-green.svg)](https://developer.android.com)
[![Platform - iOS](https://img.shields.io/badge/platform-iOS-blue.svg)](https://developer.apple.com/ios)

A high-performance native HTTP client for React Native, built with [Nitro Modules](https://nitro.margelo.com).

## Features

- **File download**
  - **Native performance** — Uses `URLSession` on iOS and `OkHttp` on Android
  - **Resumable downloads** — Pause and resume downloads with HTTP Range requests
  - **Background downloads** — Continue downloading while the app is in the background
  - **Progress tracking** — Real-time `onProgress` and `begin` callbacks
  - **Configurable timeouts** — Set connection and read timeouts independently

## Installation

```sh
npm install react-native-client react-native-nitro-modules
# or
yarn add react-native-client react-native-nitro-modules
# or
bun add react-native-client react-native-nitro-modules
```

### iOS

```sh
cd ios && pod install
```

### Android

No additional steps required — Gradle handles everything automatically.

## Usage

### Basic download

```ts
import { downloadFile, documentDirectoryPath } from 'react-native-client'

const result = await downloadFile({
  fromUrl: 'https://example.com/file.zip',
  toFile: `${documentDirectoryPath}/file.zip`,
})

console.log(`Status: ${result.statusCode}, Bytes: ${result.bytesWritten}`)
```

### Download with progress

```ts
import { downloadFile, documentDirectoryPath } from 'react-native-client'

const result = await downloadFile({
  fromUrl: 'https://example.com/large-file.zip',
  toFile: `${documentDirectoryPath}/large-file.zip`,
  begin: (statusCode, contentLength) => {
    console.log(`Download started — ${contentLength} bytes`)
  },
  onProgress: (bytesWritten, contentLength) => {
    const percent = ((bytesWritten / contentLength) * 100).toFixed(1)
    console.log(`${percent}%`)
  },
})
```

### Resumable background download

```ts
import { downloadFile, documentDirectoryPath } from 'react-native-client'

const result = await downloadFile({
  fromUrl: 'https://example.com/large-file.zip',
  toFile: `${documentDirectoryPath}/large-file.zip`,
  resumable: true,
  background: true,
  connectionTimeout: 30000,
  readTimeout: 30000,
  onProgress: (bytesWritten, contentLength) => {
    console.log(`${bytesWritten} / ${contentLength}`)
  },
})
```

## API

### `downloadFile(config: DownloadConfig): Promise<DownloadResult>`

Downloads a file from a remote URL to a local path.

### `documentDirectoryPath: string`

The app's document directory path, useful as a base path for `toFile`.

### `DownloadConfig`

| Property | Type | Required | Description |
|---|---|---|---|
| `fromUrl` | `string` | Yes | URL to download from |
| `toFile` | `string` | Yes | Local file path to save to |
| `resumable` | `boolean` | No | Enable resumable downloads via HTTP Range |
| `background` | `boolean` | No | Continue download in the background |
| `discretionary` | `boolean` | No | iOS only — marks the transfer as discretionary |
| `progressDivider` | `number` | No | Controls progress callback frequency |
| `connectionTimeout` | `number` | No | Connection timeout in milliseconds |
| `readTimeout` | `number` | No | Read timeout in milliseconds |
| `onProgress` | `(bytesWritten, contentLength) => void` | No | Called periodically with download progress |
| `begin` | `(statusCode, contentLength) => void` | No | Called when the download begins |

### `DownloadResult`

| Property | Type | Description |
|---|---|---|
| `statusCode` | `number` | HTTP status code (200, 206, etc.) |
| `bytesWritten` | `number` | Total bytes written to disk |

## Contributing

Contributions are welcome! This library is actively growing and we appreciate help from the community.

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```sh
   git clone https://github.com/<your-username>/react-native-client.git
   ```
3. Install dependencies:
   ```sh
   bun install
   ```
4. Create a branch for your changes:
   ```sh
   git checkout -b feat/my-feature
   ```

### Development

```sh
# Type check
bun run typecheck

# Lint
bun run lint

# Regenerate Nitro specs after changing .nitro.ts files
bun run specs

# Regenerate nitrogen bindings after changing Client.nitro.ts
bunx nitrogen
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
