#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
#  mdev – autonomous 20×20 grid wanderer (modular, ECS‑based)
#  Run this script once → `go run .` → watch @ wander
# ------------------------------------------------------------------

PROJECT="mdev"
MOD="github.com/newterrapine/mdev"

echo "Creating project $PROJECT ..."
rm -rf "$PROJECT"
mkdir -p "$PROJECT"/{engine,render,ecs,modules/wander,games/simulation}

# ------------------------------------------------------------------
#  go.mod
# ------------------------------------------------------------------
cat > "$PROJECT/go.mod" <<'EOF'
module github.com/newterrapine/mdev

go 1.24

require golang.org/x/term v0.25.0
EOF

# ------------------------------------------------------------------
#  main.go
# ------------------------------------------------------------------
cat > "$PROJECT/main.go" <<'EOF'
package main

import (
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/newterrapine/mdev/engine"
	"github.com/newterrapine/mdev/games/simulation"
	"github.com/newterrapine/mdev/render"
	"golang.org/x/term"
)

func main() {
	// Raw terminal for clean ANSI output
	oldState, err := term.MakeRaw(int(os.Stdin.Fd()))
	if err != nil {
		log.Fatal(err)
	}
	defer term.Restore(int(os.Stdin.Fd()), oldState)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)

	eng := engine.New()
	game := simulation.NewGame()
	renderer := render.NewConsoleRenderer(game)

	eng.SetGame(game, renderer)
	eng.SetTPS(10) // 10 updates per second

	go func() {
		<-sig
		eng.Stop()
	}()

	// Run the engine in the current goroutine
	eng.Start()
}
EOF

# ------------------------------------------------------------------
#  engine/engine.go
# ------------------------------------------------------------------
cat > "$PROJECT/engine/engine.go" <<'EOF'
package engine

import (
	"sync/atomic"
	"time"

	"github.com/newterrapine/mdev/games/simulation"
	"github.com/newterrapine/mdev/render"
)

type Engine struct {
	Running  int32
	Done     chan struct{}
	Game     *simulation.Game
	Renderer render.Renderer
	TPS      int
}

func New() *Engine {
	return &Engine{
		Done: make(chan struct{}),
		TPS:  10,
	}
}

func (e *Engine) SetGame(g *simulation.Game, r render.Renderer) {
	e.Game = g
	e.Renderer = r
}

func (e *Engine) SetTPS(tps int) { e.TPS = tps }

func (e *Engine) Start() {
	atomic.StoreInt32(&e.Running, 1)
	ticker := time.NewTicker(time.Second / time.Duration(e.TPS))
	defer ticker.Stop()

	for atomic.LoadInt32(&e.Running) == 1 {
		select {
		case <-ticker.C:
			e.Game.Update()
			e.Renderer.Render()
		case <-e.Done:
			return
		}
	}
}

func (e *Engine) Stop() {
	atomic.StoreInt32(&e.Running, 0)
	close(e.Done)
}
EOF

# ------------------------------------------------------------------
#  render/renderer.go  (interface)
# ------------------------------------------------------------------
cat > "$PROJECT/render/renderer.go" <<'EOF'
package render

type Renderer interface {
	Render()
}
EOF

# ------------------------------------------------------------------
#  render/console.go
# ------------------------------------------------------------------
cat > "$PROJECT/render/console.go" <<'EOF'
package render

import (
	"fmt"
	"os"
	"strings"

	"github.com/newterrapine/mdev/games/simulation"
	"golang.org/x/term"
)

var engineTPS = 10 // patched from main; will be replaced later

type ConsoleRenderer struct {
	game *simulation.Game
}

func NewConsoleRenderer(g *simulation.Game) *ConsoleRenderer {
	return &ConsoleRenderer{game: g}
}

func (r *ConsoleRenderer) Render() {
	fmt.Print("\033[H\033[2J\033[?25l")
	defer fmt.Print("\033[?25h")

	r.drawBorder()
	r.drawGrid()
	r.drawFooter()
}

func (r *ConsoleRenderer) drawBorder() {
	line := "+" + strings.Repeat("-", simulation.Width) + "+"
	fmt.Println(line)
}

func (r *ConsoleRenderer) drawGrid() {
	grid := r.game.GetGrid()
	for y := 0; y < simulation.Height; y++ {
		row := "|"
		for x := 0; x < simulation.Width; x++ {
			row += string(grid[y][x])
		}
		row += "|"
		fmt.Println(row)
	}
}

func (r *ConsoleRenderer) drawFooter() {
	line := "+" + strings.Repeat("-", simulation.Width) + "+"
	fmt.Println(line)
	fmt.Printf("@ wandering | TPS:%d | Size:%dx%d | Ctrl+C to quit\n",
		engineTPS, simulation.Width, simulation.Height)
}
EOF

# ------------------------------------------------------------------
#  games/simulation/game.go
# ------------------------------------------------------------------
cat > "$PROJECT/games/simulation/game.go" <<'EOF'
package simulation

import (
	"github.com/newterrapine/mdev/ecs"
	"github.com/newterrapine/mdev/modules/wander"
)

const (
	Width  = 20
	Height = 20
)

type Game struct {
	Grid     [Height][Width]rune
	PlayerX  int
	PlayerY  int
	Wanderer *wander.Wanderer
	ECS      *ecs.World
}

