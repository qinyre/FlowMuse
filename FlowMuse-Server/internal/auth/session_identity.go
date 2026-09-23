package auth

import (
	"context"
	"strings"

	"github.com/zishang520/socket.io/v2/socket"
)

// AuthenticateToken is the common fail-closed boundary for HTTP and sockets.
func (s *UserStore) AuthenticateToken(ctx context.Context, tokens *TokenService, token string) (Identity, error) {
	if token == "" || tokens == nil || s == nil {
		return Identity{}, ErrInvalidToken
	}
	userID, sessionID, err := tokens.Verify(token)
	if err != nil || !s.SessionActive(ctx, sessionID, userID) {
		return Identity{}, ErrInvalidToken
	}
	user, err := s.Load(ctx, userID)
	if err != nil || !user.HasVerifiedIdentity() {
		return Identity{}, ErrInvalidToken
	}
	return Identity{UserID: user.ID, Email: user.Email, DisplayName: user.DisplayName, AvatarURL: user.AvatarURL}, nil
}

// SocketToken never reads credentials from query parameters.
func SocketToken(client *socket.Socket) (string, error) {
	var header string
	var handshake any
	if client != nil {
		if client.Request() != nil && client.Request().Request() != nil {
			header = client.Request().Request().Header.Get("Authorization")
		}
		if client.Handshake() != nil {
			handshake = client.Handshake().Auth
		}
	}
	return socketToken(header, handshake)
}

func socketToken(header string, handshake any) (string, error) {
	headerToken := BearerToken(header)
	if header != "" && headerToken == "" {
		return "", ErrInvalidToken
	}
	var authToken string
	if handshake != nil {
		values, ok := handshake.(map[string]any)
		if !ok {
			return "", ErrInvalidToken
		}
		if value, exists := values["token"]; exists {
			authToken, ok = value.(string)
			if !ok || strings.TrimSpace(authToken) == "" {
				return "", ErrInvalidToken
			}
		}
	}
	if headerToken != "" && authToken != "" && headerToken != authToken {
		return "", ErrInvalidToken
	}
	if authToken != "" {
		return authToken, nil
	}
	return headerToken, nil
}
