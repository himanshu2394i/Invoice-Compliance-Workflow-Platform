// encryption.go
package security

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
)

// EncryptField encrypts cleartext data using AES-GCM with the provided DEK (Data Encryption Key).
func EncryptField(plaintext string, dek []byte) (string, error) {
	block, err := aes.NewCipher(dek)
	if err != nil {
		return "", fmt.Errorf("failed to create cipher block: %w", err)
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("failed to initialize GCM cipher mode: %w", err)
	}

	nonce := make([]byte, aesGCM.NonceSize())
	if _, err = io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("failed to populate random nonce bytes: %w", err)
	}

	// Seal appends the ciphertext to the nonce, keeping them grouped together.
	ciphertext := aesGCM.Seal(nonce, nonce, []byte(plaintext), nil)
	return hex.EncodeToString(ciphertext), nil
}

// DecryptField decrypts Hex encoded ciphertext using AES-GCM.
func DecryptField(encryptedHex string, dek []byte) (string, error) {
	ciphertext, err := hex.DecodeString(encryptedHex)
	if err != nil {
		return "", fmt.Errorf("failed to decode encrypted hex string: %w", err)
	}

	block, err := aes.NewCipher(dek)
	if err != nil {
		return "", fmt.Errorf("failed to create cipher block: %w", err)
	}

	aesGCM, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("failed to initialize GCM cipher mode: %w", err)
	}

	nonceSize := aesGCM.NonceSize()
	if len(ciphertext) < nonceSize {
		return "", fmt.Errorf("invalid ciphertext bounds: data shorter than nonce")
	}

	// Unpack nonce and actual encrypted block
	nonce, actualCiphertext := ciphertext[:nonceSize], ciphertext[nonceSize:]
	plaintext, err := aesGCM.Open(nil, nonce, actualCiphertext, nil)
	if err != nil {
		return "", fmt.Errorf("decryption integrity check failed: %w", err)
	}

	return string(plaintext), nil
}
