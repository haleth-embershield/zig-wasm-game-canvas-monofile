// Neon Geometry Tower Defense
// A tower defense game built with Zig v0.13 targeting WebAssembly

const std = @import("std");

// WASM imports for browser interaction
extern "env" fn consoleLog(ptr: [*]const u8, len: usize) void;
extern "env" fn clearCanvas() void;
extern "env" fn drawRect(x: f32, y: f32, width: f32, height: f32, r: u8, g: u8, b: u8) void;

// Additional drawing functions we'll need to implement in JavaScript
extern "env" fn drawCircle(x: f32, y: f32, radius: f32, r: u8, g: u8, b: u8, fill: bool) void;
extern "env" fn drawLine(x1: f32, y1: f32, x2: f32, y2: f32, thickness: f32, r: u8, g: u8, b: u8) void;
extern "env" fn drawTriangle(x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32, r: u8, g: u8, b: u8, fill: bool) void;
extern "env" fn drawText(x: f32, y: f32, text_ptr: [*]const u8, text_len: usize, size: f32, r: u8, g: u8, b: u8) void;

// Audio functions
extern "env" fn playEnemyHitSound() void;
extern "env" fn playLevelCompleteSound() void;
extern "env" fn playLevelFailSound() void;
extern "env" fn playTowerShootSound() void;
extern "env" fn playEnemyExplosionSound() void;

// Game constants
const GRID_SIZE: f32 = 40;
const GRID_COLS: u32 = 20;
const GRID_ROWS: u32 = 15;

// Game state enum
const GameState = enum {
    Menu,
    Playing,
    Paused,
    GameOver,
};

// Tower types
const TowerType = enum {
    None,
    Line, // Straight line attack
    Triangle, // Area damage
    Square, // Slowing effect
    Pentagon, // High damage
};

// Tower structure
const Tower = struct {
    x: f32,
    y: f32,
    type: TowerType,
    level: u32,
    cooldown: f32,
    cooldown_max: f32,
    range: f32,
    damage: f32,
    cost: u32,

    // Create a new tower
    fn init(x: f32, y: f32, tower_type: TowerType) Tower {
        return switch (tower_type) {
            .None => unreachable,
            .Line => Tower{
                .x = x,
                .y = y,
                .type = tower_type,
                .level = 1,
                .cooldown = 0,
                .cooldown_max = 0.5,
                .range = 150,
                .damage = 10,
                .cost = 50,
            },
            .Triangle => Tower{
                .x = x,
                .y = y,
                .type = tower_type,
                .level = 1,
                .cooldown = 0,
                .cooldown_max = 1.0,
                .range = 100,
                .damage = 15,
                .cost = 100,
            },
            .Square => Tower{
                .x = x,
                .y = y,
                .type = tower_type,
                .level = 1,
                .cooldown = 0,
                .cooldown_max = 0.8,
                .range = 120,
                .damage = 5,
                .cost = 75,
            },
            .Pentagon => Tower{
                .x = x,
                .y = y,
                .type = tower_type,
                .level = 1,
                .cooldown = 0,
                .cooldown_max = 1.5,
                .range = 200,
                .damage = 30,
                .cost = 150,
            },
        };
    }

    // Update tower cooldown
    fn update(self: *Tower, delta_time: f32) void {
        if (self.cooldown > 0) {
            self.cooldown -= delta_time;
            if (self.cooldown < 0) {
                self.cooldown = 0;
            }
        }
    }

    // Check if tower can attack
    fn canAttack(self: Tower) bool {
        return self.cooldown <= 0;
    }

    // Reset cooldown after attack
    fn resetCooldown(self: *Tower) void {
        self.cooldown = self.cooldown_max;
    }
};

