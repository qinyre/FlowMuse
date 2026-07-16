package recognition

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"
)

func TestAIAgentUsesToolsAndParsesOpenAICompatibleToolCalls(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/chat/completions" {
			t.Fatalf("unexpected path: %s", r.URL.Path)
		}
		var body map[string]any
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			t.Fatal(err)
		}
		if tools, ok := body["tools"].([]any); !ok || len(tools) != 2 {
			t.Fatalf("expected two tools, got %#v", body["tools"])
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{
          "choices":[{"message":{"content":"","tool_calls":[
            {"type":"function","function":{"name":"rename_note","arguments":"{\"title\":\"项目会议纪要\"}"}},
            {"type":"function","function":{"name":"insert_text","arguments":"{\"text\":\"总结：完成第一版。\"}"}}
          ]}}]
        }`))
	}))
	defer server.Close()

	agent := NewOpenAICompatibleSmartLayouter(OpenAICompatibleConfig{
		BaseURL: server.URL,
		APIKey:  "test-key",
		Model:   "test-model",
		Timeout: time.Second,
	})
	response, err := agent.RunAgent(context.Background(), AIAgentRequest{
		Instruction: "总结并重命名",
		NoteTitle:   "未命名笔记",
		Texts:       []AIAgentText{{ID: "text-1", Text: "今天完成第一版。"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(response.Actions) != 2 {
		t.Fatalf("expected two actions, got %#v", response.Actions)
	}
	if response.Actions[0].Arguments["title"] != "项目会议纪要" {
		t.Fatalf("unexpected rename action: %#v", response.Actions[0])
	}
	if response.Actions[1].Arguments["text"] != "总结：完成第一版。" {
		t.Fatalf("unexpected insert action: %#v", response.Actions[1])
	}
}

func TestAIAgentRejectsUnknownTool(t *testing.T) {
	response, err := parseAIAgentResponse([]byte(`{
      "choices":[{"message":{"tool_calls":[
        {"type":"function","function":{"name":"delete_note","arguments":"{}"}}
      ]}}]
    }`))
	if err != nil {
		t.Fatal(err)
	}
	if err := validateAIAgentActions(response.Actions); err == nil {
		t.Fatal("expected unknown tool to be rejected")
	}
}

func TestAIAgentEndpointRequiresAuthentication(t *testing.T) {
	api := NewHTTPAPI(nil, time.Second).WithAIAgent(
		staticAIAgent{},
		func(*http.Request) bool { return false },
	)
	mux := http.NewServeMux()
	api.Register(mux)
	request := httptest.NewRequest(http.MethodPost, "/api/ai/agent", strings.NewReader(`{}`))
	response := httptest.NewRecorder()

	mux.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", response.Code)
	}
}

func TestAIAgentConfiguredModelCompatibility(t *testing.T) {
	if os.Getenv("FLOWMUSE_AI_INTEGRATION") != "1" {
		t.Skip("set FLOWMUSE_AI_INTEGRATION=1 to call the configured model")
	}
	agent := NewOpenAICompatibleSmartLayouter(OpenAICompatibleConfig{
		BaseURL: os.Getenv("FLOWMUSE_AI_BASE_URL"),
		APIKey:  os.Getenv("FLOWMUSE_AI_API_KEY"),
		Model:   os.Getenv("FLOWMUSE_AI_MODEL"),
		Timeout: 30 * time.Second,
	})
	response, err := agent.RunAgent(context.Background(), AIAgentRequest{
		Instruction: "总结内容并生成标题",
		NoteTitle:   "未命名笔记",
		Texts:       []AIAgentText{{ID: "text-1", Text: "本周完成 AI 笔记助手第一版。"}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(response.Actions) == 0 {
		t.Fatal("configured model returned no actions")
	}
}

type staticAIAgent struct{}

func (staticAIAgent) RunAgent(context.Context, AIAgentRequest) (AIAgentResponse, error) {
	return AIAgentResponse{
		Message: "ok",
		Actions: []AIAgentAction{{
			Tool:      "insert_text",
			Arguments: map[string]string{"text": "ok"},
		}},
	}, nil
}
