#!/bin/bash
# setup-wanderer.sh
# Run: chmod +x setup-wanderer.sh && ./setup-wanderer.sh
# Creates full Wanderer roguelike with all features

set -e  # Exit on any error

echo "Creating Wanderer game structure..."

# === ROOT FILES ===
cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Wanderer</title>
  <link rel="stylesheet" href="css/style.css"/>
</head>
<body>
  <div id="game-container">
    <canvas id="game-canvas"></canvas>
    <div id="ui-overlay">
      <div id="log"></div>
      <div id="stats"></div>
      <div id="input-line">
        <input type="text" id="command-input" autofocus autocomplete="off"/>
      </div>
    </div>
  </div>

  <script type="module" src="js/main.js"></script>
</body>
</html>
EOF

# === CSS ===
mkdir -p css
cat > css/style.css << 'EOF'
* { margin:0; padding:0; box-sizing:border-box; }
html,body { height:100%; font-family: monospace; background:#111; color:#eee; }
#game-container { position:relative; width:100vw; height:100vh; }
#game-canvas { display:block; width:100%; height:100%; image-rendering:pixelated; }
#ui-overlay { position:absolute; inset:0; pointer-events:none; }
#ui-overlay > * { pointer-events:auto; }
#log { position:absolute; bottom:80px; left:10px; right:10px; height:140px; overflow-y:auto; background:rgba(0,0,0,0.6); padding:8px; font-size:14px; }
#stats { position:absolute; top:10px; left:10px; background:rgba(0,0,0,0.6); padding:6px 10px; font-size:13px; }
#input-line { position:absolute; bottom:10px; left:10px; right:10px; display:flex; }
#command-input { flex:1; background:#222; border:1px solid #555; color:#eee; padding:6px; font-size:14px; }
EOF

# === JS STRUCTURE ===
mkdir -p js/core js/world js/entities js/input js/render js/ui js/systems js/components js/ai

# === MAIN ===
cat > js/main.js << 'EOF'
import { Game } from './core/Game.js';

const canvas = document.getElementById('game-canvas');
const ctx = canvas.getContext('2d');

function resize() {
  canvas.width = canvas.clientWidth;
  canvas.height = canvas.clientHeight;
}
window.addEventListener('resize', resize);
resize();

const game = new Game(canvas, ctx);
game.start();
EOF

# === CORE ===
cat > js/core/Game.js << 'EOF'
import { World } from '../world/World.js';
import { Player } from '../entities/Player.js';
import { InputHandler } from '../input/InputHandler.js';
import { Renderer } from '../render/Renderer.js';
import { Log } from '../ui/Log.js';
import { StatsUI } from '../ui/StatsUI.js';
import { CommandParser } from '../systems/CommandParser.js';
import { SaveSystem } from '../systems/SaveSystem.js';

export class Game {
  constructor(canvas, ctx) {
    this.canvas = canvas;
    this.ctx = ctx;
    this.world = new World(128, 128);
    this.player = new Player(64, 64);
    this.world.addEntity(this.player);

    this.input = new InputHandler(canvas, document.getElementById('command-input'));
    this.renderer = new Renderer(ctx, this.world);
    this.log = new Log(document.getElementById('log'));
    this.stats = new StatsUI(document.getElementById('stats'), this.player);
    this.parser = new CommandParser(this);
    this.saveSystem = new SaveSystem(this);

    this.lastTime = 0;
    this.running = false;

    window.game = this;
  }

  start() {
    this.running = true;
    this.log.add('Wanderer started. Type **help** for commands.');
    requestAnimationFrame(this.loop.bind(this));
  }

  loop(time) {
    if (!this.running) return;
    const dt = Math.min((time - this.lastTime) / 1000, 0.1);
    this.lastTime = time;

    this.update(dt);
    this.render();

    requestAnimationFrame(this.loop.bind(this));
  }

  update(dt) {
    this.world.update(dt);
    this.input.update();
    this.stats.update();
  }

  render() {
    this.renderer.render();
  }

  executeCommand(cmd) {
    this.parser.parse(cmd);
  }
}
EOF

# === WORLD ===
cat > js/world/World.js << 'EOF'
import { TileMap } from './TileMap.js';
import { Entity } from '../entities/Entity.js';
import { Goblin } from '../entities/Goblin.js';
import { ItemEntity } from '../entities/ItemEntity.js';
import { Item } from '../components/Item.js';

export class World {
  constructor(width, height) {
    this.width = width;
    this.height = height;
    this.tileMap = new TileMap(width, height);
    this.entities = [];
    this.tileMap.generate();
    this.spawnEnemies();
    this.spawnItems();
  }

  spawnEnemies() {
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        if (this.tileMap.get(x, y) === 1 && Math.random() < 0.03) {
          this.addEntity(new Goblin(x, y));
        }
      }
    }
  }

  spawnItems() {
    const defs = [
      { name: "Health Potion", char: '!', fg: '#f00', type: 'potion', use: p => p.fighter.heal(8) },
      { name: "Iron Sword", char: '/', fg: '#ccc', type: 'weapon', bonus: { atk: 3 } },
      { name: "Leather Armor", char: '[', fg: '#840', type: 'armor', bonus: { def: 2 } },
      { name: "Apple", char: '%', fg: '#f80', type: 'food', use: p => p.fighter.heal(2) }
    ];
    for (let y = 0; y < this.height; y++) {
      for (let x = 0; x < this.width; x++) {
        if (this.tileMap.get(x, y) === 1 && Math.random() < 0.015) {
          const d = defs[Math.floor(Math.random() * defs.length)];
          const item = new Item(d.name, d.char, d.fg, d.type, d.use);
          if (d.bonus) item.bonus = d.bonus;
          this.addEntity(new ItemEntity(x, y, item));
        }
      }
    }
  }

  addEntity(ent) { if (ent instanceof Entity) this.entities.push(ent); }
  removeEntity(ent) { const i = this.entities.indexOf(ent); if (i > -1) this.entities.splice(i, 1); }
  getEntitiesAt(x, y) { return this.entities.filter(e => e.x === x && e.y === y); }

  update(dt) {
    for (const ent of this.entities.filter(e => e.isEnemy)) ent.update(dt, this);
  }

  afterPlayerMoved() { this.update(0); }
}
EOF

