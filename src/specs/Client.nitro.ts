import type { HybridObject } from 'react-native-nitro-modules'

export interface DownloadConfig {
  fromUrl: string
  toFile: string
  resumable?: boolean
  background?: boolean
  discretionary?: boolean
  progressDivider?: number
  connectionTimeout?: number
  readTimeout?: number
  onProgress?: (bytesWritten: number, contentLength: number) => void
  begin?: (statusCode: number, contentLength: number) => void
}

export interface DownloadResult {
  statusCode: number
  bytesWritten: number
}

export interface Client extends HybridObject<{
  ios: 'swift'
  android: 'kotlin'
}> {
  readonly documentDirectoryPath: string
  downloadFile(config: DownloadConfig): Promise<DownloadResult>
}
