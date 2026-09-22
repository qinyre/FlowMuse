package config

import (
	"reflect"
	"testing"
	"time"
)

func TestRecognitionV3ConfigurationIsolation(t *testing.T) {
	for key, value := range map[string]string{
		"DATABASE_URL": "postgres://test.invalid/test", "FLOWMUSE_S3_ENDPOINT": "test.invalid",
		"FLOWMUSE_S3_BUCKET": "test", "FLOWMUSE_S3_ACCESS_KEY_ID": "test-id",
		"FLOWMUSE_S3_SECRET_ACCESS_KEY": "test-secret", "ARK_API_KEY": "test-fallback",
		"FLOWMUSE_LAYOUT_V3_BASE_URL": "https://v3.invalid", "FLOWMUSE_LAYOUT_V3_API_KEY": "test-v3",
		"FLOWMUSE_LAYOUT_V3_MODEL": "v3-model", "FLOWMUSE_LAYOUT_V3_TIMEOUT_SECONDS": "45",
	} {
		t.Setenv(key, value)
	}
	load := func() Config {
		t.Helper()
		cfg, err := Load()
		if err != nil {
			t.Fatal(err)
		}
		return cfg
	}
	otherFields := func(c Config) []any {
		return []any{c.MyScriptAppKey, c.MyScriptHMACKey, c.MyScriptEndpoint, c.RecognitionTimeout}
	}
	newFields := func(c Config) []any {
		return []any{c.LayoutV3BaseURL, c.LayoutV3APIKey, c.LayoutV3Model, c.LayoutV3Timeout}
	}
	before := load()
	if !reflect.DeepEqual(newFields(before), []any{"https://v3.invalid", "test-v3", "v3-model", 45 * time.Second}) {
		t.Fatal("V3 必须读取独立配置")
	}
	t.Setenv("FLOWMUSE_LAYOUT_V3_BASE_URL", "https://v3-new.invalid")
	t.Setenv("FLOWMUSE_LAYOUT_V3_API_KEY", "test-v3-new")
	t.Setenv("FLOWMUSE_LAYOUT_V3_MODEL", "v3-new")
	t.Setenv("FLOWMUSE_LAYOUT_V3_TIMEOUT_SECONDS", "90")
	afterV3 := load()
	if !reflect.DeepEqual(otherFields(before), otherFields(afterV3)) {
		t.Fatal("修改 V3 影响了其他识别配置")
	}

	// 按协议只允许 API key 回落 ARK；URL/model 缺失不得借用旧引擎。
	t.Setenv("FLOWMUSE_LAYOUT_V3_BASE_URL", "")
	t.Setenv("FLOWMUSE_LAYOUT_V3_API_KEY", "")
	t.Setenv("FLOWMUSE_LAYOUT_V3_MODEL", "")
	missing := load()
	if missing.LayoutV3BaseURL != "" || missing.LayoutV3Model != "" || missing.LayoutV3APIKey != "test-fallback" {
		t.Fatal("V3 缺配置时发生未授权旧引擎回退")
	}
	t.Setenv("FLOWMUSE_LAYOUT_V3_TIMEOUT_SECONDS", "")
	if got := load().LayoutV3Timeout; got != 120*time.Second {
		t.Fatalf("V3 默认超时应与生产默认 120s 对齐：%v", got)
	}
}

// envIntSeconds 整数秒解析（spec §4 配置表：不得用 envDuration——
// time.ParseDuration 拒绝裸数字，会回落默认值）。
func TestEnvIntSeconds(t *testing.T) {
	t.Setenv("TEST_INT_SECONDS", "90")
	if got := envIntSeconds("TEST_INT_SECONDS", 60); got != 90*time.Second {
		t.Fatalf("裸数字 90 应解析为 90s: %v", got)
	}

	t.Setenv("TEST_INT_SECONDS", "1m30s")
	if got := envIntSeconds("TEST_INT_SECONDS", 60); got != 60*time.Second {
		t.Fatalf("ParseDuration 形态必须回落默认 60s: %v", got)
	}

	t.Setenv("TEST_INT_SECONDS", "0")
	if got := envIntSeconds("TEST_INT_SECONDS", 60); got != 60*time.Second {
		t.Fatalf("非正数必须回落默认: %v", got)
	}

	t.Setenv("TEST_INT_SECONDS", "-5")
	if got := envIntSeconds("TEST_INT_SECONDS", 60); got != 60*time.Second {
		t.Fatalf("负数必须回落默认: %v", got)
	}

	t.Setenv("TEST_INT_SECONDS", "  45  ")
	if got := envIntSeconds("TEST_INT_SECONDS", 60); got != 45*time.Second {
		t.Fatalf("容忍首尾空白: %v", got)
	}

	if got := envIntSeconds("TEST_INT_SECONDS_UNSET", 60); got != 60*time.Second {
		t.Fatalf("未设置用默认: %v", got)
	}
}

// 对照实验：envDuration 确实拒绝裸数字（防止有人改回 envDuration）。
func TestEnvDurationRejectsBareNumbers(t *testing.T) {
	t.Setenv("TEST_DURATION_BARE", "90")
	if got := envDuration("TEST_DURATION_BARE", 60*time.Second); got != 60*time.Second {
		t.Fatalf("envDuration 不应接受裸数字: %v", got)
	}
	t.Setenv("TEST_DURATION_BARE", "90s")
	if got := envDuration("TEST_DURATION_BARE", 60*time.Second); got != 90*time.Second {
		t.Fatalf("envDuration 应接受带单位形态: %v", got)
	}
}
