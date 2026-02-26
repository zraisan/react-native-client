import type { HybridObject } from 'react-native-nitro-modules'

export interface DownloadConfig {
  fromUrl: string
  toFile: string
  background?: boolean
  discretionary?: boolean
  progressDivider?: number
  connectionTimeout?: number
  readTimeout?: number
}

export interface DownloadResult {
  statusCode: number
  bytesWritten: number
}

export interface Client extends HybridObject<{
  ios: 'swift'
  android: 'kotlin'
}> {
  downloadFile(config: DownloadConfig): Promise<DownloadResult>
}
