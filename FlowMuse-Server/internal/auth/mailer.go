package auth

import (
	"context"
	"errors"
	"fmt"
	"strconv"

	mail "github.com/wneessen/go-mail"
)

type MailConfig struct {
	Host     string
	Port     int
	Username string
	Password string
	From     string
}

type Mailer struct {
	config MailConfig
}

func NewMailer(config MailConfig) *Mailer {
	return &Mailer{config: config}
}

func (m *Mailer) SendVerification(ctx context.Context, to, link string) error {
	return m.send(ctx, to, "验证 FlowMuse 邮箱", fmt.Sprintf("请打开以下链接完成 FlowMuse 邮箱验证：\n\n%s\n\n如果不是你本人操作，请忽略这封邮件。", link))
}

func (m *Mailer) SendPasswordReset(ctx context.Context, to, link string) error {
	return m.send(ctx, to, "重置 FlowMuse 密码", fmt.Sprintf("请打开以下链接重置 FlowMuse 密码：\n\n%s\n\n如果不是你本人操作，请忽略这封邮件。", link))
}

func (m *Mailer) send(ctx context.Context, to, subject, body string) error {
	if m.config.Host == "" || m.config.From == "" {
		return errors.New("SMTP 未配置")
	}
	message := mail.NewMsg()
	if err := message.From(m.config.From); err != nil {
		return err
	}
	if err := message.To(to); err != nil {
		return err
	}
	message.Subject(subject)
	message.SetBodyString(mail.TypeTextPlain, body)

	options := []mail.Option{
		mail.WithPort(m.config.Port),
		mail.WithTLSPolicy(mail.TLSOpportunistic),
	}
	if m.config.Username != "" {
		options = append(options, mail.WithSMTPAuth(mail.SMTPAuthPlain))
		options = append(options, mail.WithUsername(m.config.Username))
		options = append(options, mail.WithPassword(m.config.Password))
	}
	client, err := mail.NewClient(m.config.Host, options...)
	if err != nil {
		return err
	}
	done := make(chan error, 1)
	go func() {
		done <- client.DialAndSend(message)
	}()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-done:
		if err != nil {
			return fmt.Errorf("SMTP %s:%s 发送失败：%w", m.config.Host, strconv.Itoa(m.config.Port), err)
		}
		return nil
	}
}
