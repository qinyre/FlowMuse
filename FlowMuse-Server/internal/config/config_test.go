package config

import (
	"testing"
	"time"
)

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