cat > js/world/TileMap.js << 'EOF'
export class TileMap {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.data = new Uint8Array(w * h);
  }

  get(x, y) { if (x < 0 || y < 0 || x >= this.w || y >= this.h) return 0; return this.data[y * this.w + x]; }
  set(x, y, val) { if (x < 0 || y < 0 || x >= this.w || y >= this.h) return; this.data[y * this.w + x] = val; }

  generate() {
    for (let y = 0; y < this.h; y++) {
      for (let x = 0; x < this.w; x++) {
        this.set(x, y, Math.random() < 0.44 ? 2 : 1);
      }
    }
    for (let i = 0; i < 5; i++) this.smooth();
    this.addTrees();
  }

  smooth() {
    const next = new Uint8Array(this.data);
    for (let y = 1; y < this.h - 1; y++) {
      for (let x = 1; x < this.w - 1; x++) {
        let walls = 0;
        for (let dy = -1; dy <= 1; dy++)
          for (let dx = -1; dx <= 1; dx++)
            if (this.get(x + dx, y + dy) === 2) walls++;
        next[y * this.w + x] = walls >= 5 ? 2 : 1;
      }
    }
    this.data = next;
  }

  addTrees() {
    for (let y = 0; y < this.h; y++) {
      for (let x = 0; x < this.w; x++) {
        if (this.get(x, y) === 1 && Math.random() < 0.04) this.set(x, y, 4);
      }
    }
  }
}
EOF