// Enemy structure
const Enemy = struct {
    x: f32,
    y: f32,
    radius: f32,
    health: f32,
    max_health: f32,
    speed: f32,
    value: u32,
    active: bool,
    path_index: usize,
    hit_flash: f32, // Add a visual indicator when enemy is hit

    // Create a new enemy
    fn init(x: f32, y: f32, health: f32, speed: f32, value: u32) Enemy {
        return Enemy{
            .x = x,
            .y = y,
            .radius = 15,
            .health = health,
            .max_health = health,
            .speed = speed,
            .value = value,
            .active = true,
            .path_index = 0,
            .hit_flash = 0,
        };
    }

    // Update enemy position along path
    fn update(self: *Enemy, delta_time: f32, path: []const PathPoint) bool {
        if (!self.active) return false;

        // Update hit flash effect
        if (self.hit_flash > 0) {
            self.hit_flash -= delta_time;
            if (self.hit_flash < 0) self.hit_flash = 0;
        }

        if (self.path_index >= path.len) {
            return true; // Reached end of path
        }

        const target = path[self.path_index];
        const dx = target.x - self.x;
        const dy = target.y - self.y;
        const distance = @sqrt(dx * dx + dy * dy);

        if (distance < 5) {
            // Reached waypoint, move to next
            self.path_index += 1;
            if (self.path_index >= path.len) {
                return true; // Reached end of path
            }
        } else {
            // Move toward waypoint
            const move_distance = self.speed * delta_time;
            const ratio = move_distance / distance;
            self.x += dx * ratio;
            self.y += dy * ratio;
        }

        return false;
    }

    // Take damage and check if dead
    fn takeDamage(self: *Enemy, amount: f32) bool {
        self.health -= amount;
        self.hit_flash = 0.2; // Flash for 0.2 seconds when hit

        // Play enemy hit sound
        playEnemyHitSound();

        // Log damage for debugging
        var damage_buf: [64]u8 = undefined;
        const damage_msg = std.fmt.bufPrint(&damage_buf, "Enemy took {d:.1} damage, health: {d:.1}/{d:.1}", .{ amount, self.health, self.max_health }) catch "Enemy took damage";
        logString(damage_msg);

        return self.health <= 0;
    }
};

// Path point structure
const PathPoint = struct {
    x: f32,
    y: f32,
};

// Projectile structure
const Projectile = struct {
    x: f32,
    y: f32,
    target_x: f32,
    target_y: f32,
    speed: f32,
    damage: f32,
    active: bool,
    tower_type: TowerType,
    prev_x: f32, // Track previous position for better collision detection
    prev_y: f32,

    fn init(x: f32, y: f32, target_x: f32, target_y: f32, damage: f32, tower_type: TowerType) Projectile {
        return Projectile{
            .x = x,
            .y = y,
            .target_x = target_x,
            .target_y = target_y,
            .speed = 300,
            .damage = damage,
            .active = true,
            .tower_type = tower_type,
            .prev_x = x,
            .prev_y = y,
        };
    }

    fn update(self: *Projectile, delta_time: f32) bool {
        if (!self.active) return false;

        // Store previous position
        self.prev_x = self.x;
        self.prev_y = self.y;

        const dx = self.target_x - self.x;
        const dy = self.target_y - self.y;
        const distance = @sqrt(dx * dx + dy * dy);

        if (distance < 5) {
            return true; // Hit target
        }

        const move_distance = self.speed * delta_time;
        const ratio = move_distance / distance;
        self.x += dx * ratio;
        self.y += dy * ratio;

        return false;
    }
};