func NewGame() *Game {
	g := &Game{
		PlayerX: Width / 2,
		PlayerY: Height / 2,
		ECS:     ecs.NewWorld(),
	}
	g.Wanderer = wander.New(g)
	g.initWalls()
	g.ResetGrid()

	// Player as ECS entity
	player := g.ECS.Spawn()
	g.ECS.AddPosition(player, g.PlayerX, g.PlayerY)
	g.ECS.AddRenderable(player, '@')
	g.ECS.AddBehavior(player, g.playerAI)

	return g
}

func (g *Game) initWalls() {
	for x := 0; x < Width; x++ {
		g.Grid[0][x] = '#'
		g.Grid[Height-1][x] = '#'
	}
	for y := 0; y < Height; y++ {
		g.Grid[y][0] = '#'
		g.Grid[y][Width-1] = '#'
	}
	// Example static tree
	g.Grid[8][10] = 'T'
}

func (g *Game) ResetGrid() {
	for y := 0; y < Height; y++ {
		for x := 0; x < Width; x++ {
			if g.Grid[y][x] != '#' && g.Grid[y][x] != 'T' {
				g.Grid[y][x] = '.'
			}
		}
	}
}

func (g *Game) Update() {
	g.ResetGrid()
	g.ECS.SystemUpdate()
	g.ECS.SystemRender(&g.Grid)
}

func (g *Game) GetGrid() [Height][Width]rune { return g.Grid }

func (g *Game) playerAI(w *ecs.World, e ecs.Entity) {
	g.Wanderer.Move()
	if pos, ok := w.GetPosition(e); ok {
		if pos.X != g.PlayerX || pos.Y != g.PlayerY {
			w.AddPosition(e, g.PlayerX, g.PlayerY)
		}
	}
}
EOF

# ------------------------------------------------------------------
#  modules/wander/wander.go
# ------------------------------------------------------------------
cat > "$PROJECT/modules/wander/wander.go" <<'EOF'
package wander

import (
	"math/rand"
	"time"

	"github.com/newterrapine/mdev/games/simulation"
)

type Wanderer struct {
	game *simulation.Game
	rng  *rand.Rand
}

func New(g *simulation.Game) *Wanderer {
	return &Wanderer{
		game: g,
		rng:  rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

func (w *Wanderer) Move() {
	dx := []int{0, 1, 0, -1}
	dy := []int{-1, 0, 1, 0}

	for attempt := 0; attempt < 10; attempt++ {
		dir := w.rng.Intn(4)
		nx := w.game.PlayerX + dx[dir]
		ny := w.game.PlayerY + dy[dir]
		if w.isValid(nx, ny) {
			w.game.PlayerX = nx
			w.game.PlayerY = ny
			return
		}
	}
}

func (w *Wanderer) isValid(x, y int) bool {
	if x < 0 || x >= simulation.Width || y < 0 || y >= simulation.Height {
		return false
	}
	t := w.game.Grid[y][x]
	return t != '#' && t != 'T'
}
EOF

# ------------------------------------------------------------------
#  ecs/ecs.go
# ------------------------------------------------------------------
cat > "$PROJECT/ecs/ecs.go" <<'EOF'
package ecs

import "github.com/newterrapine/mdev/games/simulation"

type Entity uint32

type Position struct{ X, Y int }
type Renderable struct{ Rune rune }
type Behavior struct {
	Update func(w *World, e Entity)
}

type World struct {
	nextID     Entity
	positions  map[Entity]Position
	renderable map[Entity]Renderable
	behavior   map[Entity]Behavior
}

func NewWorld() *World {
	return &World{
		positions:  make(map[Entity]Position),
		renderable: make(map[Entity]Renderable),
		behavior:   make(map[Entity]Behavior),
	}
}

func (w *World) Spawn() Entity {
	id := w.nextID
	w.nextID++
	return id
}

func (w *World) AddPosition(e Entity, x, y int)   { w.positions[e] = Position{X: x, Y: y} }
func (w *World) AddRenderable(e Entity, r rune)  { w.renderable[e] = Renderable{Rune: r} }
func (w *World) AddBehavior(e Entity, fn func(*World, Entity)) {
	w.behavior[e] = Behavior{Update: fn}
}

func (w *World) GetPosition(e Entity) (Position, bool)   { p, ok := w.positions[e]; return p, ok }
func (w *World) GetRenderable(e Entity) (Renderable, bool) { r, ok := w.renderable[e]; return r, ok }

func (w *World) SystemUpdate() {
	for e, b := range w.behavior {
		b.Update(w, e)
	}
}

func (w *World) SystemRender(grid *[simulation.Height][simulation.Width]rune) {
	for e, r := range w.renderable {
		if p, ok := w.positions[e]; ok {
			if p.X >= 0 && p.X < simulation.Width && p.Y >= 0 && p.Y < simulation.Height {
				grid[p.Y][p.X] = r.Rune
			}
		}
	}
}
EOF

# ------------------------------------------------------------------
#  Finalise
# ------------------------------------------------------------------
cd "$PROJECT"
echo "Running go mod tidy ..."
go mod tidy

echo ""
echo "=== ALL SET ==="
echo "Run the simulation with:"
echo "  cd $PROJECT && go run ."
echo "Press Ctrl+C to stop."
echo ""

# Optional: run it immediately
read -p "Run now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
	go run .
fi