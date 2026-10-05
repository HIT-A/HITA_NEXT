/**
 * EasWebMfaBridge.ets — 统一认证 MFA/二次验证桥接（对应蓝本 §2.2.5 / §4.1）。
 *
 * 注入 JS 全文对齐反编译（笔记 docs/eas-page-predicate-notes.md §7/§9）：
 *  - detect：WebViewLoginActivity L1337 检测脚本（逐字）
 *  - submit：submitNativeMfaInput L4781-4793 注入体（逐字语义 + 结果 {ok,error,inputId}）
 *  - switch：switchNativeMfaMethod L4795-4825 注入体（调用 mobileChangeOtherType）
 *  - send：triggerNativeMfaSendCode L4827-4843 注入体（逐字）
 * 覆盖层状态模型对应 MfaOverlayState.java（见本文件 EasMfaOverlayState）。
 *
 * 做法 = “原生 UI 输入 → runJavaScript 填表并点击”，与平台 API 解耦 → ArkWeb 可复刻。
 */
import { webview } from '@kit.ArkWeb';

/** 覆盖层状态（对应 MfaOverlayState 字段集，语义映射见 detect()）。 */
export class EasMfaOverlayState {
  visible: boolean = false;
  /** method 文案（如 “手机号验证码”），也作覆盖层标题。 */
  promptTitle: string = '';
  /** prompt 说明文字。 */
  promptText: string = '';
  /** method 文案（原样）。 */
  verifyMethod: string = '';
  /** methodType：reAuthDecN 的数字或 reAuthType（如 "3"）。 */
  verifyMethodType: string = '';
  hasVisibleInput: boolean = false;
  inputId: string = '';
  inputType: string = 'text';
  inputPlaceholder: string = '';
  submitButtonId: string = '';
  canSendCode: boolean = false;
  switchMethodJs: string = '';
}

/** 原生动作执行结果（注入脚本返回 {ok,error,…}）。 */
export class EasMfaAction {
  ok: boolean = false;
  error: string = '';
  extra: string = '';
}

/**
 * MFA 探测脚本（Activity L1337 整段逐字；中文按解码后字面存储）。
 * 判定条件（§7.2）：pathname 正则 /\/authserver\/reAuthCheck\//i 或可见 #reAuthSubmitBtn/[id*=reAuthSubmit]
 * 或存在 #dynamicCode/input[name=dynamicCode]/input[name=otpCode]；
 * 返回 JSON：{mfa:false,ready} 或 {mfa:true, method, methodType, prompt,
 * inputs:[{id,name,type,placeholder}], submitId, canSendCode, ready}。
 */