// Game data structure
const GameData = struct {
    state: GameState,
    towers: [100]Tower,
    tower_count: usize,
    enemies: [100]Enemy,
    enemy_count: usize,
    projectiles: [200]Projectile,
    projectile_count: usize,
    path: [20]PathPoint,
    path_length: usize,
    selected_tower_type: TowerType,
    money: u32,
    lives: u32,
    wave: u32,
    wave_timer: f32,
    spawn_timer: f32,
    enemies_to_spawn: u32,

    fn init() GameData {
        var data = GameData{
            .state = GameState.Menu,
            .towers = undefined,
            .tower_count = 0,
            .enemies = undefined,
            .enemy_count = 0,
            .projectiles = undefined,
            .projectile_count = 0,
            .path = undefined,
            .path_length = 0,
            .selected_tower_type = TowerType.Line,
            .money = 1000,
            .lives = 20,
            .wave = 0,
            .wave_timer = 0,
            .spawn_timer = 0,
            .enemies_to_spawn = 0,
        };

        // Initialize default path
        data.path[0] = PathPoint{ .x = 0, .y = 120 };
        data.path[1] = PathPoint{ .x = 200, .y = 120 };
        data.path[2] = PathPoint{ .x = 200, .y = 280 };
        data.path[3] = PathPoint{ .x = 400, .y = 280 };
        data.path[4] = PathPoint{ .x = 400, .y = 120 };
        data.path[5] = PathPoint{ .x = 600, .y = 120 };
        data.path[6] = PathPoint{ .x = 600, .y = 400 };
        data.path[7] = PathPoint{ .x = 800, .y = 400 };
        data.path_length = 8;

        return data;
    }

    fn startWave(self: *GameData) void {
        self.wave += 1;
        self.enemies_to_spawn = 5 + self.wave * 2;
        self.spawn_timer = 0;
        logString("Wave started!");
    }

    fn spawnEnemy(self: *GameData) void {
        if (self.enemy_count >= self.enemies.len) return;

        const health = 20.0 + @as(f32, @floatFromInt(self.wave)) * 5.0;
        const speed = 50.0 + @as(f32, @floatFromInt(self.wave)) * 2.0;
        const value = 5 + self.wave;

        self.enemies[self.enemy_count] = Enemy.init(self.path[0].x, self.path[0].y, health, speed, value);
        self.enemy_count += 1;
        self.enemies_to_spawn -= 1;
    }

    fn addTower(self: *GameData, x: f32, y: f32, tower_type: TowerType) bool {
        if (self.tower_count >= self.towers.len) return false;

        const tower = Tower.init(x, y, tower_type);

        // Check if we can afford it
        if (self.money < tower.cost) return false;

        // Check if tower placement is valid (not on path)
        for (self.path[0..self.path_length]) |point| {
            const dx = point.x - x;
            const dy = point.y - y;
            const distance = @sqrt(dx * dx + dy * dy);
            if (distance < GRID_SIZE) return false;
        }

        // Check if tower placement overlaps with another tower
        for (self.towers[0..self.tower_count]) |other| {
            const dx = other.x - x;
            const dy = other.y - y;
            const distance = @sqrt(dx * dx + dy * dy);
            if (distance < GRID_SIZE) return false;
        }

        self.towers[self.tower_count] = tower;
        self.tower_count += 1;
        self.money -= tower.cost;

        return true;
    }

    fn addProjectile(self: *GameData, x: f32, y: f32, target_x: f32, target_y: f32, damage: f32, tower_type: TowerType) void {
        if (self.projectile_count >= self.projectiles.len) return;

        self.projectiles[self.projectile_count] = Projectile.init(x, y, target_x, target_y, damage, tower_type);
        self.projectile_count += 1;
    }
};

// Global state
var canvas_width: f32 = 800;
var canvas_height: f32 = 600;
var game: GameData = undefined;

// Helper to log strings to browser console
fn logString(msg: []const u8) void {
    consoleLog(msg.ptr, msg.len);
}

// Initialize the WASM module
export fn init(width: f32, height: f32) void {
    canvas_width = width;
    canvas_height = height;

    // Initialize game data
    game = GameData.init();

    logString("Tower Defense initialized");
}

// Start or reset the game
export fn resetGame() void {
    game = GameData.init();
    game.state = GameState.Playing;
    logString("Game reset");
}

// Update animation frame
export fn update(delta_time: f32) void {
    if (game.state != GameState.Playing) {
        drawMenu();
        return;
    }

    // Clear canvas
    clearCanvas();

    // Draw grid and path
    drawGrid();
    drawPath();

    // Update game logic
    updateGame(delta_time);

    // Draw game elements
    drawTowers();
    drawEnemies();
    drawProjectiles();
    drawUI();
}

// Handle mouse click
export fn handleClick(x: f32, y: f32) void {
    if (game.state == GameState.Menu) {
        // Start game if in menu
        game.state = GameState.Playing;
        return;
    }

    if (game.state == GameState.Paused) {
        // Resume game if paused
        game.state = GameState.Playing;
        return;
    }

    if (game.state == GameState.GameOver) {
        // Reset game if game over
        resetGame();
        return;
    }

    // Handle tower placement
    if (game.selected_tower_type != TowerType.None) {
        // Snap to grid
        const grid_x = @floor(x / GRID_SIZE) * GRID_SIZE + GRID_SIZE / 2;
        const grid_y = @floor(y / GRID_SIZE) * GRID_SIZE + GRID_SIZE / 2;

        if (game.addTower(grid_x, grid_y, game.selected_tower_type)) {
            logString("Tower placed");
        } else {
            logString("Cannot place tower here");
        }
    }
}

