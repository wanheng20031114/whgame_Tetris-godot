'use strict';
const { randomUUID, randomInt } = require('crypto');

const LIMITS = Object.freeze({
    maxPayload: 64 * 1024, maxBufferedAmount: 256 * 1024,
    maxConnections: 256, maxRooms: 128, messagesPerSecond: 120,
    bytesPerSecond: 256 * 1024, attacksPerSecond: 20, samplesPerSecond: 30,
    maxAttack: 12, // tetris_core.gd: T-spin triple 6 + B2B 1 + maximum combo 5.
    loginTimeoutMs: 10000, heartbeatMs: 30000, summaryMs: 60000
});
const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const isInt = (value, min, max) => Number.isInteger(value) && value >= min && value <= max;
const isText = (value, max) => typeof value === 'string' && Array.from(value).length <= max && !/[\u0000-\u001f\u007f]/u.test(value);
const isId = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(value);
const isGrid = (grid, rows) => Array.isArray(grid) && grid.length === rows && grid.every(row =>
    Array.isArray(row) && row.length === 10 && row.every(cell => isInt(cell, 0, 8)));
const isScore = value => typeof value === 'number' && Number.isFinite(value) && Math.abs(value) <= 1000000;
const MATCH_MESSAGES = new Set(['board_update', 'attack', 'game_over', 'tetris33_sample',
    'tetris33_attack', 'tetris33_game_over', 'rematch_request', 'rematch_decline']);

function validMessage(type, p) {
    if (!isObject(p) || (p.match_id !== undefined && !isId(p.match_id))) return false;
    if (MATCH_MESSAGES.has(type) && !isId(p.match_id)) return false;
    switch (type) {
        case 'login': return isText(p.name, 12);
        case 'create_room':
        case 'create_tetris33_room': return p.name === undefined || isText(p.name, 48);
        case 'join_room': return isId(p.room_id);
        case 'board_update': return isGrid(p.grid, 40);
        case 'attack': return isInt(p.amount, 1, LIMITS.maxAttack);
        case 'tetris33_attack': return isId(p.target_id) && isInt(p.amount, 1, LIMITS.maxAttack);
        case 'tetris33_sample': return isGrid(p.visible_board, 20)
            && (p.structure_score === undefined || isScore(p.structure_score))
            && (p.stability_score === undefined || isScore(p.stability_score))
            && (p.pending_garbage === undefined || isInt(p.pending_garbage, 0, 1000000))
            && (p.eliminated === undefined || typeof p.eliminated === 'boolean')
            && (p.rank === undefined || isInt(p.rank, 1, 33));
        case 'tetris33_game_over': return p.rank === undefined || isInt(p.rank, 2, 33);
        case 'list_rooms': case 'close_room': case 'leave_room': case 'start_tetris33':
        case 'game_over': case 'rematch_request': case 'rematch_decline': return true;
        default: return false;
    }
}