export const MFA_DETECT_SCRIPT: string =
  '(function() {\n' +
  '  function isVisible(el) {\n' +
  "    if (!el || el.disabled) return false;\n" +
  '    var style = window.getComputedStyle(el);\n' +
  '    var rect = el.getBoundingClientRect();\n' +
  "    return style.display !== 'none' && style.visibility !== 'hidden' &&\n" +
  "      style.opacity !== '0' && rect.width > 0 && rect.height > 0;\n" +
  '  }\n' +
  '  function plainText(value) {\n' +
  "    var container = document.createElement('div');\n" +
  "    container.innerHTML = String(value || '');\n" +
  "    return String(container.textContent || container.innerText || '').trim();\n" +
  '  }\n' +
  "  var params = (typeof reAuthParams === 'object' && reAuthParams) ? reAuthParams : {};\n" +
  "  var methodBtn = document.getElementById('changeReAuthTypeButton');\n" +
  "  var submitButtons = Array.prototype.slice.call(document.querySelectorAll('#reAuthSubmitBtn, [id*=reAuthSubmit]'));\n" +
  '  var submitButton = submitButtons.find(isVisible) || null;\n' +
  "  var specificInput = document.querySelector('#dynamicCode, input[name=dynamicCode], input[name=otpCode]');\n" +
  "  var pathLooksLikeMfa = /\\/authserver\\/reAuthCheck\\//i.test(location.pathname);\n" +
  '  if (!pathLooksLikeMfa && !submitButton && !specificInput) {\n' +
  "    return JSON.stringify({mfa:false, ready:document.readyState});\n" +
  '  }\n' +
  '  var inputCandidates = Array.prototype.slice.call(document.querySelectorAll(\n' +
  "    '#dynamicCode, input[name=dynamicCode], input[name=otpCode], #password, input:not([type=hidden])'\n" +
  '  ));\n' +
  '  var visibleInput = inputCandidates.find(isVisible) || null;\n' +
  '  if (!submitButton && !visibleInput) {\n' +
  "    return JSON.stringify({mfa:false, ready:document.readyState});\n" +
  '  }\n' +
  "  var reAuthType = String(params.reAuthType || '');\n" +
  "  var methodNames = {\n" +
  "    '2':'统一身份认证密码', '7':'统一身份认证密码',\n" +
  "    '3':'手机号验证码', '4':'企业微信验证码', '5':'HIT APP 验证码',\n" +
  "    '10':'安全令牌C', '11':'邮箱验证码', '12':'钉钉验证码', '13':'哈工大 APP 验证码'\n" +
  '  };\n' +
  "  var descriptionKey = reAuthType ? ('reAuthDec' + reAuthType) : '';\n" +
  '  var visiblePromptEl = Array.prototype.slice.call(\n' +
  "    document.querySelectorAll('[id^=reAuthDec]')\n" +
  '  ).find(isVisible) || null;\n' +
  '  var promptEl = visiblePromptEl ||\n' +
  '    (descriptionKey && document.getElementById(descriptionKey)) ||\n' +
  "    document.getElementById('reAuthDec');\n" +
  '  var visibleTypeMatch = promptEl && promptEl.id ? promptEl.id.match(/^reAuthDec(\\d+)$/) : null;\n' +
  '  var effectiveType = visibleTypeMatch ? visibleTypeMatch[1] : reAuthType;\n' +
  '  var method = methodNames[effectiveType] ||\n' +
  "    (methodBtn ? methodBtn.textContent.trim() : '') || '二次验证';\n" +
  '  var effectiveDescriptionKey = effectiveType ? (\'reAuthDec\' + effectiveType) : descriptionKey;\n' +
  '  var prompt = plainText((promptEl && promptEl.textContent) ||\n' +
  "    (effectiveDescriptionKey && params[effectiveDescriptionKey]) || '');\n" +
  "  var sendIds = ['getDynamicCode', 'getImprovePhoneCodeId_otp', 'getImproveEmailCodeId_otp'];\n" +
  '  var sendButton = null;\n' +
  '  for (var i = 0; i < sendIds.length && !sendButton; i++) {\n' +
  '    var candidate = document.getElementById(sendIds[i]);\n' +
  '    if (isVisible(candidate)) sendButton = candidate;\n' +
  '  }\n' +
  '  if (!sendButton) {\n' +
  '    sendButton = Array.prototype.slice.call(document.querySelectorAll(\n' +
  "      '[onclick*=DynamicCode], [onclick*=dynamicCode], [id*=DynamicCode], [id*=dynamicCode]'\n" +
  '    )).find(function(el) { return isVisible(el) && el !== visibleInput; }) || null;\n' +
  '  }\n' +
  '  var result = {\n' +
  '    mfa: true,\n' +
  '    method: method,\n' +
  '    methodType: effectiveType,\n' +
  '    prompt: prompt,\n' +
  '    inputs: [],\n' +
  "    submitId: submitButton ? (submitButton.id || 'visible-submit') : '',\n" +
  '    canSendCode: !!sendButton,\n' +
  '    ready: document.readyState\n' +
  '  };\n' +
  '  if (visibleInput) {\n' +
  '    result.inputs.push({\n' +
  "      id: visibleInput.id || '',\n" +
  "      name: visibleInput.name || '',\n" +
  "      type: visibleInput.type || 'text',\n" +
  "      placeholder: visibleInput.placeholder || ''\n" +
  '    });\n' +
  '  }\n' +
  '  return JSON.stringify(result);\n' +
  '})();';