// Update game logic
fn updateGame(delta_time: f32) void {
    // Update wave timer
    if (game.enemies_to_spawn == 0 and game.enemy_count == 0) {
        // If this is the first frame after all enemies are defeated, play level complete sound
        if (game.wave_timer == 0 and game.wave > 0) {
            playLevelCompleteSound();
        }

        game.wave_timer += delta_time;

        // Log the timer for debugging
        if (@mod(@floor(game.wave_timer * 10.0), 10.0) == 0) {
            var timer_buf: [32]u8 = undefined;
            const timer_msg = std.fmt.bufPrint(&timer_buf, "Wave timer: {d:.1}", .{game.wave_timer}) catch "Wave timer update";
            logString(timer_msg);
        }

        if (game.wave_timer >= 5.0) {
            logString("Starting next wave!");
            game.wave_timer = 0;
            game.startWave();

            // We no longer play level complete sound here since we play it when the level is finished
        }
    }

    // Spawn enemies
    if (game.enemies_to_spawn > 0) {
        game.spawn_timer += delta_time;
        if (game.spawn_timer > 1.0) {
            game.spawn_timer = 0;
            game.spawnEnemy();
        }
    }

    // Update towers
    for (game.towers[0..game.tower_count]) |*tower| {
        tower.update(delta_time);

        // Check for targets if tower can attack
        if (tower.canAttack()) {
            var closest_enemy: ?*Enemy = null;
            var closest_distance: f32 = tower.range;

            for (game.enemies[0..game.enemy_count]) |*enemy| {
                if (!enemy.active) continue;

                const dx = enemy.x - tower.x;
                const dy = enemy.y - tower.y;
                const distance = @sqrt(dx * dx + dy * dy);

                if (distance < closest_distance) {
                    closest_enemy = enemy;
                    closest_distance = distance;
                }
            }

            if (closest_enemy) |enemy| {
                // Create projectile
                game.addProjectile(tower.x, tower.y, enemy.x, enemy.y, tower.damage, tower.type);
                tower.resetCooldown();

                // Play tower shoot sound
                playTowerShootSound();
            }
        }
    }

    // Update enemies
    var i: usize = 0;
    while (i < game.enemy_count) {
        const reached_end = game.enemies[i].update(delta_time, game.path[0..game.path_length]);

        if (reached_end) {
            // Enemy reached the end, lose a life
            game.lives -= 1;

            // Remove enemy
            game.enemies[i] = game.enemies[game.enemy_count - 1];
            game.enemy_count -= 1;

            // Check game over
            if (game.lives == 0) {
                game.state = GameState.GameOver;
                logString("Game Over!");

                // Play level fail sound when game is over
                playLevelFailSound();
            }
        } else {
            i += 1;
        }
    }

    // Update projectiles
    i = 0;
    while (i < game.projectile_count) {
        const hit = game.projectiles[i].update(delta_time);
        var hit_enemy = false;

        // Check for collision with enemies regardless of whether the projectile reached its target
        var j: usize = 0;
        while (j < game.enemy_count) {
            const enemy = &game.enemies[j];
            if (!enemy.active) {
                j += 1;
                continue;
            }

            // Check if projectile is close to enemy
            const dx = enemy.x - game.projectiles[i].x;
            const dy = enemy.y - game.projectiles[i].y;
            const distance = @sqrt(dx * dx + dy * dy);

            // Also check if projectile crossed over the enemy between frames
            const prev_dx = enemy.x - game.projectiles[i].prev_x;
            const prev_dy = enemy.y - game.projectiles[i].prev_y;
            const prev_distance = @sqrt(prev_dx * prev_dx + prev_dy * prev_dy);

            // If projectile is within enemy radius or crossed over enemy between frames
            if (distance < enemy.radius or
                (distance < enemy.radius * 2 and prev_distance < enemy.radius * 2 and
                distance + prev_distance < @sqrt((game.projectiles[i].x - game.projectiles[i].prev_x) * (game.projectiles[i].x - game.projectiles[i].prev_x) +
                (game.projectiles[i].y - game.projectiles[i].prev_y) * (game.projectiles[i].y - game.projectiles[i].prev_y)) * 1.5))
            {

                // Apply damage based on tower type
                const damage = game.projectiles[i].damage;

                // Log hit for debugging
                var hit_buf: [64]u8 = undefined;
                const hit_msg = std.fmt.bufPrint(&hit_buf, "Projectile hit enemy at ({d:.1}, {d:.1}), distance: {d:.1}", .{ enemy.x, enemy.y, distance }) catch "Projectile hit enemy";
                logString(hit_msg);

                // Triangle towers do area damage
                if (game.projectiles[i].tower_type == TowerType.Triangle) {
                    // Apply area damage to all enemies within range
                    var k: usize = 0;
                    const splash_radius: f32 = 50.0;
                    while (k < game.enemy_count) {
                        const splash_enemy = &game.enemies[k];
                        if (!splash_enemy.active) {
                            k += 1;
                            continue;
                        }

                        const splash_dx = splash_enemy.x - game.projectiles[i].target_x;
                        const splash_dy = splash_enemy.y - game.projectiles[i].target_y;
                        const splash_distance = @sqrt(splash_dx * splash_dx + splash_dy * splash_dy);

                        if (splash_distance < splash_radius) {
                            // Calculate damage based on distance from center (more damage at center)
                            const splash_damage = damage * (1.0 - splash_distance / splash_radius);
                            const splash_killed = splash_enemy.takeDamage(splash_damage);

                            if (splash_killed) {
                                // Play explosion sound when enemy dies
                                playEnemyExplosionSound();

                                // Add money for kill
                                game.money += splash_enemy.value;

                                // Remove enemy
                                game.enemies[k] = game.enemies[game.enemy_count - 1];
                                game.enemy_count -= 1;

                                // Adjust index if we're not at the end
                                if (k < game.enemy_count) {
                                    continue;
                                }
                            }
                        }
                        k += 1;
                    }
                } else if (game.projectiles[i].tower_type == TowerType.Square) {
                    // Square towers slow enemies
                    enemy.speed *= 0.8;
                    if (enemy.takeDamage(damage)) {
                        // Play explosion sound when enemy dies
                        playEnemyExplosionSound();

                        // Add money for kill
                        game.money += enemy.value;

                        // Remove enemy
                        game.enemies[j] = game.enemies[game.enemy_count - 1];
                        game.enemy_count -= 1;

                        // Adjust index if we're not at the end
                        if (j < game.enemy_count) {
                            continue;
                        }
                    }
                } else {
                    // Normal damage for other tower types
                    if (enemy.takeDamage(damage)) {
                        // Play explosion sound when enemy dies
                        playEnemyExplosionSound();

                        // Add money for kill
                        game.money += enemy.value;

                        // Remove enemy
                        game.enemies[j] = game.enemies[game.enemy_count - 1];
                        game.enemy_count -= 1;

                        // Adjust index if we're not at the end
                        if (j < game.enemy_count) {
                            continue;
                        }
                    }
                }

                hit_enemy = true;
                break;
            }
            j += 1;
        }

        // Remove projectile if it hit its target or hit an enemy
        if (hit or hit_enemy) {
            game.projectiles[i] = game.projectiles[game.projectile_count - 1];
            game.projectile_count -= 1;
        } else {
            // Also remove projectile if it goes off screen
            if (game.projectiles[i].x < -20 or game.projectiles[i].x > canvas_width + 20 or
                game.projectiles[i].y < -20 or game.projectiles[i].y > canvas_height + 20)
            {
                game.projectiles[i] = game.projectiles[game.projectile_count - 1];
                game.projectile_count -= 1;
            } else {
                i += 1;
            }
        }
    }
}

