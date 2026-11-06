# AI 助手多模态模型预设

从设置页选择官方服务商与模型，填入 Base URL 和模型名。继续支持自定义地址与模型。切换服务商时清空表单中的旧密钥，用户确认保存后才更新本机配置。

预设须有官方图片输入和工具调用文档。保持现有 Chat Completions 请求，根据官方端点适配 GPT-6 的工具调用参数及 Claude 的输出预算。使用合成图片测试预设的视觉和工具调用能力，自定义端点仍可使用文字连接测试。

验证配置页的自动填入、密钥隔离、请求参数和测试结果判定。浏览器直连仍受各服务商的 CORS 策略约束。

## 官方核验与本地验证

- DeepSeek V4.1 Flash 使用官方 API ID `deepseek-flash`。[模型更新日志](https://api-docs.deepseek.com/updates/) · [图片输入](https://api-docs.deepseek.com/guides/vision/) · [工具调用](https://api-docs.deepseek.com/guides/tool_calls/)
- 智谱选择 GLM-5.3-Flash 与 FlashX。[官方模型说明](https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash)
- OpenAI 选择 GPT-6 Luna 与 Sol。Chat Completions 的工具调用使用 `reasoning_effort: none`。[官方迁移指南](https://developers.openai.com/api/docs/guides/latest-model)
- Anthropic 采用 Claude 5.5 的 Sonnet、Opus、Haiku 与官方兼容端点。服务商密钥须具备相应 API 权限。[模型目录](https://platform.claude.com/docs/en/models/overview) · [兼容接口](https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk)
- Google Gemini 选择 3.8 Flash 与 3.7 Flash。[模型目录](https://ai.google.dev/gemini-api/docs/models?authuser=002) · [兼容接口](https://aistudio.google.com/docs/openai)
- 静态检查无问题，助手、设置和指南的 151 项定向测试通过。请求验证使用模拟响应，真实账号和浏览器直连待验证。
