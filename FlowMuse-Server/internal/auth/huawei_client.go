package auth

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"time"
)

var ErrInvalidHuaweiCode = errors.New("invalid Huawei authorization")
var errHuaweiUnavailable = errors.New("Huawei account service unavailable")

// HuaweiClient exchanges a one-use native authorization code. Identity is read
// only from Huawei's token-info endpoint, never from client-supplied claims.
type HuaweiClient struct {
	clientID, clientSecret string
	tokenURL, infoURL      string
	profileURL             string
	http                   *http.Client
}

type HuaweiIdentity struct {
	UnionID     string
	DisplayName string
	AvatarURL   string
}

func NewHuaweiClient(clientID, clientSecret string) *HuaweiClient {
	if strings.TrimSpace(clientID) == "" || strings.TrimSpace(clientSecret) == "" {
		return nil
	}
	return &HuaweiClient{
		clientID: clientID, clientSecret: clientSecret,
		tokenURL:   "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
		infoURL:    "https://oauth-api.cloud.huawei.com/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo",
		profileURL: "https://account.cloud.huawei.com/rest.php?nsp_svc=GOpen.User.getInfo",
		http: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		}},
	}
}

func (c *HuaweiClient) VerifyCode(ctx context.Context, code string) (HuaweiIdentity, error) {
	var token struct {
		AccessToken string `json:"access_token"`
		TokenType   string `json:"token_type"`
		ExpiresIn   int64  `json:"expires_in"`
		Scope       string `json:"scope"`
		Error       string `json:"error"`
	}
	if err := c.post(ctx, c.tokenURL, url.Values{
		"grant_type": {"authorization_code"}, "code": {code},
		"client_id": {c.clientID}, "client_secret": {c.clientSecret},
	}, &token); err != nil {
		return HuaweiIdentity{}, err
	}
	if token.Error != "" || token.AccessToken == "" || token.ExpiresIn <= 0 || !strings.EqualFold(token.TokenType, "Bearer") {
		return HuaweiIdentity{}, ErrInvalidHuaweiCode
	}
	var info struct {
		ClientID string `json:"client_id"`
		UnionID  string `json:"union_id"`
		ExpireIn int64  `json:"expire_in"`
		Type     *int   `json:"type"`
		Error    string `json:"error"`
	}
	if err := c.post(ctx, c.infoURL, url.Values{"access_token": {token.AccessToken}}, &info); err != nil {
		return HuaweiIdentity{}, err
	}
	if info.Error != "" || info.ClientID != c.clientID || info.Type == nil || *info.Type != 0 || info.ExpireIn <= 0 || strings.TrimSpace(info.UnionID) == "" || len(info.UnionID) > 256 {
		return HuaweiIdentity{}, ErrInvalidHuaweiCode
	}
	identity := HuaweiIdentity{UnionID: info.UnionID}
	if !slices.Contains(strings.Fields(token.Scope), "profile") {
		return identity, nil
	}
	var profile struct {
		UnionID        string `json:"unionID"`
		DisplayName    string `json:"displayName"`
		HeadPictureURL string `json:"headPictureURL"`
		Error          string `json:"error"`
	}
	// Profile data is optional; a temporary failure must not reject a verified identity.
	profileCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if err := c.post(profileCtx, c.profileURL, url.Values{
		"access_token": {token.AccessToken}, "getNickName": {"1"},
	}, &profile); err == nil && profile.Error == "" && (profile.UnionID == "" || profile.UnionID == identity.UnionID) {
		identity.DisplayName = cleanDisplayName(profile.DisplayName)
		identity.AvatarURL = validHuaweiAvatarURL(profile.HeadPictureURL)
	}
	return identity, nil
}

func validHuaweiAvatarURL(value string) string {
	if len(value) > 2048 {
		return ""
	}
	parsed, err := url.Parse(value)
	if err != nil || parsed.Scheme != "https" || parsed.Hostname() == "" || parsed.User != nil {
		return ""
	}
	return value
}

func (c *HuaweiClient) post(ctx context.Context, endpoint string, form url.Values, target any) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return errHuaweiUnavailable
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	response, err := c.http.Do(req)
	if err != nil {
		// Do not propagate upstream errors, URLs or bodies containing credentials.
		return errHuaweiUnavailable
	}
	defer response.Body.Close()
	if response.StatusCode == http.StatusBadRequest || response.StatusCode == http.StatusUnauthorized || response.StatusCode == http.StatusForbidden || response.Header.Get("NSP_STATUS") != "" {
		return ErrInvalidHuaweiCode
	}
	if response.StatusCode != http.StatusOK {
		return errHuaweiUnavailable
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 64*1024+1))
	if err != nil || len(body) > 64*1024 || json.Unmarshal(body, target) != nil {
		return errHuaweiUnavailable
	}
	return nil
}