// Draw the game grid
fn drawGrid() void {
    // Draw grid lines
    for (0..GRID_COLS + 1) |i| {
        const x = @as(f32, @floatFromInt(i)) * GRID_SIZE;
        drawLine(x, 0, x, canvas_height, 1, 20, 20, 20);
    }

    for (0..GRID_ROWS + 1) |i| {
        const y = @as(f32, @floatFromInt(i)) * GRID_SIZE;
        drawLine(0, y, canvas_width, y, 1, 20, 20, 20);
    }
}

// Draw the enemy path
fn drawPath() void {
    // Draw path segments
    for (1..game.path_length) |i| {
        const start = game.path[i - 1];
        const end = game.path[i];
        drawLine(start.x, start.y, end.x, end.y, 20, 30, 30, 80);
    }

    // Draw path points
    for (game.path[0..game.path_length]) |point| {
        drawCircle(point.x, point.y, 10, 40, 40, 120, true);
    }
}

// Draw all towers
fn drawTowers() void {
    for (game.towers[0..game.tower_count]) |tower| {
        const size: f32 = 15;

        // Draw tower based on type
        switch (tower.type) {
            .Line => {
                // Draw line tower (vertical and horizontal lines)
                drawLine(tower.x - size, tower.y, tower.x + size, tower.y, 2, 0, 255, 255);
                drawLine(tower.x, tower.y - size, tower.x, tower.y + size, 2, 0, 255, 255);
            },
            .Triangle => {
                // Draw triangle tower
                drawTriangle(tower.x, tower.y - size, tower.x - size, tower.y + size, tower.x + size, tower.y + size, 255, 0, 255, false);
            },
            .Square => {
                // Draw square tower
                drawLine(tower.x - size, tower.y - size, tower.x + size, tower.y - size, 2, 255, 255, 0);
                drawLine(tower.x + size, tower.y - size, tower.x + size, tower.y + size, 2, 255, 255, 0);
                drawLine(tower.x + size, tower.y + size, tower.x - size, tower.y + size, 2, 255, 255, 0);
                drawLine(tower.x - size, tower.y + size, tower.x - size, tower.y - size, 2, 255, 255, 0);
            },
            .Pentagon => {
                // Draw pentagon tower (simplified as a circle for now)
                drawCircle(tower.x, tower.y, size, 255, 0, 0, false);
            },
            .None => {},
        }

        // We no longer show range indicators when towers are shooting
        // This makes the gameplay less cluttered
    }
}

