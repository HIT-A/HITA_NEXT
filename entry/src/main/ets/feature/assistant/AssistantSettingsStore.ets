/** Persists the assistant's optional cloud model provider and API key. */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'hitanext_assistant';
const PROVIDER_KEY: string = 'llm_provider';
const API_KEY_KEY: string = 'llm_api_key';

export enum AssistantProvider {
  DEEPSEEK = 'deepseek',
  ZHIPU = 'zhipu'
}

export class AssistantSettings {
  provider: AssistantProvider = AssistantProvider.DEEPSEEK;
  apiKey: string = '';

  hasCloudModel(): boolean {
    return this.apiKey.trim().length > 0;
  }

  static providerName(provider: AssistantProvider): string {
    return provider === AssistantProvider.ZHIPU ? '智谱 GLM' : 'DeepSeek';
  }
}

export class AssistantSettingsStore {
  private static instance: AssistantSettingsStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;

  static getInstance(): AssistantSettingsStore {
    if (AssistantSettingsStore.instance === undefined) {
      AssistantSettingsStore.instance = new AssistantSettingsStore();
    }
    return AssistantSettingsStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (e) {
      this.store = undefined;
    }
  }

  async load(): Promise<AssistantSettings> {
    const settings: AssistantSettings = new AssistantSettings();
    if (this.store === undefined) {
      return settings;
    }
    try {
      const provider: string = String(await this.store.get(PROVIDER_KEY, AssistantProvider.DEEPSEEK));
      settings.provider = provider === AssistantProvider.ZHIPU ? AssistantProvider.ZHIPU : AssistantProvider.DEEPSEEK;
      settings.apiKey = String(await this.store.get(API_KEY_KEY, ''));
    } catch (e) {
    }
    return settings;
  }

  async save(settings: AssistantSettings): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.put(PROVIDER_KEY, settings.provider.toString());
      await this.store.put(API_KEY_KEY, settings.apiKey.trim());
      await this.store.flush();
    } catch (e) {
    }
  }
}
