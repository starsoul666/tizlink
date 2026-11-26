import { AppLanguage } from '../model/Models';

export class I18n {
  static lang: AppLanguage = 'zh';

  static t(zh: string, en: string): string {
    return I18n.lang === 'en' ? en : zh;
  }
}
