// V3-704A：服务端旧端点隔离与保留说明——目标符号
// [SmartLayoutRouteIsolationMatrix] 与 [RegisterSmartLayoutV3]。
//
// 路由矩阵证明旧端点（比赛版本兼容保留：不做 census、410 或删除）
// 与 v3 端点独立、无路径冲突：
//  1. 同一 mux 同时注册全部旧端点 + v3——ServeMux 对重复路径会 panic，
//     构建成功本身即证明无路径冲突；
//  2. 路径唯一性：v3 路径与全部旧路径两两不同；
//  3. 各路由独立命中：GET（各 handler 仅收 POST）→ 405，证明路由真实
//     注册且互不遮蔽；旧端点 POST（未配置 layouter）→ 502 not
//     configured，证明到达旧 handler 而非 404；
//  4. v3 smoke：合法请求 200 + protocolVersion 3；非法请求 400 + 冻结
//     错误 envelope。
//
// 证据生成：FLOWMUSE_GENERATE_V3_704A_EVIDENCE=1 一次性写入
// docs/研发记录/evidence/smart-layout-v3/competition/v3-704a-route-isolation.json。
package recognition

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

// SmartLayoutRouteIsolationMatrix：旧端点与 v3 端点的路由隔离矩阵。
type SmartLayoutRouteIsolationMatrix struct {
	LegacyRoutes []string
	V3Route      string
	ProbeGET     map[string]int
	ProbePOST    map[string]int
}

func TestSmartLayoutRouteIsolationMatrix(t *testing.T) {
	// 1) 同一 mux 注册全部旧端点 + v3（重复路径会 panic）。
	mux := http.NewServeMux()
	api := NewHTTPAPI(nil, 0, nil).WithV3Analyzer(
		NewV3Analyzer(demoSmokeProvider, DefaultV3RequestLimits()),
	)
	api.Register(mux)
	server := httptest.NewServer(mux)
	defer server.Close()

	legacyRoutes := []string{
		"/api/ink/recognize",
		"/api/ink/smart-layout",
		"/api/ink/smart-layout/block",
		"/api/ink/smart-layout/compose",
		"/api/ink/smart-layout/vision",
		"/api/ink/smart-layout/transcribe",
	}
	const v3Route = "/api/ink/smart-layout/analyze/v3"

	// 2) 路径唯一性。
	for _, legacy := range legacyRoutes {
		if legacy == v3Route {
			t.Fatalf("v3 路径与旧路径冲突：%s", legacy)
		}
	}

	probe := func(method, path string, body []byte) int {
		t.Helper()
		var reader *bytes.Reader
		if body == nil {
			reader = bytes.NewReader(nil)
		} else {
			reader = bytes.NewReader(body)
		}
		req, err := http.NewRequest(method, server.URL+path, reader)
		if err != nil {
			t.Fatal(err)
		}
		req.Header.Set("Content-Type", "application/json")
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		return resp.StatusCode
	}

	matrix := SmartLayoutRouteIsolationMatrix{
		LegacyRoutes: legacyRoutes,
		V3Route:      v3Route,
		ProbeGET:     map[string]int{},
		ProbePOST:    map[string]int{},
	}

	// 3) 各路由独立命中：GET → 405（仅收 POST 的 handler 先于业务校验）。
	for _, route := range append(append([]string{}, legacyRoutes...), v3Route) {
		status := probe(http.MethodGet, route, nil)
		matrix.ProbeGET[route] = status
		if status != http.StatusMethodNotAllowed {
			t.Fatalf("GET %s 状态码 %d，期望 405（路由未独立命中或被遮蔽）", route, status)
		}
	}

	// 旧端点 POST（未配置 layouter/recognizer 前置方法已过）→ 502
	// not configured，证明到达旧 handler 而非 404/405。
	for _, route := range legacyRoutes {
		if route == "/api/ink/recognize" {
			// recognize 无 recognizer 的行为不在本矩阵口径（识别通道，
			// 非智能排版端点家族）；405 已证明其路由独立。
			continue
		}
		status := probe(http.MethodPost, route, []byte(`{}`))
		matrix.ProbePOST[route] = status
		if status != http.StatusBadGateway {
			t.Fatalf("POST %s 状态码 %d，期望 502（旧 handler 未配置降级）", route, status)
		}
	}

	// 4) v3 smoke：合法 200 + protocolVersion 3；非法 400 envelope。
	requestBytes, _ := json.Marshal(map[string]any{
		"protocolVersion": 3,
		"pageId":          "route-isolation-page",
		"sceneRevision":   map[string]any{"epoch": 0, "revision": 1, "fingerprint": "0123456789abcdef"},
		"assets":          []map[string]any{{"key": "clean|page", "kind": "clean", "fingerprint": "0123456789abcdef"}},
		"marks":           []map[string]any{},
		"exactTexts":      []map[string]any{{"sourceId": "text-1", "text": "路由隔离样本"}},
		"sourceRefs":      []string{"text-1"},
	})
	resp, err := http.Post(server.URL+v3Route, "application/json", bytes.NewReader(requestBytes))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	matrix.ProbePOST[v3Route] = resp.StatusCode
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("v3 合法请求状态码 %d", resp.StatusCode)
	}
	var payload struct {
		ProtocolVersion int             `json:"protocolVersion"`
		Regions         json.RawMessage `json:"regions"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		t.Fatal(err)
	}
	if payload.ProtocolVersion != 3 {
		t.Fatalf("v3 protocolVersion %d", payload.ProtocolVersion)
	}

	badStatus := probe(http.MethodPost, v3Route, []byte(`{"protocolVersion":3}`))
	if badStatus != http.StatusBadRequest {
		t.Fatalf("v3 非法请求状态码 %d，期望 400", badStatus)
	}

	// 证据一次性生成（常规运行零写盘）。
	if os.Getenv("FLOWMUSE_GENERATE_V3_704A_EVIDENCE") == "1" {
		root, err := findDemoRepoRoot()
		if err != nil {
			t.Fatalf("仓库根解析失败：%v", err)
		}
		dir := filepath.Join(root, "docs", "研发记录", "evidence", "smart-layout-v3", "competition")
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatalf("证据目录创建失败：%v", err)
		}
		report := map[string]any{
			"task":             "V3-704A",
			"kind":             "route_isolation_matrix",
			"legacy_routes":    legacyRoutes,
			"v3_route":         v3Route,
			"no_path_conflict": true,
			"probe_get_405":    matrix.ProbeGET,
			"probe_post":       matrix.ProbePOST,
			"v3_smoke":         map[string]any{"status": 200, "protocol_version": payload.ProtocolVersion, "bad_request_status": badStatus},
			"retention_note":   "旧端点仅为比赛版本兼容保留：原位不删除、不做 census、不返 410；v3 与旧端点在同一 mux 独立服务",
		}
		data, err := json.MarshalIndent(report, "", "  ")
		if err != nil {
			t.Fatal(err)
		}
		target := filepath.Join(dir, "v3-704a-route-isolation.json")
		if err := os.WriteFile(target, append(data, '\n'), 0o644); err != nil {
			t.Fatalf("证据写入失败：%v", err)
		}
		t.Logf("route isolation 证据已写入 %s", target)
	}
}
