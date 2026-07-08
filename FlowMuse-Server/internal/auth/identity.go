package auth

type Identity struct {
	UserID      string
	Email       string
	DisplayName string
	AvatarURL   string
	IsGuest     bool
}

func (i Identity) Username() string {
	if i.DisplayName != "" {
		return i.DisplayName
	}
	if i.Email != "" {
		return i.Email
	}
	return "匿名用户"
}