# === ENTITIES ===
cat > js/entities/Entity.js << 'EOF'
export class Entity {
  constructor(x, y) {
    this.x = x; this.y = y;
    this.char = '?'; this.fg = '#fff'; this.bg = null;
    this.isPlayer = false; this.isEnemy = false;
    this.fighter = null; this.ai = null;
  }

  update(dt, world) {
    if (this.ai) this.ai.update(dt, world, this);
  }
}
EOF

cat > js/entities/Player.js << 'EOF'
import { Entity } from './Entity.js';
import { Fighter } from '../components/Fighter.js';
import { Leveling } from '../components/Leveling.js';
import { ItemEntity } from './ItemEntity.js';

export class Player extends Entity {
  constructor(x, y) {
    super(x, y);
    this.char = '@'; this.fg = '#ff0';
    this.isPlayer = true;
    this.fighter = new Fighter(6, 2, 20, this);
    this.hp = this.fighter.maxHp;
    this.leveling = new Leveling();
    this.inventory = [];
    this.equipped = { weapon: null, armor: null };
  }

  addToInventory(item, world) {
    if (this.inventory.length >= 26) { world.game.log.add("Inventory full!"); return false; }
    this.inventory.push(item);
    world.game.log.add(`You pick up the ${item.name}.`);
    return true;
  }

  dropItem(index, world) {
    if (index < 0 || index >= this.inventory.length) return;
    const item = this.inventory[index];
    world.addEntity(new ItemEntity(this.x, this.y, item));
    this.inventory.splice(index, 1);
    world.game.log.add(`You drop the ${item.name}.`);
  }

  useItem(index, world) {
    if (index < 0 || index >= this.inventory.length) return;
    const item = this.inventory[index];
    if (item.use(this, world)) {
      if (item.type === 'potion' || item.type === 'food') {
        this.inventory.splice(index, 1);
        world.game.log.add(`You consume the ${item.name}.`);
      }
    } else {
      world.game.log.add(`The ${item.name} does nothing.`);
    }
  }

  equipItem(index, world) {
    if (index < 0 || index >= this.inventory.length) return;
    const item = this.inventory[index];
    if (item.type !== 'weapon' && item.type !== 'armor') { world.game.log.add(`Can't equip ${item.name}.`); return; }
    const slot = item.type; const old = this.equipped[slot];
    if (old) { old.equipped = false; this.applyEquipBonus(old, false); }
    this.equipped[slot] = item; item.equipped = true;
    this.applyEquipBonus(item, true);
    world.game.log.add(`You equip the ${item.name}.`);
  }

  applyEquipBonus(item, equip) {
    if (!item.bonus) return;
    const m = equip ? 1 : -1;
    if (item.bonus.atk) this.fighter.atk += m * item.bonus.atk;
    if (item.bonus.def) this.fighter.def += m * item.bonus.def;
  }

  move(dx, dy, world) {
    const nx = this.x + dx, ny = this.y + dy;
    const tile = world.tileMap.get(nx, ny);
    const entities = world.getEntitiesAt(nx, ny);
    const itemEnt = entities.find(e => e instanceof ItemEntity);
    if (itemEnt) {
      if (this.addToInventory(itemEnt.item, world)) world.removeEntity(itemEnt);
      world.afterPlayerMoved(); return true;
    }
    if (tile === 1 || tile === 4) {
      this.x = nx; this.y = ny;
      if (tile === 4) world.game.log.add('You push through foliage.');
      world.afterPlayerMoved(); return true;
    }
    const target = entities.find(e => e.isEnemy);
    if (target && this.fighter) { this.fighter.attack(target, world); world.afterPlayerMoved(); return true; }
    if (tile === 3) world.game.log.add('You can’t swim yet.');
    return false;
  }
}
EOF

cat > js/entities/Goblin.js << 'EOF'
import { Entity } from './Entity.js';
import { Fighter } from '../components/Fighter.js';
import { SimpleAI } from '../ai/SimpleAI.js';

