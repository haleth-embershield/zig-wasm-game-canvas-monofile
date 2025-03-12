# Neon Geometry Tower Defense

A VERY SIMPLE tower defense game built with Zig (v0.13) targeting WebAssembly. This project showcases ZIG + CANVAS integration in a monofile simple manner.

## Description
Neon Geometry Tower Defense is a minimalist tower defense game featuring geometric shapes with a neon aesthetic. Players place geometric towers (lines, triangles, squares, etc.) to defend against waves of enemy circles. The game features a sleek black background with vibrant neon colors for maximum visual impact.

## Features
- Four unique geometric towers with different attack patterns and abilities:
  - **Line Tower**: Fast firing rate, medium damage, long range
  - **Triangle Tower**: Area splash damage affecting multiple enemies
  - **Square Tower**: Slows enemies down while dealing damage
  - **Pentagon Tower**: High damage, slow rate of fire, longest range
- Wave-based enemy progression with increasing difficulty
- Grid-based tower placement system
- Path-following enemy movement
- Visual feedback for tower placement and enemy damage
- Audio effects for game events (tower shooting, enemy hits, level completion)
- Neon visual aesthetic with bright colors on a black background

## How to Play
1. Click "Start Game" to begin
2. Select a tower type from the bottom panel
3. Click on the grid to place towers (avoid the enemy path)
4. Defend against waves of enemies
5. Earn money by defeating enemies to buy more towers
6. Survive as many waves as possible!

### Controls
- **Mouse**: Place towers and interact with UI
- **1-4 Keys**: Select different tower types
- **ESC**: Deselect current tower
- **Space**: Pause/Resume game

## Development
This project is built using Zig v0.13 targeting WebAssembly. It's designed as a simple, single-file implementation to demonstrate how Zig can be used with HTML Canvas via WebAssembly.

### Building and Running
```bash
# Build and run the project (starts a local web server)
zig build run

# Just build and deploy without running the server
zig build deploy

# Alternative: After deploying, serve with Python's HTTP server
zig build deploy
cd www
python -m http.server
```

## Project Structure
- `src/main.zig`: Main game logic and WebAssembly exports
- `assets/`: Contains HTML, CSS, JavaScript, and audio files
- `build.zig`: Build configuration for Zig