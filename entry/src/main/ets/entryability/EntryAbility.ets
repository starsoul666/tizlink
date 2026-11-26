import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageService } from '../service/StorageService';
import { VpnManager } from '../service/VpnManager';

const DOMAIN: number = 0x3200;
const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'TizLink EntryAbility onCreate');
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (_e) {
      // ignore on older runtimes
    }
    AppStorage.setOrCreate('abilityContext', this.context);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'TizLink EntryAbility onWindowStageCreate');
    this.initializeAndLoad(windowStage);
  }

  private async initializeAndLoad(windowStage: window.WindowStage): Promise<void> {
    try {
      await StorageService.getInstance().init(this.context);
      await VpnManager.getInstance().init();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Init services failed: %{public}s', JSON.stringify(err));
    }

    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowBackgroundColor('#08090C');
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#08090C',
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: '#08090C',
        navigationBarContentColor: '#FFFFFF'
      });
    } catch (_e) {
      // ignore window styling failure in previewer
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err && err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load pages/Index: %{public}s', JSON.stringify(err));
      }
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'TizLink EntryAbility onDestroy');
  }
}
