// V3-700A：比赛演示 smoke——服务端真实 v3 analyzer 本地启动与端到端。
//
// httptest 启动真实端点（RegisterSmartLayoutV3 + V3Analyzer + 确定性
// demo provider：逐 exactText 合成 body region，全额认领文本源），
// 合成请求 → 200 + 冻结响应 schema；非法请求 → 400 + 冻结错误
// envelope（fail closed 可重复演示）。
//
// 证据生成：FLOWMUSE_GENERATE_V3_700A_EVIDENCE=1 一次性写入
// docs/研发记录/evidence/smart-layout-v3/competition/v3-700a-server-smoke.json；
// 常规 go test 只验证行为不写文件。
package recognition

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// demoSmokeProvider：确定性合成——每个 exactText 一个 body region，
// 引用全部落在请求 sourceRefs 内（sanitize 契约）。
func demoSmokeProvider(ctx context.Context, req *SmartLayoutV3Request) ([]byte, error) {
	regions := make([]map[string]any, 0, len(req.ExactTexts))
	for i, t := range req.ExactTexts {
		regions = append(regions, map[string]any{
			"id":          fmt.Sprintf("demo-region-%d", i),
			"role":        "body",
			"sourceIds":   []string{t.SourceID},
			"readingOrder": i,
			"confidence":  0.9,
			"relations":   []any{},
		})
	}
	return json.Marshal(map[string]any{
		"protocolVersion": 3,
		"requestId":       "demo-server-req-1",
		"regions":         regions,
		"warnings":        []string{},
	})
}

func TestSmartLayoutV3DemoSmokeStartupAndServe(t *testing.T) {
	mux := http.NewServeMux()
	analyzer := NewV3Analyzer(demoSmokeProvider, DefaultV3RequestLimits())
	RegisterSmartLayoutV3(mux, analyzer)
	server := httptest.NewServer(mux)
	defer server.Close()
	endpoint := server.URL + "/api/ink/smart-layout/analyze/v3"

	// 合成比赛演示请求（与既有 endpoint 测试同 schema）。
	sourceRefs := []string{"text-1", "text-2", "ink-3"}
	requestBytes, _ := json.Marshal(map[string]any{
		"protocolVersion": 3,
		"pageId":          "demo-page-1",
		"sceneRevision":   map[string]any{"epoch": 0, "revision": 1, "fingerprint": "0123456789abcdef"},
		"assets":          []map[string]any{{"key": "clean|page", "kind": "clean", "fingerprint": "0123456789abcdef"}},
		"marks":           []map[string]any{},
		"exactTexts": []map[string]any{
			{"sourceId": "text-1", "text": "标题：演示文稿"},
			{"sourceId": "text-2", "text": "第二段正文"},
		},
		"sourceRefs": sourceRefs,
	})

	start := time.Now()
	resp, err := http.Post(endpoint, "application/json", bytes.NewReader(requestBytes))
	if err != nil {
		t.Fatalf("analyzer 启动失败：%v", err)
	}
	defer resp.Body.Close()
	latencyMs := time.Since(start).Milliseconds()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("状态码 %d，期望 200", resp.StatusCode)
	}
	var payload struct {
		ProtocolVersion int             `json:"protocolVersion"`
		Regions         json.RawMessage `json:"regions"`
		Error           json.RawMessage `json:"error"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if payload.ProtocolVersion != 3 {
		t.Fatalf("protocolVersion %d，期望 3", payload.ProtocolVersion)
	}
	var regions []struct {
		ID        string   `json:"id"`
		Role      string   `json:"role"`
		SourceIDs []string `json:"sourceIds"`
	}
	if err := json.Unmarshal(payload.Regions, &regions); err != nil {
		t.Fatalf("regions 解码失败：%v", err)
	}
	if len(regions) != 2 {
		t.Fatalf("regions %d 个，期望 2（逐 exactText 合成）", len(regions))
	}
	allowed := map[string]bool{}
	for _, ref := range sourceRefs {
		allowed[ref] = true
	}
	for _, region := range regions {
		for _, source := range region.SourceIDs {
			if !allowed[source] {
				t.Fatalf("region %s 引用未知源 %s", region.ID, source)
			}
		}
	}
	if payload.Error != nil {
		t.Fatal("成功响应不应带 error")
	}

	// fail closed 演示：非法请求 → 400 + 冻结错误 envelope。
	bad, _ := json.Marshal(map[string]any{"protocolVersion": 3})
	resp2, err := http.Post(endpoint, "application/json", bytes.NewReader(bad))
	if err != nil {
		t.Fatal(err)
	}
	defer resp2.Body.Close()
	if resp2.StatusCode != http.StatusBadRequest {
		t.Fatalf("非法请求状态码 %d，期望 400", resp2.StatusCode)
	}
	var errPayload map[string]SmartLayoutV3Error
	if err := json.NewDecoder(resp2.Body).Decode(&errPayload); err != nil {
		t.Fatal(err)
	}
	if errPayload["error"].Code != V3ErrInvalidRequest {
		t.Fatalf("错误 envelope code：%+v", errPayload["error"])
	}

	// 证据一次性生成（常规运行零写盘）。
	if os.Getenv("FLOWMUSE_GENERATE_V3_700A_EVIDENCE") == "1" {
		root, err := findDemoRepoRoot()
		if err != nil {
			t.Fatalf("仓库根解析失败：%v", err)
		}
		dir := filepath.Join(root, "docs", "研发记录", "evidence", "smart-layout-v3", "competition")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("证据目录创建失败：%v", err)
		}
		report := map[string]any{
			"task":    "V3-700A",
			"kind":    "demo_smoke_report",
			"side":    "server",
			"started": true,
			"endpoint": "/api/ink/smart-layout/analyze/v3",
			"happy_path": map[string]any{
				"status":             200,
				"protocol_version":   payload.ProtocolVersion,
				"region_count":       len(regions),
				"latency_ms":         latencyMs,
				"sources_fully_used": true,
			},
			"fail_closed_path": map[string]any{
				"status": 400,
				"code":   string(errPayload["error"].Code),
			},
			"generated_at_unix": time.Now().Unix(),
		}
		data, err := json.MarshalIndent(report, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		target := filepath.Join(dir, "v3-700a-server-smoke.json")
		if err := os.WriteFile(target, append(data, '\n'), 0o644); err != nil {
			t.Fatalf("证据写入失败：%v", err)
		}
		t.Logf("server demo smoke 证据已写入 %s", target)
	}
}

// findDemoRepoRoot：从测试工作目录向上定位仓库根（同时含
// FlowMuse-App 与 FlowMuse-Server 的目录）。
func findDemoRepoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		appInfo, appErr := os.Stat(filepath.Join(dir, "FlowMuse-App"))
		serverInfo, serverErr := os.Stat(filepath.Join(dir, "FlowMuse-Server"))
		if appErr == nil && appInfo.IsDir() && serverErr == nil && serverInfo.IsDir() {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("未找到仓库根（FlowMuse-App/FlowMuse-Server 并存目录）")
		}
		dir = parent
	}
}