// Draw all enemies
fn drawEnemies() void {
    for (game.enemies[0..game.enemy_count]) |enemy| {
        if (!enemy.active) continue;

        // Draw enemy circle - flash white when hit
        if (enemy.hit_flash > 0) {
            // Flash white when hit
            const flash_intensity = @as(u8, @intFromFloat(255.0 * (enemy.hit_flash / 0.2)));
            drawCircle(enemy.x, enemy.y, enemy.radius, 255, flash_intensity, flash_intensity, true);
        } else {
            // Normal red color
            drawCircle(enemy.x, enemy.y, enemy.radius, 255, 0, 0, true);
        }

        // Draw health bar background (black)
        const health_bar_width = enemy.radius * 2.0;
        const health_bar_height = 5.0;
        const health_x = enemy.x - enemy.radius;
        const health_y = enemy.y - enemy.radius - 10;
        drawRect(health_x, health_y, health_bar_width, health_bar_height, 0, 0, 0);

        // Draw health bar (green to red gradient based on health percentage)
        const health_percent = enemy.health / enemy.max_health;
        const health_width = health_bar_width * health_percent;

        // Color shifts from green to red as health decreases
        const r: u8 = @intFromFloat(255.0 * (1.0 - health_percent));
        const g: u8 = @intFromFloat(255.0 * health_percent);

        drawRect(health_x, health_y, health_width, health_bar_height, r, g, 0);

        // Draw health bar border
        drawLine(health_x, health_y, health_x + health_bar_width, health_y, 1, 255, 255, 255);
        drawLine(health_x + health_bar_width, health_y, health_x + health_bar_width, health_y + health_bar_height, 1, 255, 255, 255);
        drawLine(health_x + health_bar_width, health_y + health_bar_height, health_x, health_y + health_bar_height, 1, 255, 255, 255);
        drawLine(health_x, health_y + health_bar_height, health_x, health_y, 1, 255, 255, 255);
    }
}

// Draw all projectiles
fn drawProjectiles() void {
    for (game.projectiles[0..game.projectile_count]) |projectile| {
        if (!projectile.active) continue;

        // Draw projectile based on tower type
        switch (projectile.tower_type) {
            .Line => {
                drawCircle(projectile.x, projectile.y, 3, 0, 255, 255, true);
            },
            .Triangle => {
                drawCircle(projectile.x, projectile.y, 4, 255, 0, 255, true);
            },
            .Square => {
                drawCircle(projectile.x, projectile.y, 3, 255, 255, 0, true);
            },
            .Pentagon => {
                drawCircle(projectile.x, projectile.y, 5, 255, 0, 0, true);
            },
            .None => {},
        }
    }
}

