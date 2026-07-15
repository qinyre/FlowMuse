import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { ServiceWidgetChannel } from '../channels/ServiceWidgetChannel';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY]?.toString();
    if (formId) {
      void ServiceWidgetChannel.rememberFormId(this.context, formId).then(() => {
        void ServiceWidgetChannel.updateFormById(this.context, formId);
      });
    }
    return formBindingData.createFormBindingData({
      appName: 'FlowMuse',
      headline: '开始你的第一块白板',
      detail: '最近白板',
      buttonText: '打开资料库'
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
