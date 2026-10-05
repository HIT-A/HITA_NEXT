import { AssistantMessage, AssistantService } from './AssistantService';

/** Session-only state survives route recreation without writing conversations to disk. */
@Observed
export class AssistantConversation {
  private static instance: AssistantConversation | undefined = undefined;
  messages: AssistantMessage[] = [AssistantService.welcome()];
  sending: boolean = false;

  static getInstance(): AssistantConversation {
    if (AssistantConversation.instance === undefined) {
      AssistantConversation.instance = new AssistantConversation();
    }
    return AssistantConversation.instance;
  }
}
