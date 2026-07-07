package storage

import (
	"context"
	"fmt"
	"io"
	"strings"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type FileStore struct {
	client *minio.Client
	bucket string
}

func NewFileStore(endpoint, accessKeyID, secretAccessKey, bucket string, useSSL bool) (*FileStore, error) {
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKeyID, secretAccessKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		return nil, err
	}
	return &FileStore{client: client, bucket: bucket}, nil
}

func (s *FileStore) EnsureBucket(ctx context.Context) error {
	exists, err := s.client.BucketExists(ctx, s.bucket)
	if err != nil {
		return err
	}
	if exists {
		return nil
	}
	return s.client.MakeBucket(ctx, s.bucket, minio.MakeBucketOptions{})
}

func (s *FileStore) Put(ctx context.Context, roomID, fileID, contentType string, body io.Reader, size int64) error {
	_, err := s.client.PutObject(ctx, s.bucket, objectName(roomID, fileID), body, size, minio.PutObjectOptions{
		ContentType: contentType,
	})
	return err
}

func (s *FileStore) Get(ctx context.Context, roomID, fileID string) (*minio.Object, minio.ObjectInfo, error) {
	object, err := s.client.GetObject(ctx, s.bucket, objectName(roomID, fileID), minio.GetObjectOptions{})
	if err != nil {
		return nil, minio.ObjectInfo{}, err
	}
	info, err := object.Stat()
	if err != nil {
		_ = object.Close()
		return nil, minio.ObjectInfo{}, err
	}
	return object, info, nil
}

func objectName(roomID, fileID string) string {
	return fmt.Sprintf("rooms/%s/files/%s", sanitizePathPart(roomID), sanitizePathPart(fileID))
}

func sanitizePathPart(value string) string {
	value = strings.ReplaceAll(value, "\\", "_")
	value = strings.ReplaceAll(value, "/", "_")
	return value
}