export class Goblin extends Entity {
  constructor(x, y) {
    super(x, y);
    this.char = 'g'; this.fg = '#0a0';
    this.isEnemy = true;
    this.fighter = new Fighter(4, 1, 6, this);
    this.hp = this.fighter.maxHp;
    this.ai = new SimpleAI();
  }
}
EOF

cat > js/entities/ItemEntity.js << 'EOF'
import { Entity } from './Entity.js';

export class ItemEntity extends Entity {
  constructor(x, y, item) {
    super(x, y);
    this.item = item;
    this.char = item.char;
    this.fg = item.fg;
  }
}
EOF

# === COMPONENTS ===
cat > js/components/Fighter.js << 'EOF'
import { Item } from './Item.js';
import { ItemEntity } from '../entities/ItemEntity.js';

export class Fighter {
  constructor(atk, def, maxHp, owner = null) {
    this.atk = atk; this.def = def; this.maxHp = maxHp; this.hp = maxHp; this.owner = owner;
  }

  attack(target, world) {
    const damage = Math.max(1, Math.floor(this.atk - target.fighter.def / 2) + Math.floor(Math.random() * 3));
    target.fighter.hp -= damage;
    world.game.log.add(`${this.owner?.char || '@'} hits ${target.char} for ${damage} damage!`);
    if (target.fighter.hp <= 0) target.fighter.die(world);
  }

  die(world) {
    if (!this.owner) return;
    const name = this.owner.char.toUpperCase();
    world.game.log.add(`${name} is dead!`);
    if (this.owner.isPlayer) { world.game.log.add('GAME OVER'); world.game.running = false; return; }

    const player = world.entities.find(e => e.isPlayer);
    if (player?.leveling) player.leveling.gainXP(10 + Math.floor(Math.random() * 5), world);

    if (Math.random() < 0.6) {
      const loot = this.getLootDrop();
      if (loot) {
        world.addEntity(new ItemEntity(this.owner.x, this.owner.y, loot));
        world.game.log.add(`${name} drops a ${loot.name}!`);
      }
    }
    world.removeEntity(this.owner);
  }

  getLootDrop() {
    const table = [
      {c:0.4, n:"Health Potion", ch:'!', fg:'#f00', t:'potion', u:p=>p.fighter.heal(8)},
      {c:0.2, n:"Iron Sword", ch:'/', fg:'#ccc', t:'weapon', b:{atk:3}},
      {c:0.2, n:"Leather Armor", ch:'[', fg:'#840', t:'armor', b:{def:2}},
      {c:0.2, n:"Apple", ch:'%', fg:'#f80', t:'food', u:p=>p.fighter.heal(2)}
    ];
    let r = Math.random(), cum = 0;
    for (const d of table) { cum += d.c; if (r <= cum) {
      const item = new Item(d.n, d.ch, d.fg, d.t, d.u); if (d.b) item.bonus = d.b; return item;
    }}
    return null;
  }

  heal(a) { this.hp = Math.min(this.hp + a, this.maxHp); }
  levelUp(s) { this.atk += s.atk; this.def += s.def; this.maxHp += s.hp; this.hp = this.maxHp; }
}
EOF

cat > js/components/Leveling.js << 'EOF'
export class Leveling {
  constructor() { this.level = 1; this.xp = 0; }
  getThreshold(l) { return Math.floor(10 * Math.pow(1.6, l - 1)); }
  getCurrentThreshold() { return this.getThreshold(this.level); }
  getNextThreshold() { return this.getThreshold(this.level + 1); }
  gainXP(a, w) {
    this.xp += a; w.game.log.add(`+${a} XP!`);
    while (this.xp >= this.getNextThreshold()) {
      this.level++;
      const s = { hp:3, atk:1, def:0.5 };
      w.game.player.fighter.levelUp(s);
      w.game.log.add(`LEVEL UP! Lv ${this.level} (+${s.hp}HP, +${s.atk}ATK, +${s.def}DEF)`);
    }
  }
  getProgress() {
    const c = this.getCurrentThreshold(), n = this.getNextThreshold();
    return Math.max(0, Math.min(1, (this.xp - c) / (n - c)));
  }
}
EOF

