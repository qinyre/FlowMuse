package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strconv"
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
	value := int(sum[0])<<8 | int(sum[1])
	return "匿名用户 " + strconv.Itoa(value%9000+1000)
}
