package recognition

import (
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

// 双端 conformance：Go 与 Dart 消费同一 fixtures
// （docs/研发记录/specs/smart-layout-v3/protocol/fixtures）。
// go test CWD=internal/recognition。
const fixtureRoot = "../../../docs/研发记录/specs/smart-layout-v3/protocol/fixtures"

type fixtureDoc struct {
	Kind              string          `json:"kind"`
	Expect            string          `json:"expect"`
	ExpectedErrorCode string          `json:"expectedErrorCode"`
	Payload           json.RawMessage `json:"payload"`
}

func loadFixtures(t *testing.T, sub string) []struct {
	name string
	doc  fixtureDoc
} {
	t.Helper()
	dir := filepath.Join(fixtureRoot, sub)
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatalf("读取 fixtures 目录失败 %s: %v", dir, err)
	}
	var out []struct {
		name string
		doc  fixtureDoc
	}
	for _, entry := range entries {
		raw, err := os.ReadFile(filepath.Join(dir, entry.Name()))
		if err != nil {
			t.Fatalf("读取 fixture 失败: %v", err)
		}
		var doc fixtureDoc
		if err := json.Unmarshal(raw, &doc); err != nil {
			t.Fatalf("fixture %s 结构错误: %v", entry.Name(), err)
		}
		out = append(out, struct {
			name string
			doc  fixtureDoc
		}{entry.Name(), doc})
	}
	if len(out) == 0 {
		t.Fatalf("%s 下没有 fixture", dir)
	}
	return out
}

func parseByKind(kind string, payload []byte) (any, *SmartLayoutV3Error) {
	switch kind {
	case "request":
		req, err := ParseSmartLayoutV3Request(payload)
		return req, err
	case "response":
		resp, err := ParseSmartLayoutV3Response(payload)
		return resp, err
	}
	return nil, v3err(V3ErrInvalidRequest, "", "未知 fixture kind: %s", kind)
}

func TestPositiveFixturesRoundTrip(t *testing.T) {
	for _, fixture := range loadFixtures(t, "positive") {
		t.Run(fixture.name, func(t *testing.T) {
			parsed, err := parseByKind(fixture.doc.Kind, fixture.doc.Payload)
			if err != nil {
				t.Fatalf("正例被拒绝: %v", err)
			}
			serialized, mErr := json.Marshal(parsed)
			if mErr != nil {
				t.Fatalf("序列化失败: %v", mErr)
			}
			roundTripped, err := parseByKind(fixture.doc.Kind, serialized)
			if err != nil {
				t.Fatalf("round-trip 解析失败: %v（%s）", err, string(serialized))
			}
			if !reflect.DeepEqual(parsed, roundTripped) {
				t.Fatalf("round-trip 语义不等价:\n%+v\n%+v", parsed, roundTripped)
			}
		})
	}
}

func TestNegativeFixturesRejectedWithSameCode(t *testing.T) {
	for _, fixture := range loadFixtures(t, "negative") {
		t.Run(fixture.name, func(t *testing.T) {
			_, err := parseByKind(fixture.doc.Kind, fixture.doc.Payload)
			if err == nil {
				t.Fatalf("负例被接受（期望 %s）", fixture.doc.ExpectedErrorCode)
			}
			if err.Code != fixture.doc.ExpectedErrorCode {
				t.Fatalf("错误码不一致：got %s（%s） want %s", err.Code, err.Message, fixture.doc.ExpectedErrorCode)
			}
			if err.Message == "" || err.Field == "" {
				t.Fatalf("拒绝必须带 message 与 field：%+v", err)
			}
		})
	}
}

func TestSmartLayoutV3ErrorEnvelope(t *testing.T) {
	raw, err := json.Marshal(&SmartLayoutV3Error{
		Code: V3ErrUnknownEnum, Message: "x", Field: "assets[0].kind",
	})
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]string
	if err := json.Unmarshal(raw, &decoded); err != nil {
		t.Fatal(err)
	}
	want := map[string]string{"code": "unknown_enum", "message": "x", "field": "assets[0].kind"}
	if !reflect.DeepEqual(decoded, want) {
		t.Fatalf("错误 envelope 序列化不符：%v", decoded)
	}
}

func TestParseRejectsMalformedJson(t *testing.T) {
	if _, err := ParseSmartLayoutV3Request([]byte(`{"protocolVersion":3,`)); err == nil || err.Code != V3ErrInvalidRequest {
		t.Fatalf("残缺 JSON 应 invalid_request 拒绝：%+v", err)
	}
}
