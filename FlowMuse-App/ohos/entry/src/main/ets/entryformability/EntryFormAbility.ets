import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { ServiceWidgetChannel } from '../channels/ServiceWidgetChannel';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY]?.toString();
    if (formId) {
      // 注册 formId 后异步刷新一次，使新添加的卡片立即展示当前快照。
      // onAddForm 是同步 API，Preferences 只支持异步读取，因此首次渲染会
      // 短暂显示下方默认数据，再切换至真实内容。这是已知的鸿蒙平台限制。
      void ServiceWidgetChannel.rememberFormId(this.context, formId).then(() => {
        void ServiceWidgetChannel.updateFormById(this.context, formId);
      });
    }
    return formBindingData.createFormBindingData({
      appName: 'FlowMuse',
      headline: '开始你的第一块白板',
      detail: '',
      buttonText: '立即创建',
      buttonAction: 'createNote'
    });
  }

  onUpdateForm(formId: string): void {
    void ServiceWidgetChannel.updateFormById(this.context, formId);
  }

  onRemoveForm(formId: string): void {
    void ServiceWidgetChannel.removeFormId(this.context, formId);
  }

  onAcquireFormState(want: Want) {
    return formInfo.FormState.READY;
  }
}
