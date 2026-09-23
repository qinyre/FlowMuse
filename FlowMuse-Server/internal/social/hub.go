package social

import (
	"context"
	"slices"
	"sync"
	"time"

	"flowmuse/server/internal/auth"
	"github.com/zishang520/socket.io/v2/socket"
)

type connection struct {
	client        *socket.Socket
	userID, token string
}
type hint struct {
	event, id string
	users     []string
}

// ponytail: one process owns social connections; add a shared adapter before
// running multiple replicas. HTTP history remains the source of truth.
type Hub struct {
	users         *auth.UserStore
	tokens        *auth.TokenService
	mu            sync.Mutex
	clients       map[string]*connection
	notifications chan hint
	ctx           context.Context
	cancel        context.CancelFunc
	done          chan struct{}
}

func NewHub(server *socket.Server, users *auth.UserStore, tokens *auth.TokenService, enabled bool) *Hub {
	ctx, cancel := context.WithCancel(context.Background())
	h := &Hub{users: users, tokens: tokens, clients: map[string]*connection{}, notifications: make(chan hint, 128), ctx: ctx, cancel: cancel, done: make(chan struct{})}
	ns := server.Of("/social", nil)
	ns.Use(func(client *socket.Socket, next func(*socket.ExtendedError)) {
		if !enabled {
			next(socket.NewExtendedError("disabled", nil))
			return
		}
		token, err := auth.SocketToken(client)
		ctx, cancel := context.WithTimeout(h.ctx, 5*time.Second)
		defer cancel()
		var identity auth.Identity
		if err == nil {
			identity, err = users.AuthenticateToken(ctx, tokens, token)
		}
		if err != nil {
			next(socket.NewExtendedError("unauthorized", nil))
			return
		}
		client.SetData(&connection{client: client, userID: identity.UserID, token: token})
		next(nil)
	})
	ns.On("connection", func(args ...any) {
		client := args[0].(*socket.Socket)
		c := client.Data().(*connection)
		h.mu.Lock()
		count := 0
		for _, v := range h.clients {
			if v.userID == c.userID {
				count++
			}
		}
		if count >= 10 || len(h.clients) >= 2048 {
			h.mu.Unlock()
			client.Disconnect(false)
			return
		}
		h.clients[string(client.Id())] = c
		h.mu.Unlock()
		// No client-controlled subscription or write event is registered.
		client.On("disconnect", func(...any) { h.mu.Lock(); delete(h.clients, string(client.Id())); h.mu.Unlock() })
	})
	go h.run()
	return h
}

func (h *Hub) Notify(event, id string, users ...string) {
	select {
	case h.notifications <- hint{event: event, id: id, users: users}:
	default:
		// Bounded hints may coalesce under load; foreground/reconnect HTTP repairs it.
	}
}

func (h *Hub) Close() { h.cancel(); <-h.done }

func (h *Hub) run() {
	defer close(h.done)
	timer := time.NewTicker(30 * time.Second)
	defer timer.Stop()
	for {
		select {
		case <-h.ctx.Done():
			return
		case <-timer.C:
			h.deliver(hint{})
		case event := <-h.notifications:
			h.deliver(event)
		}
	}
}

func (h *Hub) deliver(event hint) {
	h.mu.Lock()
	clients := make([]*connection, 0, len(h.clients))
	for _, c := range h.clients {
		if event.event == "" || slices.Contains(event.users, c.userID) {
			clients = append(clients, c)
		}
	}
	h.mu.Unlock()
	for _, c := range clients {
		if h.ctx.Err() != nil {
			return
		}
		ctx, cancel := context.WithTimeout(h.ctx, 3*time.Second)
		_, err := h.users.AuthenticateToken(ctx, h.tokens, c.token)
		cancel()
		if err != nil {
			c.client.Emit("session.revoked", map[string]any{})
			c.client.Disconnect(false)
			continue
		}
		if event.event != "" {
			c.client.Emit(event.event, map[string]string{"id": event.id})
		}
	}
}