/** 填码并点提交（submitNativeMfaInput 注入体，逐字语义；JSON 引号安全插入）。 */
export function buildMfaSubmitScript(code: string, preferredInputId: string): string {
  const safeCode: string = JSON.stringify(code === undefined || code === null ? '' : code);
  const pref: string = JSON.stringify(preferredInputId === undefined ? '' : preferredInputId);
  return '(function() {\n' +
  '  var result = {ok:false, error:\'\'};\n' +
  '  // Find the visible code input field\n' +
  '  var input = null;\n' +
  '  var preferredId = ' + pref + ';\n' +
  '  if (preferredId) {\n' +
  '    var preferred = document.getElementById(preferredId);\n' +
  "    if (preferred && preferred.offsetParent !== null) input = preferred;\n" +
  '  }\n' +
  "  var codeIds = ['dynamicCode','captcha_code','smsCode','otpCode','verifyCode'];\n" +
  "  for (var i=0; !input && i<codeIds.length;i++) {\n" +
  "    var el = document.getElementById(codeIds[i]);\n" +
  "    if (el && el.offsetParent !== null) { input = el; break; }\n" +
  '  }\n' +
  '  if (!input) {\n' +
  "    var inputs = document.querySelectorAll('input:not([type=hidden])');\n" +
  '    for (var i=0;i<inputs.length;i++) {\n' +
  "      if (inputs[i].offsetParent !== null && inputs[i].type !== 'password') { input = inputs[i]; break; }\n" +
  '    }\n' +
  '  }\n' +
  '  if (!input) {\n' +
  "    var pwd = document.getElementById('password');\n" +
  '    if (pwd) input = pwd;\n' +
  '  }\n' +
  '  if (input) {\n' +
  '    input.value = ' + safeCode + ';\n' +
  "    input.dispatchEvent(new Event('input', {bubbles:true}));\n" +
  "    input.dispatchEvent(new Event('change', {bubbles:true}));\n" +
  "    result.inputId = input.id || input.name || 'unknown';\n" +
  '  }\n' +
  '  // Click submit button by exact ID\n' +
  "  var submitBtn = Array.prototype.slice.call(document.querySelectorAll('#reAuthSubmitBtn, [id*=reAuthSubmit], .submit_btn')).find(function(el) {\n" +
  '    var rect = el.getBoundingClientRect();\n' +
  '    var style = window.getComputedStyle(el);\n' +
  "    return style.display !== 'none' && style.visibility !== 'hidden' && rect.width > 0 && rect.height > 0;\n" +
  '  });\n' +
  '  if (submitBtn) {\n' +
  '    submitBtn.click();\n' +
  '    result.ok = true;\n' +
  "  } else {\n" +
  "    result.error = 'reAuthSubmitBtn not found';\n" +
  '  }\n' +
  '  return JSON.stringify(result);\n' +
  '})();';
}

/** 打开发送/切换方式选择器（switchNativeMfaMethod 注入体，逐字）。 */
export const MFA_SWITCH_METHOD_SCRIPT: string =
  '(function() {\n' +
  '  try {\n' +
  "    if (typeof mobileChangeOtherType !== 'function') {\n" +
  "      return JSON.stringify({ok:false, error:'METHOD_PICKER_NOT_FOUND'});\n" +
  '    }\n' +
  '    mobileChangeOtherType();\n' +
  '    return JSON.stringify({ok:true});\n' +
  '  } catch (e) {\n' +
  '    return JSON.stringify({ok:false, error:String(e && e.message || e)});\n' +
  '  }\n' +
  '})();';

/** 触发发送验证码（triggerNativeMfaSendCode 注入体，逐字）。 */
export const MFA_SEND_CODE_SCRIPT: string =
  '(function() {\n' +
  '  try {\n' +
  '    function isVisible(el) {\n' +
  "      if (!el || el.disabled) return false;\n" +
  '      var style = window.getComputedStyle(el);\n' +
  '      var rect = el.getBoundingClientRect();\n' +
  "      return style.display !== 'none' && style.visibility !== 'hidden' &&\n" +
  '        rect.width > 0 && rect.height > 0;\n' +
  '    }\n' +
  "    var targetIds = ['getDynamicCode', 'getImprovePhoneCodeId_otp', 'getImproveEmailCodeId_otp'];\n" +
  '    var target = null;\n' +
  '    for (var i = 0; i < targetIds.length; i++) {\n' +
  '      var btn = document.getElementById(targetIds[i]);\n' +
  '      if (isVisible(btn)) { target = btn; break; }\n' +
  '    }\n' +
  '    if (!target) {\n' +
  '      target = Array.prototype.slice.call(document.querySelectorAll(\n' +
  "        '[onclick*=DynamicCode], [onclick*=dynamicCode], [id*=DynamicCode], [id*=dynamicCode]'\n" +
  '      )).find(function(el) {\n' +
  "        return isVisible(el) && el.tagName !== 'INPUT';\n" +
  '      }) || null;\n' +
  '    }\n' +
  '    if (target) {\n' +
  '      target.click();\n' +
  "      return JSON.stringify({ok:true, id:target.id || 'dynamic-code-action'});\n" +
  '    }\n' +
  "    return JSON.stringify({ok:false, error:'NOT_FOUND'});\n" +
  '  } catch(e) {\n' +
  '    return JSON.stringify({ok:false, error: e.message});\n' +
  '  }\n' +
  '})();';