cat > js/components/Item.js << 'EOF'
export class Item {
  constructor(name, char, fg, type, useEffect = null) {
    this.name = name; this.char = char; this.fg = fg; this.type = type;
    this.useEffect = useEffect; this.bonus = null; this.equipped = false;
  }
  use(player, world) {
    if (this.useEffect) { this.useEffect(player, world); return true; }
    return false;
  }
}
EOF

# === AI ===
cat > js/ai/SimpleAI.js << 'EOF'
function lineOfSight(x0,y0,x1,y1) {
  const dx=Math.abs(x1-x0), dy=Math.abs(y1-y0), sx=x0<x1?1:-1, sy=y0<y1?1:-1;
  let err=dx-dy, x=x0, y=y0, path=[];
  while(true){ path.push({x,y}); if(x===x1&&y===y1)break; const e2=2*err; if(e2>-dy){err-=dy;x+=sx;} if(e2<dx){err+=dx;y+=sy;} }
  return path;
}
export class SimpleAI {
  update(dt, world, owner) {
    const p = world.entities.find(e=>e.isPlayer); if(!p)return;
    const path = lineOfSight(owner.x,owner.y,p.x,p.y);
    let canSee=true; for(let i=1;i<path.length;i++){ if(world.tileMap.get(path[i].x,path[i].y)===2){canSee=false;break;}}
    if(!canSee||Math.hypot(owner.x-p.x,owner.y-p.y)>10)return;
    let bx=0,by=0,bd=Infinity;
    for(let dy=-1;dy<=1;dy++)for(let dx=-1;dx<=1;dx++)if(dx||dy){
      const nx=owner.x+dx,ny=owner.y+dy,t=world.tileMap.get(nx,ny);
      if(t===1||t===4){ const d=Math.hypot(nx-p.x,ny-p.y); if(d<bd){bd=d;bx=dx;by=dy;}}
    }
    const nx=owner.x+bx,ny=owner.y+by;
    const t=world.getEntitiesAt(nx,ny)[0];
    if(t&&t.isPlayer) owner.fighter.attack(t,world);
    else { owner.x=nx; owner.y=ny; }
  }
}
EOF

# === INPUT ===
cat > js/input/InputHandler.js << 'EOF'
export class InputHandler {
  constructor(canvas, inputEl) {
    this.canvas = canvas; this.inputEl = inputEl; this.keys = {};
    this.setupKeyboard(); this.setupCommandLine();
  }
  setupKeyboard() {
    window.addEventListener('keydown', e => { this.keys[e.key] = true; if(e.key==='Enter') this.inputEl.focus(); });
    window.addEventListener('keyup', e => delete this.keys[e.key]);
  }
  setupCommandLine() {
    this.inputEl.addEventListener('keydown', e => {
      if(e.key==='Enter'){ const cmd=this.inputEl.value.trim(); this.inputEl.value=''; if(cmd) window.game.executeCommand(cmd); }
    });
  }
  update() {
    const dir = {x:0,y:0};
    if(this.keys['ArrowLeft']||this.keys['h'])dir.x=-1;
    if(this.keys['ArrowRight']||this.keys['l'])dir.x=1;
    if(this.keys['ArrowUp']||this.keys['k'])dir.y=-1;
    if(this.keys['ArrowDown']||this.keys['j'])dir.y=1;
    if(dir.x||dir.y){ const p=window.game.player; p.move(dir.x,dir.y,window.game.world); }
  }
}
EOF

