package main

import (
	"bufio"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"

	_ "golang.org/x/image/webp"
)

const (
	minWidth    = 1500
	minRatioNum = 2
	minRatioDen = 2
)

var (
	cacheFile = filepath.Join(os.Getenv("HOME"), ".cache", "terminal-wallpapers.txt")
	imageExts = map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".webp": true}
)

func isValidImage(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()

	cfg, _, err := image.DecodeConfig(f)
	if err != nil {
		return false
	}

	if cfg.Width < minWidth {
		return false
	}
	if cfg.Width*minRatioDen < cfg.Height*minRatioNum {
		return false
	}

	return true
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "사용법: ghostty-rebuild-cache <배경화면 디렉토리>")
		os.Exit(1)
	}

	wallpaperDir := os.Args[1]
	info, err := os.Stat(wallpaperDir)
	if err != nil || !info.IsDir() {
		fmt.Fprintf(os.Stderr, "Error: 디렉토리가 존재하지 않습니다: %s\n", wallpaperDir)
		os.Exit(1)
	}

	cached := make(map[string]bool)
	removed := 0

	if data, err := os.ReadFile(cacheFile); err == nil {
		scanner := bufio.NewScanner(strings.NewReader(string(data)))
		for scanner.Scan() {
			path := scanner.Text()
			if path == "" {
				continue
			}
			if _, err := os.Stat(path); err == nil {
				cached[path] = true
			} else {
				removed++
			}
		}
	}

	entries, err := os.ReadDir(wallpaperDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	var newImages []string
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		ext := strings.ToLower(filepath.Ext(entry.Name()))
		if !imageExts[ext] {
			continue
		}
		fullPath := filepath.Join(wallpaperDir, entry.Name())
		if !cached[fullPath] {
			newImages = append(newImages, fullPath)
		}
	}

	var (
		mu    sync.Mutex
		wg    sync.WaitGroup
		added atomic.Int32
		sem   = make(chan struct{}, runtime.NumCPU())
	)

	for _, img := range newImages {
		wg.Add(1)
		go func(path string) {
			defer wg.Done()
			sem <- struct{}{}
			defer func() { <-sem }()

			if isValidImage(path) {
				mu.Lock()
				cached[path] = true
				mu.Unlock()
				n := added.Add(1)
				fmt.Printf("\r새 이미지: %d개", n)
			}
		}(img)
	}
	wg.Wait()

	if added.Load() > 0 {
		fmt.Println()
	}

	if err := os.MkdirAll(filepath.Dir(cacheFile), 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	lines := make([]string, 0, len(cached))
	for path := range cached {
		lines = append(lines, path)
	}

	if err := os.WriteFile(cacheFile, []byte(strings.Join(lines, "\n")+"\n"), 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("제거: %d개 / 추가: %d개 / 총: %d개\n", removed, added.Load(), len(cached))
}
