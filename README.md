#!/usr/bin/bash
set -e
D=modular-game
mkdir -p $D/{engine,input,render,ecs,modules/example,games}

# go.mod
cat >$D/go.mod <<'EOF'
module github.com/yourname/modular-game
go 1.21
EOF

# main.go
cat >$D/main.go <<'EOF'
package main
import (
    "log"
    "github.com/yourname/modular-game/engine"
    "github.com/yourname/modular-game/games"
)
func main() {
    e := engine.New()
    if err := e.Run(&games.ExampleGame{}); err != nil {
        if err.Error() == "quit" { return }
        log.Fatalf("Game error: %v", err)
    }
}
EOF

# engine/types.go
cat >$D/engine/types.go <<'EOF'
package engine
import "time"
type Tick struct{Delta,Total time.Duration}
type Game interface {
    Load(*Engine) error
    Update(*Engine,Tick) error
    Name() string
}
EOF

# engine/engine.go
cat >$D/engine/engine.go <<'EOF'
package engine
import (
    "time"
    "github.com/yourname/modular-game/ecs"
    "github.com/yourname/modular-game/input"
    "github.com/yourname/modular-game/render"
)
type Engine struct {
    Entities []ecs.Entity; Systems []ecs.System
    Input *input.Keyboard; Render *render.Console
    lastTick time.Time; total time.Duration; Game Game
}
func New()*Engine{e:=&Engine{Input:input.NewKeyboard(),Render:render.NewConsole()};e.ResetTiming();return e}
func(e*Engine)ResetTiming(){e.lastTick=time.Now();e.total=0}
func(e*Engine)Run(g Game)error{
    e.Game=g;if err:=g.Load(e);err!=nil{return err}
    const targetFPS=60;frameDur:=time.Second/targetFPS;ticker:=time.NewTicker(frameDur);defer ticker.Stop()
    for{select{case<-ticker.C:
        now:=time.Now();delta:=now.Sub(e.lastTick);e.total+=delta;e.lastTick=now
        e.Input.Update()
        if err:=g.Update(e,Tick{Delta:delta,Total:e.total});err!=nil{return err}
        for _,sys:=range e.Systems{sys(e.Entities)}
        e.Render.Clear();e.Render.Draw(e.Entities);e.Render.Present()
    }}}
}
EOF

# input/keyboard.go
cat >$D/input/keyboard.go <<'EOF'
package input
import("bufio";"os")
type Keyboard struct{pressed map[rune]bool}
func NewKeyboard()*Keyboard{return &Keyboard{pressed:make(map[rune]bool)}}
func(k*Keyboard)Update(){if !hasInput(){return};r:=bufio.NewReader(os.Stdin);c,_,_:=r.ReadRune();k.pressed[c]=true}
func(k*Keyboard)IsPressed(r rune)bool{p:=k.pressed[r];k.pressed[r]=false;return p}
func hasInput()bool{return true}
EOF

# render/console.go
cat >$D/render/console.go <<'EOF'
package render
import("fmt";"strings";"github.com/yourname/modular-game/ecs")
type Console struct{width,height int;buffer []rune}
func NewConsole()*Console{w,h,_:=terminalSize();if w==0{w,h=80,24};c:=&Console{width:w,height:h};c.buffer=make([]rune,w*h);c.Clear();return c}
func(c*Console)Clear(){for i:=range c.buffer{c.buffer[i]=' '}}
func(c*Console)Set(x,y int,r rune){if x<0||x>=c.width||y<0||y>=c.height{return};c.buffer[y*c.width+x]=r}
func(c*Console)Draw(ents[]ecs.Entity){for _,e:=range ents{if p,ok:=e.Components["position"].(*ecs.Position);ok{if v,ok:=e.Components["visual"].(*ecs.Visual);ok{c.Set(p.X,p.Y,v.Char)}}}}
func(c*Console)Present(){var s strings.Builder;for y:=0;y<c.height;y++{for x:=0;x<c.width;x++{s.WriteRune(c.buffer[y*c.width+x])};s.WriteByte('\n')};fmt.Print("\033[H");fmt.Print(s.String())}
func terminalSize()(int,int,error){return 0,0,nil}
EOF

# ecs/component.go
cat >$D/ecs/component.go <<'EOF'
package ecs
type Entity struct{ID uint64;Components map[string]any}
type Position struct{X,Y int}
type Visual struct{Char rune;Fg string}
type Velocity struct{DX,DY int}
EOF

# ecs/system.go
cat >$D/ecs/system.go <<'EOF'
package ecs
type System func([]Entity)
func MovementSystem(ents []Entity){for i:=range ents{e:=&ents[i];if v,ok:=e.Components["velocity"].(*Velocity);ok{if p,ok:=e.Components["position"].(*Position);ok{p.X+=v.DX;p.Y+=v.DY}}}}
EOF

# modules/registry.go
cat >$D/modules/registry.go <<'EOF'
package modules
import "github.com/yourname/modular-game/engine"
func RegisterAll(e *engine.Engine)error{
    if err:=example.Register(e);err!=nil{return err}
    return nil
}
EOF

# modules/example/module.go
cat >$D/modules/example/module.go <<'EOF'
package example
import("github.com/yourname/modular-game/ecs";"github.com/yourname/modular-game/engine")
func Register(e *engine.Engine)error{
    player:=ecs.Entity{ID:1,Components:map[string]any{
        "position":&ecs.Position{X:10,Y:10},
        "visual":&ecs.Visual{Char:'@'},
        "velocity":&ecs.Velocity{DX:0,DY:0},
    }}
    e.Entities=append(e.Entities,player)
    e.Systems=append(e.Systems,ecs.MovementSystem)
    return nil
}
EOF

# games/example_game.go
cat >$D/games/example_game.go <<'EOF'
package games
import "github.com/yourname/modular-game/engine"
type ExampleGame struct{}
func(g*ExampleGame)Name()string{return "Example Modular Game"}
func(g*ExampleGame)Load(e *engine.Engine)error{return engine.RegisterAll(e)}
func(g*ExampleGame)Update(e *engine.Engine,t engine.Tick)error{
    const s=1
    if e.Input.IsPressed('w'){setVelocity(e,0,-s)}
    if e.Input.IsPressed('s'){setVelocity(e,0,s)}
    if e.Input.IsPressed('a'){setVelocity(e,-s,0)}
    if e.Input.IsPressed('d'){setVelocity(e,s,0)}
    if e.Input.IsPressed('q'){return fmt.Errorf("quit")}
    return nil
}
func setVelocity(e *engine.Engine,dx,dy int){
    for i:=range e.Entities{ent:=&e.Entities[i]
        if v,ok:=ent.Components["velocity"].(*engine.Velocity);ok{v.DX=dx;v.DY=dy}
    }
}
EOF

echo "Folder structure and files created in $D"