// Importing this module never loads ws or creates/listens on an HTTP server.
// Injected transports let tests exercise the actual protocol entirely in memory.
function createGameServer({ WebSocket = require('ws'), http = require('http'),
    logger = console, now = Date.now, timers = globalThis } = {}) {
    const server = http.createServer({ maxHeaderSize: 8192, requestTimeout: 10000,
        headersTimeout: 10000, keepAliveTimeout: 5000 }, (_request, response) => {
        response.writeHead(426, { Connection: 'close', 'Content-Type': 'text/plain' });
        response.end('WebSocket required');
    });
    server.maxConnections = LIMITS.maxConnections;
    const wss = new WebSocket.Server({ server, maxPayload: LIMITS.maxPayload, perMessageDeflate: false });
    const connections = new Map(), clients = new Map(), rooms = new Map();
    const counters = Object.create(null);
    let roomListTimer = null;
    let sendingMatchStarts = false;
    const failedMatchStarts = new Map();
    function count(key) { counters[key] = Math.min(Number.MAX_SAFE_INTEGER, (counters[key] || 0) + 1); }
    function flushSummary() {
        if (!Object.keys(counters).length) return;
        logger.log('[server]', JSON.stringify({ ...counters, connections: connections.size, rooms: rooms.size }));
        for (const key of Object.keys(counters)) delete counters[key];
    }
    function error(ws, message, extra = {}) { send(ws, 'error', { message, ...extra }); }
    function disconnect(ws, reason) {
        if (!connections.has(ws)) return;
        // A synchronous send failure must not eliminate a player before the
        // remaining clients have received the new match ID.
        if (sendingMatchStarts) { failedMatchStarts.set(ws, reason); return; }
        count(reason); handleDisconnect(ws); ws.terminate();
    }
    function send(ws, type, payload) {
        if (ws.readyState !== WebSocket.OPEN || !connections.has(ws) || failedMatchStarts.has(ws)) return false;
        const message = JSON.stringify({ type, payload }), size = Buffer.byteLength(message);
        if (size > LIMITS.maxPayload || ws.bufferedAmount + size > LIMITS.maxBufferedAmount) {
            disconnect(ws, 'slow_or_oversize_send'); return false;
        }
        try { ws.send(message, err => { if (err) disconnect(ws, 'send_error'); }); return true; }
        catch (_err) { disconnect(ws, 'send_error'); return false; }
    }
    function takeBudget(ws, key, limit, amount = 1) {
        const c = connections.get(ws);
        if (!c) return false;
        if (now() - c.windowStarted >= 1000) { c.windowStarted = now(); c.budget = Object.create(null); }
        c.budget[key] = (c.budget[key] || 0) + amount;
        return c.budget[key] <= limit;
    }
    function cooldown(ws, key, ms) {
        const c = connections.get(ws), previous = c.cooldowns[key];
        if (previous !== undefined && now() - previous < ms) {
            error(ws, key === 'list_rooms' ? 'refresh_too_fast' : 'create_room_too_fast', { retry_after_ms: ms - (now() - previous) });
            return false;
        }
        c.cooldowns[key] = now(); return true;
    }
    function invalid(ws) {
        const c = connections.get(ws);
        if (!c) return;
        count('invalid_messages');
        if (++c.invalidMessages >= 3) disconnect(ws, 'invalid_client');
        else error(ws, 'invalid_message');
    }
    wss.on('connection', ws => {
        // Receiver errors are emitted on WebSocket, outside the message callback.
        ws.on('error', () => disconnect(ws, 'websocket_error'));
        ws.on('close', () => handleDisconnect(ws));
        if (connections.size >= LIMITS.maxConnections) { count('connection_limit'); ws.terminate(); return; }
        connections.set(ws, { connectedAt: now(), alive: true, windowStarted: now(),
            budget: Object.create(null), cooldowns: Object.create(null), invalidMessages: 0 });
        count('connected');
        ws.on('pong', () => { const c = connections.get(ws); if (c) c.alive = true; });
        ws.on('message', (message, isBinary) => {
            if (!connections.has(ws)) return;
            if (isBinary || (!Buffer.isBuffer(message) && typeof message !== 'string')) return invalid(ws);
            const length = Buffer.byteLength(message);
            if (length > LIMITS.maxPayload || !takeBudget(ws, 'messages', LIMITS.messagesPerSecond)
                || !takeBudget(ws, 'bytes', LIMITS.bytesPerSecond, length)) return disconnect(ws, 'rate_limit');
            let data;
            try { data = JSON.parse(message.toString()); } catch (_err) { return invalid(ws); }
            if (!isObject(data) || typeof data.type !== 'string' || !validMessage(data.type, data.payload)) return invalid(ws);
            handleMessage(ws, data.type, data.payload);
        });
    });
    server.on('error', () => count('http_error'));
    wss.on('error', () => count('websocket_server_error'));
    function roomFor(ws) {
        const c = clients.get(ws), room = c && rooms.get(c.room_id);
        return room && room.players.includes(ws) ? room : null;
    }
    function activeRoom(ws, mode, p) {
        const room = roomFor(ws);
        return room && room.mode === mode && room.status === 'playing' && room.alive.has(ws)
            && p.match_id === room.matchId ? room : null;
    }
    function matchPayload(room, p) { return { ...p, match_id: room.matchId }; }
    function broadcast(room, type, payload, except = null) {
        for (const p of [...room.players]) if (p !== except) send(p, type, payload);
    }
    function roomList() { return [...rooms.values()].filter(r => r.status === 'waiting').map(serializeRoom); }
    function broadcastRoomList() {
        if (roomListTimer !== null) return;
        roomListTimer = timers.setTimeout(() => {
            roomListTimer = null;
            const payload = { rooms: roomList() };
            for (const ws of clients.keys()) send(ws, 'room_list', payload);
        }, 50);
        roomListTimer.unref?.();
    }
    function serializeRoom(room) {
        const owner = clients.get(room.owner);
        return { id: room.id, name: room.name, mode: room.mode, playerCount: room.players.length,
            maxPlayers: room.maxPlayers, minPlayers: room.minPlayers, ownerId: owner.id, ownerName: owner.name };
    }
    function playerList(room) {
        return room.players.map((p, i) => ({ id: clients.get(p).id, name: clients.get(p).name, slot: i + 1 }));
    }
    function broadcastLobby(room) {
        broadcast(room, 'tetris33_lobby_update', { room_id: room.id, player_count: room.players.length,
            min_players: room.minPlayers, max_players: room.maxPlayers,
            owner_slot: room.players.indexOf(room.owner) + 1, players: playerList(room) });
    }
    function createRoom(ws, mode, name) {
        const c = clients.get(ws);
        if (c.room_id) return error(ws, 'already_in_room');
        if (!cooldown(ws, 'create_room', 1000)) return;
        if (rooms.size >= LIMITS.maxRooms) return error(ws, 'room_limit');
        const id = randomUUID().replaceAll('-', '').slice(0, 12).toUpperCase();
        if (rooms.has(id)) return error(ws, 'room_id_unavailable');
        const room = { id, name: name || `${c.name}'s ${mode === 'tetris33' ? 'Tetris33' : 'room'}`,
            mode, players: [ws], owner: ws, status: 'waiting', maxPlayers: mode === 'tetris33' ? 33 : 2,
            minPlayers: mode === 'tetris33' ? 3 : 2, seed: null, matchId: '',
            roster: new Map(), alive: new Set(), results: new Map(), rematch: new Map(), rematchLocked: false };
        rooms.set(id, room); c.room_id = id;
        send(ws, 'room_created', { room_id: id, mode });
        if (rooms.has(id) && mode === 'tetris33') broadcastLobby(room);
        broadcastRoomList();
    }
    function startMatch(room) {
        // Evict already backed-up peers before constructing a new match. This
        // prevents elimination events preceding game_start on healthy peers.
        for (const p of [...room.players]) {
            if (p.bufferedAmount > LIMITS.maxBufferedAmount - LIMITS.maxPayload) disconnect(p, 'slow_before_match');
        }
        if (!rooms.has(room.id)) return false;
        if (room.players.length < room.minPlayers || room.players.length > room.maxPlayers
            || new Set(room.players).size !== room.players.length
            || room.players.some(p => !clients.has(p) || clients.get(p).room_id !== room.id)) return false;
        room.status = 'playing'; room.seed = randomInt(1, 2147483647); room.matchId = randomUUID();
        room.rematch.clear(); room.rematchLocked = false; room.results.clear();
        room.roster = new Map(room.players.map((p, i) => [p, { id: clients.get(p).id, name: clients.get(p).name, slot: i + 1 }]));
        room.alive = new Set(room.players);
        const players = [...room.roster.values()];
        sendingMatchStarts = true;
        try {
            for (const [p, entry] of room.roster) {
                if (room.mode === 'tetris33') send(p, 'game_start_tetris33', matchPayload(room,
                    { seed: room.seed, local_slot: entry.slot, player_count: players.length, players }));
                else send(p, 'game_start', matchPayload(room,
                    { seed: room.seed, opponent_name: players.find(other => other.id !== entry.id).name }));
            }
        } finally {
            sendingMatchStarts = false;
            for (const [p, reason] of failedMatchStarts) {
                failedMatchStarts.delete(p);
                disconnect(p, reason);
            }
        }
        broadcastRoomList(); return true;
    }
    function finishTetris33(room) {
        if (room.status !== 'playing' || room.alive.size !== 1) return;
        const winner = room.alive.values().next().value;
        room.results.set(winner, { ...room.roster.get(winner), rank: 1 });
        room.status = 'finished'; room.rematch.clear();
        room.rematchLocked = room.players.length < room.minPlayers;
        for (const p of room.players) room.rematch.set(p, 'none');
        const results = [...room.results.values()].sort((a, b) => a.rank - b.rank);
        broadcast(room, 'tetris33_match_finished', matchPayload(room, { results, player_count: room.roster.size }));
        broadcastRematch(room);
    }
    function eliminate(room, ws) {
        if (room.status !== 'playing' || !room.alive.has(ws)) return;
        const rank = room.alive.size;
        room.alive.delete(ws);
        const who = room.roster.get(ws);
        room.results.set(ws, { ...who, rank });
        broadcast(room, 'tetris33_game_over', matchPayload(room, { rank, from_id: who.id, from_name: who.name }), ws);
        finishTetris33(room);
    }
    function closeRoom(room, reason) {
        rooms.delete(room.id);
        const players = [...room.players]; room.players = [];
        for (const p of players) clients.get(p).room_id = null;
        for (const p of players) send(p, 'room_closed', { room_id: room.id, reason });
        broadcastRoomList();
    }
    function removePlayer(ws, room) {
        const client = clients.get(ws);
        room.players = room.players.filter(p => p !== ws); client.room_id = null;
        if (!room.players.length) { rooms.delete(room.id); broadcastRoomList(); return; }
        if (room.owner === ws) room.owner = room.players[0];
        if (room.mode === 'versus') {
            if (room.status !== 'waiting') {
                rooms.delete(room.id);
                for (const p of room.players) { clients.get(p).room_id = null; send(p, 'opponent_left', {}); }
            }
        } else {
            // Fixed roster/results survive disconnects. Leaving is an elimination
            // only while alive, and can immediately settle the survivor match.
            eliminate(room, ws);
            broadcast(room, 'tetris33_player_left', matchPayload(room, { id: client.id, name: client.name, player_count: room.players.length }));
            if (room.status === 'waiting') broadcastLobby(room);
            else if (room.status === 'finished') { room.rematchLocked = true; broadcastRematch(room); }
        }
        broadcastRoomList();
    }
    function handleDisconnect(ws) {
        if (!connections.delete(ws)) return;
        count('disconnected');
        const room = roomFor(ws);
        if (room) {
            if (room.status === 'waiting' && room.owner === ws) closeRoom(room, 'owner_disconnected');
            else removePlayer(ws, room);
        }
        clients.delete(ws);
    }
    function broadcastRematch(room) {
        if (room.mode === 'tetris33') {
            const statuses = room.players.map(p => ({ id: clients.get(p).id, name: clients.get(p).name, status: room.rematch.get(p) || 'none' }));
            const ready = statuses.filter(s => s.status === 'ready').length;
            for (const p of [...room.players]) send(p, 'rematch_status', matchPayload(room,
                { mode: room.mode, my_status: room.rematch.get(p) || 'none',
                    opponent_status: room.rematchLocked ? 'declined' : 'none', ready_count: ready,
                    total_count: statuses.length, declined: room.rematchLocked, statuses }));
        } else {
            for (const p of [...room.players]) send(p, 'rematch_status', matchPayload(room,
                { my_status: room.rematch.get(p) || 'none', opponent_status: room.rematch.get(room.players.find(other => other !== p)) || 'none' }));
        }
    }
    function handleMessage(ws, type, payload) {
        if (type === 'login') {
            // Login retries retain identity and room membership.
            if (!clients.has(ws)) clients.set(ws, { id: randomUUID(), name: payload.name.trim() || 'GUEST', room_id: null });
            send(ws, 'login_success', { id: clients.get(ws).id }); return;
        }
        if (!clients.has(ws)) return error(ws, 'login_required');
        switch (type) {
            case 'list_rooms':
                if (cooldown(ws, 'list_rooms', 200)) send(ws, 'room_list', { rooms: roomList() });
                return;
            case 'create_room': return createRoom(ws, 'versus', payload.name);
            case 'create_tetris33_room': return createRoom(ws, 'tetris33', payload.name);
            case 'join_room': {
                const client = clients.get(ws), room = rooms.get(payload.room_id);
                if (client.room_id) return error(ws, 'already_in_room');
                if (!room) return error(ws, 'room_not_found');
                if (room.status !== 'waiting') return error(ws, 'room_not_waiting');
                if (room.players.length >= room.maxPlayers) return error(ws, 'room_full');
                room.players.push(ws); client.room_id = room.id;
                send(ws, 'room_joined', { room_id: room.id, mode: room.mode });
                if (!rooms.has(room.id)) return;
                if (room.mode === 'tetris33') broadcastLobby(room);
                if (room.players.length === room.maxPlayers) startMatch(room);
                broadcastRoomList(); return;
            }
            case 'start_tetris33': {
                const room = roomFor(ws);
                if (!room || room.mode !== 'tetris33' || room.status !== 'waiting') return error(ws, 'invalid_room_state');
                if (room.owner !== ws) return error(ws, 'only_owner_can_start');
                if (!startMatch(room)) error(ws, 'not_enough_players', { min_players: room.minPlayers, player_count: room.players.length });
                return;
            }
            case 'close_room': case 'leave_room': {
                const room = roomFor(ws);
                if (!room) { send(ws, 'room_left', {}); return; }
                if (type === 'close_room') {
                    if (room.owner !== ws) return error(ws, 'only_owner_can_close');
                    if (room.status !== 'waiting') return error(ws, 'invalid_room_state');
                }
                if (room.owner === ws && room.status === 'waiting') closeRoom(room, 'owner_closed_room');
                else { removePlayer(ws, room); send(ws, 'room_left', { room_id: room.id }); }
                return;
            }
            case 'board_update': case 'attack': case 'game_over': {
                const room = activeRoom(ws, 'versus', payload);
                if (!room) return error(ws, 'invalid_match_state');
                if (type !== 'game_over' && !takeBudget(ws, type, type === 'attack' ? LIMITS.attacksPerSecond : LIMITS.samplesPerSecond)) return disconnect(ws, 'game_rate_limit');
                broadcast(room, type, matchPayload(room, type === 'attack' ? { amount: payload.amount } : type === 'board_update' ? { grid: payload.grid } : {}), ws);
                if (type === 'game_over') {
                    room.alive.delete(ws); room.status = 'finished'; room.rematch.clear();
                    for (const p of room.players) room.rematch.set(p, 'none');
                }
                return;
            }
            case 'tetris33_sample': case 'tetris33_attack': case 'tetris33_game_over': {
                const room = activeRoom(ws, 'tetris33', payload);
                if (!room) return error(ws, 'invalid_match_state');
                if (type === 'tetris33_game_over') { eliminate(room, ws); return; }
                if (!takeBudget(ws, type, type === 'tetris33_attack' ? LIMITS.attacksPerSecond : LIMITS.samplesPerSecond)) return disconnect(ws, 'game_rate_limit');
                const who = room.roster.get(ws);
                if (type === 'tetris33_attack') {
                    const target = [...room.alive].find(p => room.roster.get(p).id === payload.target_id && p !== ws);
                    if (!target || !room.players.includes(target)) return error(ws, 'invalid_target');
                    send(target, type, matchPayload(room, { amount: payload.amount, target_id: payload.target_id, from_id: who.id, from_name: who.name }));
                } else {
                    // Visual samples cannot change authoritative elimination/rank.
                    // Old clients may still include those fields in their input.
                    broadcast(room, type, matchPayload(room, { visible_board: payload.visible_board,
                        structure_score: payload.structure_score || 0, stability_score: payload.stability_score || 0,
                        pending_garbage: payload.pending_garbage || 0, from_id: who.id, from_name: who.name }), ws);
                }
                return;
            }
            case 'rematch_request': case 'rematch_decline': {
                const room = roomFor(ws);
                if (!room || room.status !== 'finished' || payload.match_id !== room.matchId) return error(ws, 'invalid_match_state');
                if (type === 'rematch_decline') {
                    room.rematch.set(ws, 'declined'); room.rematchLocked = true;
                    // Commit departure before sending: send may synchronously
                    // disconnect a slow peer, which must not remove it twice.
                    removePlayer(ws, room);
                    send(ws, 'room_left', { room_id: room.id }); return;
                }
                if (room.rematchLocked || room.players.length < room.minPlayers) { broadcastRematch(room); return; }
                room.rematch.set(ws, 'ready');
                if (room.players.every(p => room.rematch.get(p) === 'ready')) startMatch(room);
                else broadcastRematch(room);
                return;
            }
        }
    }
    // Aggregate fixed counters once per minute; packet bodies are never logged.
    const summaryTimer = timers.setInterval(flushSummary, LIMITS.summaryMs);
    const heartbeatTimer = timers.setInterval(() => {
        for (const [ws, c] of connections) {
            if (!clients.has(ws) && now() - c.connectedAt >= LIMITS.loginTimeoutMs) disconnect(ws, 'login_timeout');
            else if (!c.alive) disconnect(ws, 'heartbeat_timeout');
            else { c.alive = false; try { ws.ping(); } catch (_err) { disconnect(ws, 'ping_error'); } }
        }
    }, LIMITS.heartbeatMs);
    summaryTimer.unref?.(); heartbeatTimer.unref?.();
    function stop() {
        timers.clearInterval(summaryTimer); timers.clearInterval(heartbeatTimer);
        if (roomListTimer !== null) timers.clearTimeout(roomListTimer);
        roomListTimer = null;
        for (const ws of [...connections.keys()]) disconnect(ws, 'shutdown');
        if (roomListTimer !== null) timers.clearTimeout(roomListTimer);
        roomListTimer = null; wss.close(); server.close();
    }
    return { server, wss, clients, rooms, connections, stop, flushSummary,
        listen(port = 8998) { server.listen(port, () => logger.log(`[server] listening on ${port}`)); } };
}
module.exports = { createGameServer, LIMITS, validMessage, isGrid };
if (require.main === module) {
    const app = createGameServer();
    app.server.once('error', () => {
        console.error('[server] HTTP server failure; shutting down.');
        process.exitCode = 1; app.stop();
    });
    app.listen();
}
