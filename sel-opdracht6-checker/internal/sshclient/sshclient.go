// Package sshclient provides a reusable SSH connection for running commands
// on the target VM.
package sshclient

import (
	"bytes"
	"fmt"
	"net"
	"time"

	"golang.org/x/crypto/ssh"
)

type Client struct {
	conn *ssh.Client
	addr string
}

// Dial connects to host:22 with password authentication.
func Dial(host, user, pass string) (*Client, error) {
	cfg := &ssh.ClientConfig{
		User: user,
		Auth: []ssh.AuthMethod{
			ssh.Password(pass),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         5 * time.Second,
	}

	addr := net.JoinHostPort(host, "22")
	conn, err := ssh.Dial("tcp", addr, cfg)
	if err != nil {
		return nil, fmt.Errorf("ssh dial %s: %w", addr, err)
	}

	return &Client{conn: conn, addr: addr}, nil
}

// Run executes a command and returns combined stdout.
func (c *Client) Run(cmd string) (string, error) {
	sess, err := c.conn.NewSession()
	if err != nil {
		return "", fmt.Errorf("ssh session: %w", err)
	}
	defer sess.Close()

	var stdout bytes.Buffer
	sess.Stdout = &stdout
	err = sess.Run(cmd)
	return stdout.String(), err
}

// Close closes the underlying SSH connection.
func (c *Client) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

// Conn returns the underlying *ssh.Client for use with SFTP etc.
func (c *Client) Conn() *ssh.Client {
	return c.conn
}