# === RENDER ===
cat > js/render/Renderer.js << 'EOF'
export class Renderer {
  constructor(ctx, world) { this.ctx=ctx; this.world=world; this.tileSize=16; this.camera={x:0,y:0}; }
  render() {
    const {ctx,world,tileSize}=this;
    const player=world.entities.find(e=>e.isPlayer);
    if(player){ this.camera.x=player.x; this.camera.y=player.y; }
    ctx.fillStyle='#000'; ctx.fillRect(0,0,ctx.canvas.width,ctx.canvas.height);
    const viewW=Math.ceil(ctx.canvas.width/tileSize)+2, viewH=Math.ceil(ctx.canvas.height/tileSize)+2;
    const offX=Math.floor(this.camera.x-viewW/2), offY=Math.floor(this.camera.y-viewH/2);
    for(let gy=0;gy<viewH;gy++)for(let gx=0;gx<viewW;gx++){
      const tx=offX+gx,ty=offY+gy,tile=world.tileMap.get(tx,ty);
      const sx=gx*tileSize,sy=gy*tileSize;
      ctx.font=`${tileSize}px monospace`; ctx.textAlign='center'; ctx.textBaseline='middle';
      const def=Renderer.tiles[tile]||Renderer.tiles[0];
      if(def.bg){ ctx.fillStyle=def.bg; ctx.fillRect(sx,sy,tileSize,tileSize); }
      ctx.fillStyle=def.fg; ctx.fillText(def.char,sx+tileSize/2,sy+tileSize/2);
    }
    for(const ent of world.entities){
      if(ent instanceof world.entities[0].constructor) continue; // skip player
      const sx=(ent.x-offX)*tileSize, sy=(ent.y-offY)*tileSize;
      if(sx>=-tileSize&&sx<=ctx.canvas.width&&sy>=-tileSize&&sy<=ctx.canvas.height){
        ctx.fillStyle=ent.fg;
        if(ent.bg){ ctx.fillStyle=ent.bg; ctx.fillRect(sx,sy,tileSize,tileSize); }
        ctx.fillStyle=ent.fg; ctx.fillText(ent.char,sx+tileSize/2,sy+tileSize/2);
      }
    }
    // player last
    if(player){
      const sx=(player.x-offX)*tileSize, sy=(player.y-offY)*tileSize;
      ctx.fillStyle=player.fg; ctx.fillText(player.char,sx+tileSize/2,sy+tileSize/2);
    }
  }
  static tiles={
    0:{char:' ',fg:'#000'},1:{char:'.',fg:'#666'},2:{char:'#',fg:'#999'},
    3:{char:'~',fg:'#08f',bg:'#004'},4:{char:'tree',fg:'#0b0'}
  };
}
EOF

# === UI ===
cat > js/ui/Log.js << 'EOF'
export class Log {
  constructor(el) { this.el=el; this.lines=[]; this.maxLines=30; }
  add(msg) {
    const ts=new Date().toLocaleTimeString().slice(0,5);
    this.lines.push(`[${ts}] ${msg}`);
    if(this.lines.length>this.maxLines)this.lines.shift();
    this.render();
  }
  render() {
    this.el.innerHTML=this.lines.map(l=>`<div>${l}</div>`).join('');
    this.el.scrollTop=this.el.scrollHeight;
  }
}
EOF

cat > js/ui/StatsUI.js << 'EOF'
export class StatsUI {
  constructor(el, player) { this.el=el; this.player=player; }
  update() {
    const p=this.player, l=p.leveling, prog=l.getProgress();
    const barW=20, filled=Mathfloor(prog*barW), bar='█'.repeat(filled)+'░'.repeat(barW-filled);
    const w=p.equipped.weapon?.name||"none", a=p.equipped.armor?.name||"none";
    this.el.innerHTML=`
      <strong>LV ${l.level}</strong> [${bar}] ${l.xp}/${l.getNextThreshold()}<br>
      HP: ${p.fighter.hp}/${p.fighter.maxHp}<br>
      ATK: ${p.fighter.atk} | DEF: ${Math.floor(p.fighter.def)}<br>
      Weapon: ${w}<br>Armor: ${a}<br>
      Inv: ${p.inventory.length}/26<br>Pos: ${p.x},${p.y}
    `.trim();
  }
}
EOF

