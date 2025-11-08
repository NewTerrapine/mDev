#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# mdev - Modular Game Engine Setup Script
# Creates: github.com/newterrapine/mdev
# Go version: 1.24
# =============================================================================

PROJECT_ROOT="mdev"
MODULE_PATH="github.com/newterrapine/mdev"

echo "Creating modular game engine at ./$PROJECT_ROOT ..."

# -----------------------------------------------------------------------------
# Create directory structure
# -----------------------------------------------------------------------------
mkdir -p "$PROJECT_ROOT"/{engine,input,render,ecs,modules/example,games}

# -----------------------------------------------------------------------------
# go.mod
# -----------------------------------------------------------------------------
cat << EOF > "$PROJECT_ROOT/go.mod"
module $MODULE_PATH

go 1.24
EOF

# -----------------------------------------------------------------------------
# main.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/main.go"
package main

import (
    "log"

    "github.com/newterrapine/mdev/engine"
    "github.com/newterrapine/mdev/games"
    _ "github.com/newterrapine/mdev/modules"
)

func main() {
    e := engine.New()
    game := &games.ExampleGame{}
    if err := e.Run(game); err != nil {
        if err.Error() == "quit" {
            return
        }
        log.Fatalf("Game crashed: %v", err)
    }
}
EOF

# -----------------------------------------------------------------------------
# engine/types.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/engine/types.go"
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

# -----------------------------------------------------------------------------
# engine/engine.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/engine/engine.go"
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
    Render *render.Console

    lastTick time.Time
    total    time.Duration

    Game Game
}

func New() *Engine {
    e := &Engine{
        Input:  input.NewKeyboard(),
        Render: render.NewConsole(),
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

    const targetFPS = 60
    frameDur := time.Second / targetFPS
    ticker := time.NewTicker(frameDur)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
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
    }
}
EOF

# -----------------------------------------------------------------------------
# input/keyboard.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/input/keyboard.go"
package input

import (
    "bufio"
    "os"
)

type Keyboard struct {
    pressed map[rune]bool
}

func NewKeyboard() *Keyboard {
    return &Keyboard{pressed: make(map[rune]bool)}
}

func (k *Keyboard) Update() {
    reader := bufio.NewReader(os.Stdin)
    if r, _, err := reader.ReadRune(); err == nil {
        k.pressed[r] = true
    }
}

func (k *Keyboard) IsPressed(r rune) bool {
    pressed := k.pressed[r]
    delete(k.pressed, r)
    return pressed
}
EOF

# -----------------------------------------------------------------------------
# render/console.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/render/console.go"
package render

import (
    "fmt"
    "os"
    "strings"

    "github.com/newterrapine/mdev/ecs"
)

type Console struct {
    width, height int
    buffer        []rune
}

func NewConsole() *Console {
    w, h := 80, 24
    c := &Console{width: w, height: h}
    c.buffer = make([]rune, w*h)
    c.Clear()
    return c
}

func (c *Console) Clear() {
    for i := range c.buffer {
        c.buffer[i] = ' '
    }
}

func (c *Console) Set(x, y int, r rune) {
    if x < 0 || x >= c.width || y < 0 || y >= c.height {
        return
    }
    c.buffer[y*c.width+x] = r
}

func (c *Console) Draw(entities []ecs.Entity) {
    for _, e := range entities {
        if pos, ok := e.Components["position"].(*ecs.Position); ok {
            if vis, ok := e.Components["visual"].(*ecs.Visual); ok {
                c.Set(pos.X, pos.Y, vis.Char)
            }
        }
    }
}

func (c *Console) Present() {
    var sb strings.Builder
    for y := 0; y < c.height; y++ {
        for x := 0; x < c.width; x++ {
            sb.WriteRune(c.buffer[y*c.width+x])
        }
        sb.WriteByte('\n')
    }
    fmt.Fprint(os.Stdout, "\033[H")
    fmt.Fprint(os.Stdout, sb.String())
}
EOF

# -----------------------------------------------------------------------------
# ecs/component.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/ecs/component.go"
package ecs

type Entity struct {
    ID         uint64
    Components map[string]any
}

type Position struct {
    X, Y int
}

type Visual struct {
    Char rune
    Fg   string
}

type Velocity struct {
    DX, DY int
}
EOF

# -----------------------------------------------------------------------------
# ecs/system.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/ecs/system.go"
package ecs

type System func([]Entity)

func MovementSystem(ents []Entity) {
    for i := range ents {
        e := &ents[i]
        if vel, ok := e.Components["velocity"].(*Velocity); ok {
            if pos, ok := e.Components["position"].(*Position); ok {
                pos.X += vel.DX
                pos.Y += vel.DY
            }
        }
    }
}
EOF

# -----------------------------------------------------------------------------
# modules/registry.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/modules/registry.go"
package modules

import (
    _ "github.com/newterrapine/mdev/modules/example"
    "github.com/newterrapine/mdev/engine"
)

func RegisterAll(e *engine.Engine) error {
    return nil
}
EOF

# -----------------------------------------------------------------------------
# modules/example/module.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/modules/example/module.go"
package example

import (
    "github.com/newterrapine/mdev/ecs"
    "github.com/newterrapine/mdev/engine"
)

func Register(e *engine.Engine) error {
    player := ecs.Entity{
        ID: 1,
        Components: map[string]any{
            "position": &ecs.Position{X: 40, Y: 12},
            "visual":   &ecs.Visual{Char: '@'},
            "velocity": &ecs.Velocity{DX: 0, DY: 0},
        },
    }
    e.Entities = append(e.Entities, player)
    e.Systems = append(e.Systems, ecs.MovementSystem)
    return nil
}
EOF

# -----------------------------------------------------------------------------
# games/example_game.go
# -----------------------------------------------------------------------------
cat << 'EOF' > "$PROJECT_ROOT/games/example_game.go"
package games

import (
    "fmt"

    "github.com/newterrapine/mdev/engine"
    "github.com/newterrapine/mdev/modules/example"
)

type ExampleGame struct{}

func (g *ExampleGame) Name() string { return "mdev - Modular Game Engine" }

func (g *ExampleGame) Load(e *engine.Engine) error {
    return example.Register(e)
}

func (g *ExampleGame) Update(e *engine.Engine, t engine.Tick) error {
    const speed = 1
    if e.Input.IsPressed('w') {
        setVelocity(e, 0, -speed)
    }
    if e.Input.IsPressed('s') {
        setVelocity(e, 0, speed)
    }
    if e.Input.IsPressed('a') {
        setVelocity(e, -speed, 0)
    }
    if e.Input.IsPressed('d') {
        setVelocity(e, speed, 0)
    }
    if e.Input.IsPressed('q') {
        return fmt.Errorf("quit")
    }
    return nil
}

func setVelocity(e *engine.Engine, dx, dy int) {
    for i := range e.Entities {
        ent := &e.Entities[i]
        if v, ok := ent.Components["velocity"].(*ecs.Velocity); ok {
            v.DX = dx
            v.DY = dy
        }
    }
}
EOF

# -----------------------------------------------------------------------------
# Finalize
# -----------------------------------------------------------------------------
echo "Project created successfully!"
echo
echo "Next steps:"
echo "  cd $PROJECT_ROOT"
echo "  go run ."
echo
echo "Controls:"
echo "  WASD - move"
echo "  Q    - quit"
echo
echo "Add new modules in ./modules/yourname/ with a Register(*engine.Engine) func."
echo "Then import it in modules/registry.go with blank import."