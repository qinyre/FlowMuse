package storage

import "errors"

var (
	ErrStaleSceneSnapshot = errors.New("stale scene snapshot")
	ErrRoomAlreadyExists  = errors.New("room already exists")
)
