package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

var ErrInvalidToken = errors.New("invalid auth token")

type TokenService struct {
	secret []byte
	ttl    time.Duration
}

type tokenClaims struct {
	UserID    string `json:"uid"`
	SessionID string `json:"sid"`
	Email     string `json:"email"`
	Exp       int64  `json:"exp"`
}

func NewTokenService(secret string, ttl time.Duration) *TokenService {
	return &TokenService{
		secret: []byte(secret),
		ttl:    ttl,
	}
}

func (s *TokenService) Issue(user User, sessionID string) (string, error) {
	header := base64.RawURLEncoding.EncodeToString([]byte(`{"alg":"HS256","typ":"JWT"}`))
	body, err := json.Marshal(tokenClaims{
		UserID:    user.ID,
		SessionID: sessionID,
		Email:     user.Email,
		Exp:       time.Now().Add(s.ttl).Unix(),
	})
	if err != nil {
		return "", err
	}
	payload := base64.RawURLEncoding.EncodeToString(body)
	unsigned := header + "." + payload
	return unsigned + "." + s.sign(unsigned), nil
}

func (s *TokenService) Verify(token string) (string, string, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return "", "", ErrInvalidToken
	}
	unsigned := parts[0] + "." + parts[1]
	if !hmac.Equal([]byte(parts[2]), []byte(s.sign(unsigned))) {
		return "", "", ErrInvalidToken
	}
	body, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", "", ErrInvalidToken
	}
	var claims tokenClaims
	if err := json.Unmarshal(body, &claims); err != nil {
		return "", "", ErrInvalidToken
	}
	if claims.UserID == "" || claims.SessionID == "" || claims.Exp < time.Now().Unix() {
		return "", "", ErrInvalidToken
	}
	return claims.UserID, claims.SessionID, nil
}

func (s *TokenService) ExpiresAt() time.Time {
	return time.Now().Add(s.ttl)
}

func (s *TokenService) sign(value string) string {
	mac := hmac.New(sha256.New, s.secret)
	mac.Write([]byte(value))
	return base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
}

func BearerToken(header string) string {
	if header == "" {
		return ""
	}
	parts := strings.Fields(header)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return parts[1]
}

func GuestName(seed string) string {
	sum := sha256.Sum256([]byte(seed))
	adjectives := []string{
		"活泼", "敏捷", "勇敢", "聪慧", "温柔", "沉稳",
		"灵巧", "可靠", "明亮", "快乐", "优雅", "好奇",
		"专注", "自在", "友善", "坚定", "从容", "机敏",
		"灿烂", "安静", "热忱", "清醒", "坦率", "轻快",
	}
	nouns := []string{
		"猫", "狗", "狐狸", "熊猫", "狮子", "老虎",
		"狼", "小鹿", "骏马", "独角兽", "斑马", "长颈鹿",
		"大象", "犀牛", "河马", "袋鼠", "考拉", "兔子",
		"仓鼠", "海豚", "鲸鱼", "海豹", "企鹅", "鸭子",
		"天鹅", "鹦鹉", "猫头鹰", "蝴蝶", "蜜蜂", "章鱼",
		"乌龟", "螃蟹", "龙虾",
	}
	alphabet := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	adjective := adjectives[int(sum[0])%len(adjectives)]
	noun := nouns[int(sum[1])%len(nouns)]
	seq := []byte{
		alphabet[int(sum[2])%len(alphabet)],
		alphabet[int(sum[3])%len(alphabet)],
		alphabet[int(sum[4])%len(alphabet)],
		alphabet[int(sum[5])%len(alphabet)],
	}
	return adjective + "的" + noun + string(seq)
}
