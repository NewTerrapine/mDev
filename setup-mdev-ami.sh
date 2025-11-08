#!/usr/bin/env bash
# setup-mdev-ami.sh
# For Amazon Linux 2 / 2023 AMI
# Installs Go, Git, GitHub CLI, creates mdev project, pushes to GitHub

set -euo pipefail

REPO="newterrapine/mdev"
DIR="mdev"
REMOTE_URL="https://github.com/${REPO}.git"

echo "=== Setting up ${REPO} on Amazon Linux AMI ==="

# 1. Update system
echo "Updating system..."
sudo yum update -y

# 2. Install Git
echo "Installing Git..."
sudo yum install -y git

# 3. Install Go 1.24+ (official binary)
echo "Installing Go 1.24..."
GO_VERSION="1.24.0"
GO_TAR="go${GO_VERSION}.linux-amd64.tar.gz"
GO_URL="https://go.dev/dl/${GO_TAR}"

if ! command -v go &> /dev/null || ! go version | grep -q "go1\.24"; then
    echo "Downloading Go ${GO_VERSION}..."
    curl -L -o /tmp/${GO_TAR} ${GO_URL}
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/${GO_TAR}
    rm /tmp/${GO_TAR}

    # Add to PATH for this session
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
fi

# Verify Go
go version

# 4. Install GitHub CLI (gh) via official script
echo "Installing GitHub CLI (gh)..."
if ! command -v gh &> /dev/null; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo yum install -y dnf  # Amazon Linux 2023 uses dnf
    sudo dnf install -y gh
fi

# 5. Authenticate to GitHub
echo "Logging in to GitHub..."
if ! gh auth status &> /dev/null; then
    gh auth login --web
fi
echo "Authenticated!"

# 6. Clone or create repo
if [ -d "$DIR" ]; then
    echo "Updating existing repo..."
    cd "$DIR"
    git pull origin main || true
    cd ..
else
    echo "Cloning repo..."
    gh repo clone "${REPO}" "$DIR" || {
        echo "Repo not found. Will create after setup."
    }
fi

cd "$DIR" || mkdir -p "$DIR" && cd "$DIR"

# 7. Initialize Go module
[ -f go.mod ] || cat > go.mod <<'EOF'
module github.com/newterrapine/mdev

go 1.24
EOF

# 8. Create directories
mkdir -p engine input render ecs modules/grid games

# 9. Write source files (same as before)
echo "Writing project files..."

cat > engine/types.go <<'EOF'
package engine

import "time"

type Tick struct {
    Delta time.Duration
    Total time.Duration
}

type Game interface {
    Load(e *Engine) error
    Update(e *Engine, t Tick) error
    Name() string
}
EOF

cat > engine/engine.go <<'EOF'
package engine

import (
    "time"

    "github.com/newterrapine/mdev/ecs"
    "github.com/newterrapine/mdev/input"
    "github.com/newterrapine/mdev/render"
)

type Engine struct {
    Entities []ecs.Entity
    Systems  []ecs.System

    Input  *input.Keyboard
    Render *render.Grid

    lastTick time.Time
    total    time.Duration

    Game Game
}

func New() *Engine {
    e := &Engine{
        Input:  input.NewKeyboard(),
        Render: render.NewGrid(40, 20),
    }
    e.ResetTiming()
    return e
}

func (e *Engine) ResetTiming() {
    e.lastTick = time.Now()
    e.total = 0
}

func (e *Engine) Run(g Game) error {
    e.Game = g
    if err := g.Load(e); err != nil {
        return err
    }

    const targetFPS = 30
    frame := time.Second / targetFPS
    ticker := time.NewTicker(frame)
    defer ticker.Stop()

    for range ticker.C {
        now := time.Now()
        delta := now.Sub(e.lastTick)
        e.total += delta
        e.lastTick = now

        e.Input.Update()
        if err := g.Update(e, Tick{Delta: delta, Total: e.total}); err != nil {
            return err
        }

        for _, sys := range e.Systems {
            sys(e.Entities)
        }

        e.Render.Clear()
        e.Render.Draw(e.Entities)
        e.Render.Present()
    }
    return nil
}
EOF

cat > input/keyboard.go <<'EOF'
package input

import (
    "bufio"
    "os"
)

type Keyboard struct{ pressed map[rune]bool }

func NewKeyboard() *Keyboard { return &Keyboard{pressed: make(map[rune]bool)} }

func (k *Keyboard) Update() {
    r := bufio.NewReader(os.Stdin)
    if ch, _, err := r.ReadRune(); err == nil {
        k.pressed[ch] = true
    }
}

func (k *Keyboard) IsPressed(r rune) bool {
    p := k.pressed[r]
    delete(k.pressed, r)
    return p
}
EOF

cat > render/grid.go <<'EOF'
package render

import (
    "fmt"
    "os"
    "strings"

    "github.com/newterrapine/mdev/ecs"
)

type Grid struct {
    W, H  int
    cells []rune
}

func NewGrid(w, h int) *Grid {
    g := &Grid{W: w, H: h}
    g.cells = make([]rune, w*h)
    g.Clear()
    return g
}

func (g *Grid) Clear() {
    for i := range g.cells {
        g.cells[i] = '.'
    }
}