export class EasWebMfaBridge {
  /**
   * 探测当前页面是否为 MFA 页并给出覆盖层状态。
   * 返回 visible=false 表示非 MFA 页/无可桥接输入。
   */
  static async detect(controller: webview.WebviewController): Promise<EasMfaOverlayState> {
    const state: EasMfaOverlayState = new EasMfaOverlayState();
    const raw: string = await EasWebMfaBridge.runJs(controller, MFA_DETECT_SCRIPT);
    if (isBlank(raw)) {
      return state;
    }
    const json: string = EasWebMfaBridge.sanitize(raw);
    try {
      const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      if (parsed['mfa'] !== true) {
        return state;
      }
      const str = (k: string): string => parsed[k] === undefined || parsed[k] === null ? '' : String(parsed[k]);
      state.visible = true;
      state.verifyMethod = str('method');
      state.verifyMethodType = str('methodType');
      state.promptTitle = str('method').length > 0 ? str('method') : '二次验证';
      state.promptText = str('prompt');
      state.submitButtonId = str('submitId');
      state.canSendCode = parsed['canSendCode'] === true;
      const inputs: Array<Record<string, Object>> =
        parsed['inputs'] as Array<Record<string, Object>>;
      if (inputs !== undefined && inputs !== null && inputs.length > 0) {
        const first: Record<string, Object> = inputs[0];
        const iv = (k: string): string =>
          first[k] === undefined || first[k] === null ? '' : String(first[k]);
        state.hasVisibleInput = true;
        state.inputId = iv('id').length > 0 ? iv('id') : iv('name');
        state.inputType = iv('type').length > 0 ? iv('type') : 'text';
        state.inputPlaceholder = iv('placeholder');
      }
    } catch (e) {
      return state;
    }
    return state;
  }

  /** 填码并点提交；返回 {ok,error}（ok=true 时等待页面跳转，由调用方收覆盖层）。 */
  static async submit(controller: webview.WebviewController, code: string,
    preferredInputId: string): Promise<EasMfaAction> {
    const raw: string = await EasWebMfaBridge.runJs(controller,
      buildMfaSubmitScript(code, preferredInputId));
    return EasWebMfaBridge.parseAction(raw);
  }

  /** 触发发送验证码。 */
  static async sendCode(controller: webview.WebviewController): Promise<EasMfaAction> {
    const raw: string = await EasWebMfaBridge.runJs(controller, MFA_SEND_CODE_SCRIPT);
    return EasWebMfaBridge.parseAction(raw);
  }

  /** 打开发送/切换方式选择器（选择器内自动点“手机号验证码”轮询为二期 TODO）。 */
  static async switchMethod(controller: webview.WebviewController): Promise<EasMfaAction> {
    const raw: string = await EasWebMfaBridge.runJs(controller, MFA_SWITCH_METHOD_SCRIPT);
    return EasWebMfaBridge.parseAction(raw);
  }

  /** 执行任意注入脚本并返回结果（可抛异常→空串）。 */
  static async runJs(controller: webview.WebviewController, script: string): Promise<string> {
    return new Promise<string>((resolve) => {
      const timer: number = setTimeout(() => resolve(''), 5000);
      try {
        controller.runJavaScript(script).then((result: string) => {
          clearTimeout(timer);
          resolve(result === undefined || result === null ? '' : result);
        }).catch(() => {
          clearTimeout(timer);
          resolve('');
        });
      } catch (e) {
        clearTimeout(timer);
        resolve('');
      }
    });
  }

  /** runJavaScript 返回带引号包裹的字符串：去外层引号与 \" 转义。 */
  static sanitize(raw: string): string {
    let t: string = raw === undefined || raw === null ? '' : raw.trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      t = t.substring(1, t.length - 1);
    }
    t = t.replace(/\\"/g, '"');
    return t;
  }

  static parseAction(raw: string): EasMfaAction {
    const action: EasMfaAction = new EasMfaAction();
    if (isBlank(raw)) {
      return action;
    }
    const json: string = EasWebMfaBridge.sanitize(raw);
    try {
      const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      action.ok = parsed['ok'] === true;
      action.error = parsed['error'] === undefined || parsed['error'] === null ? '' :
        String(parsed['error']);
      action.extra = json;
    } catch (e) {
      action.ok = false;
      action.error = 'parse error';
    }
    return action;
  }
}

function isBlank(s: string): boolean {
  return s === undefined || s === null || s.trim().length === 0;
}
