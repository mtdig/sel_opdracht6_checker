// Package secrets implements OpenSSL-compatible AES-256-CBC decryption with
// PBKDF2 key derivation so the existing secrets.env.enc files (created with
// `openssl enc -aes-256-cbc -pbkdf2`) can be decrypted in pure Go without
// shelling out or linking to OpenSSL.
package secrets

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"errors"
	"fmt"
	"os"
	"strings"

	"golang.org/x/crypto/pbkdf2"
)

const (
	saltPrefix = "Salted__"
	keyLen     = 32 // AES-256
	ivLen      = aes.BlockSize
	iterations = 10000
)

// Decrypt decrypts raw OpenSSL enc'd bytes (aes-256-cbc, pbkdf2) and
// returns the plaintext.
func Decrypt(data []byte, passphrase string) ([]byte, error) {
	if len(data) < len(saltPrefix)+8 {
		return nil, errors.New("encrypted data too short")
	}

	if string(data[:8]) != saltPrefix {
		return nil, errors.New("missing OpenSSL Salted__ header")
	}

	salt := data[8:16]
	ciphertext := make([]byte, len(data)-16)
	copy(ciphertext, data[16:])

	// PBKDF2 derive key + IV (same as openssl -pbkdf2 default)
	derived := pbkdf2.Key([]byte(passphrase), salt, iterations, keyLen+ivLen, sha256.New)
	key := derived[:keyLen]
	iv := derived[keyLen : keyLen+ivLen]

	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, fmt.Errorf("aes cipher: %w", err)
	}

	if len(ciphertext)%aes.BlockSize != 0 {
		return nil, errors.New("ciphertext not a multiple of block size")
	}

	mode := cipher.NewCBCDecrypter(block, iv)
	mode.CryptBlocks(ciphertext, ciphertext)

	// Remove PKCS#7 padding
	plaintext, err := pkcs7Unpad(ciphertext)
	if err != nil {
		return nil, fmt.Errorf("bad padding (wrong passphrase?): %w", err)
	}

	return plaintext, nil
}

// DecryptFile decrypts an OpenSSL enc'd file (aes-256-cbc, pbkdf2) and
// returns the plaintext.
func DecryptFile(path, passphrase string) ([]byte, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read encrypted file: %w", err)
	}
	return Decrypt(data, passphrase)
}

// LoadSecretsFromBytes decrypts raw encrypted bytes and parses KEY=VALUE
// lines into a map.  It validates that all requiredKeys are present.
func LoadSecretsFromBytes(data []byte, passphrase string, requiredKeys []string) (map[string]string, error) {
	plain, err := Decrypt(data, passphrase)
	if err != nil {
		return nil, err
	}
	return parseSecrets(plain, requiredKeys)
}

// LoadSecrets decrypts the file and parses KEY=VALUE lines into a map.
// It validates that all requiredKeys are present.
func LoadSecrets(path, passphrase string, requiredKeys []string) (map[string]string, error) {
	plain, err := DecryptFile(path, passphrase)
	if err != nil {
		return nil, err
	}
	return parseSecrets(plain, requiredKeys)
}

func parseSecrets(plain []byte, requiredKeys []string) (map[string]string, error) {
	m := make(map[string]string)
	for _, line := range strings.Split(string(plain), "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		m[strings.TrimSpace(k)] = strings.TrimSpace(v)
	}

	for _, key := range requiredKeys {
		if m[key] == "" {
			return nil, fmt.Errorf("secret %q missing after decryption", key)
		}
	}
	return m, nil
}

func pkcs7Unpad(data []byte) ([]byte, error) {
	if len(data) == 0 {
		return nil, errors.New("empty data")
	}
	pad := int(data[len(data)-1])
	if pad == 0 || pad > aes.BlockSize || pad > len(data) {
		return nil, errors.New("invalid padding")
	}
	for i := len(data) - pad; i < len(data); i++ {
		if data[i] != byte(pad) {
			return nil, errors.New("invalid padding byte")
		}
	}
	return data[:len(data)-pad], nil
}
