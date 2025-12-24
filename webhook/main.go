package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
)

// StreamInfo contains information about active streams
type StreamInfo struct {
	Profile string
	Active  bool
}

var (
	activeStreams = make(map[string]*StreamInfo)
	streamsMux    sync.RWMutex
)

// PublishRequest represents the incoming webhook request from nginx
type PublishRequest struct {
	Name string `json:"name"`
	App  string `json:"app"`
}

func main() {
	http.HandleFunc("/api/v1/publish", handlePublish)
	http.HandleFunc("/api/v1/publish_done", handlePublishDone)
	http.HandleFunc("/health", handleHealth)

	port := os.Getenv("WEBHOOK_PORT")
	if port == "" {
		port = "8090"
	}

	if logFile := os.Getenv("WEBHOOK_LOG_FILE"); logFile != "" {
		if err := os.MkdirAll(filepath.Dir(logFile), 0o755); err != nil {
			log.Printf("Failed to create log directory: %v", err)
		} else if file, err := os.OpenFile(logFile, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644); err != nil {
			log.Printf("Failed to open log file: %v", err)
		} else {
			log.SetOutput(file)
		}
	}

	log.Printf("Starting webhook server on port %s", port)
	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

// handlePublish is called when a stream starts
func handlePublish(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	req, err := parsePublishRequest(r)
	if err != nil {
		log.Printf("Error parsing request: %v", err)
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	// Sanitize profile name to prevent command injection
	profile := sanitizeProfileName(req.Name)
	if profile == "" {
		log.Printf("Invalid profile name: %s", req.Name)
		http.Error(w, "Invalid profile name", http.StatusBadRequest)
		return
	}

	log.Printf("Stream publish request received for profile: %s", profile)

	// Check if stream is already active
	streamsMux.Lock()
	if stream, exists := activeStreams[profile]; exists && stream.Active {
		streamsMux.Unlock()
		log.Printf("Stream already active for profile: %s", profile)
		w.WriteHeader(http.StatusOK)
		json.NewEncoder(w).Encode(map[string]string{"status": "already_active"})
		return
	}
	activeStreams[profile] = &StreamInfo{Profile: profile, Active: true}
	streamsMux.Unlock()

	// Auth-only webhook: NGINX will execute broadcaster/hls_transcode via exec_publish
	log.Printf("Stream authorized for profile: %s (orchestration via NGINX exec_publish)", profile)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "authorized",
		"profile": profile,
	})
}

// handlePublishDone is called when a stream ends
func handlePublishDone(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	req, err := parsePublishRequest(r)
	if err != nil {
		log.Printf("Error parsing request: %v", err)
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	profile := sanitizeProfileName(req.Name)
	if profile == "" {
		log.Printf("Invalid profile name: %s", req.Name)
		http.Error(w, "Invalid profile name", http.StatusBadRequest)
		return
	}

	log.Printf("Stream publish_done request received for profile: %s", profile)

	streamsMux.Lock()
	if stream, exists := activeStreams[profile]; exists {
		stream.Active = false
	}
	streamsMux.Unlock()

	// Auth-only webhook: NGINX will execute broadcaster/hls_transcode stop via exec_publish_done
	log.Printf("Stream ended for profile: %s (cleanup via NGINX exec_publish_done)", profile)

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{
		"status":  "stopped",
		"profile": profile,
	})
}

// handleHealth provides a simple health check endpoint
func handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

// sanitizeProfileName validates and sanitizes the profile name to prevent command injection
func sanitizeProfileName(name string) string {
	// Only allow alphanumeric characters, underscores, and hyphens
	allowed := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"

	var result strings.Builder
	for _, char := range name {
		if strings.ContainsRune(allowed, char) {
			result.WriteRune(char)
		}
	}

	sanitized := result.String()
	if len(sanitized) == 0 || len(sanitized) > 50 {
		return ""
	}

	return sanitized
}

func parsePublishRequest(r *http.Request) (PublishRequest, error) {
	contentType := r.Header.Get("Content-Type")
	if strings.HasPrefix(contentType, "application/json") {
		var req PublishRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			return PublishRequest{}, err
		}
		return req, nil
	}

	if err := r.ParseForm(); err != nil {
		return PublishRequest{}, err
	}

	return PublishRequest{
		Name: r.FormValue("name"),
		App:  r.FormValue("app"),
	}, nil
}

// startBroadcaster executes the broadcaster script for the given profile
func startBroadcaster(profile string) error {
	cmd := exec.Command("/usr/local/bin/broadcaster", "--profile", profile)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	log.Printf("Executing: /usr/local/bin/broadcaster --profile %s", profile)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("broadcaster failed: %w", err)
	}

	log.Printf("Broadcaster completed for profile: %s", profile)
	return nil
}

// stopBroadcaster stops the broadcaster for the given profile
func stopBroadcaster(profile string) error {
	cmd := exec.Command("/usr/local/bin/broadcaster", "--profile", profile, "--stop")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	log.Printf("Executing: /usr/local/bin/broadcaster --profile %s --stop", profile)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("broadcaster stop failed: %w", err)
	}

	log.Printf("Broadcaster stopped for profile: %s", profile)
	return nil
}

// startHLSTranscode executes the HLS transcode script
func startHLSTranscode(profile string, action string) error {
	cmd := exec.Command("/usr/local/bin/hls_transcode", profile, action)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	log.Printf("Executing: /usr/local/bin/hls_transcode %s %s", profile, action)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("hls_transcode failed: %w", err)
	}

	log.Printf("HLS transcode %s completed for profile: %s", action, profile)
	return nil
}