// Draw game UI
fn drawUI() void {
    // Draw money
    var money_text_buf: [32]u8 = undefined;
    const money_text = std.fmt.bufPrint(&money_text_buf, "Money: {d}", .{game.money}) catch "Money: ???";
    drawText(10, 20, money_text.ptr, money_text.len, 16, 255, 255, 0);

    // Draw lives
    var lives_text_buf: [32]u8 = undefined;
    const lives_text = std.fmt.bufPrint(&lives_text_buf, "Lives: {d}", .{game.lives}) catch "Lives: ???";
    drawText(10, 40, lives_text.ptr, lives_text.len, 16, 0, 255, 0);

    // Draw wave
    var wave_text_buf: [32]u8 = undefined;
    const wave_text = std.fmt.bufPrint(&wave_text_buf, "Wave: {d}", .{game.wave}) catch "Wave: ???";
    drawText(10, 60, wave_text.ptr, wave_text.len, 16, 0, 255, 255);

    // Draw next wave timer if applicable
    if (game.enemies_to_spawn == 0 and game.enemy_count == 0) {
        var timer_text_buf: [32]u8 = undefined;
        const time_left = 5.0 - game.wave_timer;
        const timer_text = std.fmt.bufPrint(&timer_text_buf, "Next wave in: {d:.1}", .{time_left}) catch "Next wave soon";
        drawText(canvas_width / 2 - 100, 30, timer_text.ptr, timer_text.len, 20, 255, 255, 255);
    }

    // Draw selected tower info
    if (game.selected_tower_type != TowerType.None) {
        const tower = Tower.init(0, 0, game.selected_tower_type);
        var tower_text_buf: [64]u8 = undefined;
        const tower_text = std.fmt.bufPrint(&tower_text_buf, "Selected: {s} (Cost: {d})", .{ @tagName(game.selected_tower_type), tower.cost }) catch "Selected Tower";
        drawText(canvas_width - 300, 20, tower_text.ptr, tower_text.len, 16, 255, 255, 255);
    }

    // Draw game over message if applicable
    if (game.state == GameState.GameOver) {
        const game_over_text = "GAME OVER - Click to restart";
        drawText(canvas_width / 2 - 150, canvas_height / 2, game_over_text.ptr, game_over_text.len, 30, 255, 0, 0);
    }
}

// Draw menu screen
fn drawMenu() void {
    // Clear canvas
    clearCanvas();

    // Draw title
    const title_text = "NEON GEOMETRY TOWER DEFENSE";
    drawText(canvas_width / 2 - 250, canvas_height / 2 - 50, title_text.ptr, title_text.len, 30, 0, 255, 255);

    // Draw start instruction
    const start_text = "Click to Start";
    drawText(canvas_width / 2 - 80, canvas_height / 2 + 50, start_text.ptr, start_text.len, 20, 255, 255, 255);
}

// Check if a tower can be placed at the given coordinates
export fn canPlaceTower(x: f32, y: f32) bool {
    if (game.state != GameState.Playing) return false;
    if (game.selected_tower_type == TowerType.None) return false;

    // Check if we can afford it
    const tower = Tower.init(x, y, game.selected_tower_type);
    if (game.money < tower.cost) return false;

    // Check if tower placement is valid (not on path)
    for (game.path[0..game.path_length]) |point| {
        const dx = point.x - x;
        const dy = point.y - y;
        const distance = @sqrt(dx * dx + dy * dy);
        if (distance < GRID_SIZE) return false;
    }

    // Check if tower placement overlaps with another tower
    for (game.towers[0..game.tower_count]) |other| {
        const dx = other.x - x;
        const dy = other.y - y;
        const distance = @sqrt(dx * dx + dy * dy);
        if (distance < GRID_SIZE) return false;
    }

    return true;
}

// Select tower type
export fn selectTowerType(tower_type: u32) void {
    game.selected_tower_type = switch (tower_type) {
        1 => TowerType.Line,
        2 => TowerType.Triangle,
        3 => TowerType.Square,
        4 => TowerType.Pentagon,
        else => TowerType.None,
    };

    var msg_buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&msg_buf, "Selected tower: {s}", .{@tagName(game.selected_tower_type)}) catch "Selected tower";
    logString(msg);
}

// Get the range of the currently selected tower
export fn getTowerRange() f32 {
    if (game.selected_tower_type == TowerType.None) return 0;

    const tower = Tower.init(0, 0, game.selected_tower_type);
    return tower.range;
}
