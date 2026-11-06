/// Official Chat Completions endpoints with documented image and tool support.
enum AiAgentProvider {
  deepseek(
    'DeepSeek',
    'https://api.deepseek.com',
    'https://api-docs.deepseek.com/guides/vision/',
    ['deepseek-flash'],
  ),
  zhipu(
    '智谱 GLM',
    'https://open.bigmodel.cn/api/paas/v4',
    'https://docs.bigmodel.cn/cn/guide/models/vlm/glm-5.3-flash',
    ['glm-5.3-flash', 'glm-5.3-flashx'],
  ),
  openai(
    'OpenAI',
    'https://api.openai.com/v1',
    'https://developers.openai.com/api/docs/guides/latest-model',
    ['gpt-6-luna', 'gpt-6-sol'],
  ),
  anthropic(
    'Anthropic',
    'https://api.anthropic.com/v1',
    'https://platform.claude.com/docs/en/cli-sdks-libraries/libraries/openai-sdk',
    ['claude-sonnet-5-5', 'claude-opus-5-5', 'claude-haiku-5-5'],
  ),
  gemini(
    'Google Gemini',
    'https://generativelanguage.googleapis.com/v1beta/openai',
    'https://aistudio.google.com/docs/openai',
    ['gemini-3.8-flash', 'gemini-3.7-flash'],
  );

  const AiAgentProvider(this.label, this.baseUrl, this.docsUrl, this.models);

  final String label;
  final String baseUrl;
  final String docsUrl;
  final List<String> models;

  static AiAgentProvider? forEndpoint(Uri endpoint) => values
      .where(
        (provider) =>
            endpoint == Uri.parse('${provider.baseUrl}/chat/completions'),
      )
      .firstOrNull;
}