# === SYSTEMS ===
cat > js/systems/CommandParser.js << 'EOF'
export class CommandParser {
  constructor(game) { this.game=game; }
  commands={
    help:()=>this.help(), look:()=>this.look(), go:(d)=>this.move(d),
    north:()=>this.move('n'), south:()=>this.move('s'), east:()=>this.move('e'), west:()=>this.move('w'),
    clear:()=>{this.game.log.el.innerHTML=''},
    inventory:()=>this.inventory(), i:()=>this.inventory(),
    use:(idx)=>this.useItem(idx), drop:(idx)=>this.dropItem(idx), equip:(idx)=>this.equipItem(idx),
    stats:()=>this.stats(), save:()=>this.game.saveSystem.save(), load:()=>this.game.saveSystem.load()
  };
  parse(raw){
    const parts=raw.toLowerCase().trim().split(/\s+/);
    const cmd=parts[0], args=parts.slice(1);
    if(this.commands[cmd]) this.commands[cmd](...args);
    else this.game.log.add(`Unknown: ${cmd}`);
  }
  help(){ const list=Object.keys(this.commands).sort().join(', '); this.game.log.add(`Commands: ${list}`); }
  look(){ const p=this.game.player, t=this.game.world.tileMap.get(p.x,p.y);
    const names={1:'floor',2:'wall',3:'water',4:'tree'}; this.game.log.add(`You stand on ${names[t]||'nothing'}.`);
  }
  move(dir){ const map={n:{x:0,y:-1},s:{x:0,y:1},e:{x:1,y:0},w:{x:-1,y:0}}; const d=map[dir];
    if(!d){this.game.log.add('Dir? (n/s/e/w)');return;} this.game.player.move(d.x,d.y,this.game.world);
  }
  inventory(){
    const p=this.game.player; if(!p.inventory.length){this.game.log.add("Empty.");return;}
    const lines=p.inventory.map((it,i)=>`${String.fromCharCode(97+i)}) ${it.name}${it.equipped?' (eq)':''}`);
    this.game.log.add("Inventory:\n"+lines.join('\n'));
  }
  useItem(idxStr){ const idx=this.parseIndex(idxStr); if(idx===null)return; this.game.player.useItem(idx,this.game.world); this.game.world.afterPlayerMoved(); }
  dropItem(idxStr){ const idx=this.parseIndex(idxStr); if(idx===null)return; this.game.player.dropItem(idx,this.game.world); }
  equipItem(idxStr){ const idx=this.parseIndex(idxStr); if(idx===null)return; this.game.player.equipItem(idx,this.game.world); }
  parseIndex(str){
    if(!str||str.length===0){this.game.log.add("Use: use/drop/equip <a-z>");return null;}
    const idx=str.toLowerCase().charCodeAt(0)-97;
    if(idx<0||idx>25||idx>=this.game.player.inventory.length){this.game.log.add("Invalid slot.");return null;}
    return idx;
  }
  stats(){
    const p=this.game.player, f=p.fighter, l=p.leveling;
    this.game.log.add(`Lv ${l.level} | XP ${l.xp}/${l.getNextThreshold()} | HP ${f.hp}/${f.maxHp} | ATK ${f.atk} | DEF ${f.def}`);
  }
}
EOF

cat > js/systems/SaveSystem.js << 'EOF'
import { Item } from '../components/Item.js';
import { Goblin } from '../entities/Goblin.js';

export class SaveSystem {
  constructor(game) { this.game = game; }
  save() {
    const data = { version:1, player:this.serializePlayer(), world:this.serializeWorld() };
    try { localStorage.setItem('wander
