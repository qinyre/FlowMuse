# engine.io v2.5.0 local patch

Source: `github.com/zishang520/engine.io/v2 v2.5.0`, from the verified Go module cache. Original MIT LICENSE is preserved. Only Go sources and module metadata are included.

Change: `transports/websocket.go`, in `websocket.send`, replace the successful prepared-message `return` with `continue`. The original branch exits the whole batch after its first prepared frame and silently discards subsequent text and binary packets. Error returns are unchanged.

Regression: `go test ./internal/collab -run TestWebSocketPreparedFrameDoesNotDiscardFollowingPackets -count=1`. Against the unmodified dependency, packet 2 of 4 is missing; the patch delivers every packet in order.

The local module replacement is also copied before Docker dependency resolution. No deployment-time modification of the module cache is required. Remove this replacement after an upstream release containing this fix passes the same regression and cross-language live-ink test.
