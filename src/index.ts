import { NitroModules } from 'react-native-nitro-modules'
import type {
  Client,
  DownloadConfig,
  DownloadResult,
} from './specs/Client.nitro'

const FetchHybridObject = NitroModules.createHybridObject<Client>('Fetch')

export function downloadFile(config: DownloadConfig): Promise<DownloadResult> {
  return FetchHybridObject.downloadFile(config)
}
