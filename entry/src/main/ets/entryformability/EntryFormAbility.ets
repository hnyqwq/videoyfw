import FormPreference from '../formcommon/utils/FormPreference';
import { formBindingData, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';

export default class EntryFormAbility extends FormExtensionAbility {
  onAddForm(want: Want) {
    /**
     * This is the automatically generated code for the logic of card interactions.
     * Used to persist formId and formName.
     */
    FormPreference.persistForm(want, this.context)


    // Called to return a FormBindingData object.
    let formData = '';
    return formBindingData.createFormBindingData(formData);
  }

  onRemoveForm(formId: string) {
    /**
     * This is the automatically generated code for the logic of card interactions.
     * Remove formId and formName from persistence.
     */
    FormPreference.removePersistentForm(formId, this.context);


    // Called to notify the form provider that a specified form has been destroyed.
  }

  onAcquireFormState(want: Want) {
    // Called to return a {@link FormState} object.
    return formInfo.FormState.READY;
  }
};