func (g *Grid) Set(x, y int, r rune) {
    if x < 0 || x >= g.W || y < 0 || y >= g.H {
        return
    }
    g.cells[y*g.W+x] = r
}

func (g *Grid) Draw(ents []ecs.Entity) {
    for x := 0; x < g.W; x++ {
        g.Set(x, 0, '#')
        g.Set(x, g.H-1, '#')
    }
    for y := 0; y < g.H; y++ {
        g.Set(0, y, '#')
        g.Set(g.W-1, y, '#')
    }

    for _, e := range ents {
        if p, ok := e.Components["position"].(*ecs.Position); ok {
            if v, ok := e.Components["visual"].(*ecs.Visual); ok {
                g.Set(p.X, p.Y, v.Char)
            }
        }
    }
}

func (g *Grid) Present() {
    var sb strings.Builder
    for y := 0; y < g.H; y++ {
        for x := 0; x < g.W; x++ {
            sb.WriteRune(g.cells[y*g.W+x])
        }
        sb.WriteByte('\n')
    }
    fmt.Fprint(os.Stdout, "\033[H")
    fmt.Fprint(os.Stdout, sb.String())
}
EOF

cat > ecs/component.go <<'EOF'
package ecs

type Entity struct {
    ID         uint64
    Components map[string]any
}

type Position struct{ X, Y int }
type Visual struct{ Char rune }
type Velocity struct{ DX, DY int }
EOF

cat > ecs/system.go <<'EOF'
package ecs

type System func([]Entity)

func MovementSystem(ents []Entity) {
    for i := range ents {
        e := &ents[i]
        if v, ok := e.Components["velocity"].(*Velocity); ok {
            if p, ok := e.Components["position"].(*ecs.Position); ok {
                p.X += v.DX
                p.Y += v.DY
                if p.X < 1 { p.X = 1 }
                if p.X >= 39 { p.X = 39 }
                if p.Y < 1 { p.Y = 1 }
                if p.Y >= 19 { p.Y = 19 }
            }
        }
    }
}
EOF

cat > modules/grid/module.go <<'EOF'
package grid

import (
    "github.com/newterrapine/mdev/ecs"
    "github.com/newterrapine/mdev/engine"
)

func Register(e *engine.Engine) error {
    player := ecs.Entity{
        ID: 1,
        Components: map[string]any{
            "position": &ecs.Position{X: 20, Y: 10},
            "visual":   &ecs.Visual{Char: '@'},
            "velocity": &ecs.Velocity{},
        },
    }
    e.Entities = append(e.Entities, player)
    e.Systems = append(e.Systems, ecs.MovementSystem)
    return nil
}
EOF

cat > modules/registry.go <<'EOF'
package modules

import _ "github.com/newterrapine/mdev/modules/grid"
EOF

cat > games/simple_grid.go <<'EOF'
package games

import (
    "fmt"

    "github.com/newterrapine/mdev/engine"
    "github.com/newterrapine/mdev/ecs"
    "github.com/newterrapine/mdev/modules/grid"
)

type SimpleGrid struct{}

func (g *SimpleGrid) Name() string { return "Simple Grid Roam" }

func (g *SimpleGrid) Load(e *engine.Engine) error {
    return grid.Register(e)
}

func (g *SimpleGrid) Update(e *engine.Engine, _ engine.Tick) error {
    const speed = 1
    vel := &ecs.Velocity{}
    if e.Input.IsPressed('w') { vel.DY = -speed }
    if e.Input.IsPressed('s') { vel.DY = speed }
    if e.Input.IsPressed('a') { vel.DX = -speed }
    if e.Input.IsPressed('d') { vel.DX = speed }
    if e.Input.IsPressed('q') { return fmt.Errorf("quit") }

    for i := range e.Entities {
        ent := &e.Entities[i]
        if _, ok := ent.Components["visual"].(*ecs.Visual); ok {
            if v, ok := ent.Components["velocity"].(*ecs.Velocity); ok {
                *v = *vel
            }
        }
    }
    return nil
}
EOF

cat > main.go <<'EOF'
package main

import (
    "log"

    "github.com/newterrapine/mdev/engine"
    "github.com/newterrapine/mdev/games"
    _ "github.com/newterrapine/mdev/modules"
)

func main() {
    e := engine.New()
    game := &games.SimpleGrid{}
    if err := e.Run(game); err != nil {
        if err.Error() == "quit" {
            return
        }
        log.Fatalf("error: %v", err)
    }
}
EOF

# 10. Build
echo "Building..."
go mod tidy
go build -o mdev.bin .

# 11. Git setup & push
echo "Pushing to GitHub..."
git config --global user.name "Newterrapine" || true
git config --global user.email "newterrapine@example.com" || true

if [ ! -d ".git" ]; then
    git init
    git branch -M main
fi

git remote set-url origin "${REMOTE_URL}" 2>/dev/null || git remote add origin "${REMOTE_URL}"

# Create repo if missing
if ! gh repo view "${REPO}" &> /dev/null; then
    gh repo create "${REPO}" --public --source=. --remote=origin
fi

git add .
git commit -m "Initial commit: modular grid game" || echo "No changes"
git push -u origin main

echo "=== SUCCESS! ==="
echo "Repo: https://github.com/${REPO}"
echo "Run: ./mdev.bin"
echo "Use WASD to move @, Q to quit"
