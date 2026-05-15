const WebSocket = require('ws');
const http = require('http');

const PORT = 8998;
const LIST_ROOMS_COOLDOWN_MS = 200;
const CREATE_ROOM_COOLDOWN_MS = 1000;
const LOGIN_COOLDOWN_MS = 1000;
const MAX_PLAYER_NAME_LENGTH = 12;
const server = http.createServer();
const wss = new WebSocket.Server({ server });
const actionCooldowns = new WeakMap(); // ws -> { action: last_ts_ms }

// 存储全局状态
const clients = new Map(); // ws -> { id, name, room_id }
const rooms = new Map();    // room_id -> { id, name, players: [ws1, ws2], status: 'waiting'|'playing'|'finished', seed, rematch: Map<ws, 'none'|'ready'|'declined'> }

console.log(`俄罗斯方块 WebSocket 服务端已启动，监听端口: ${PORT}`);

wss.on('connection', (ws) => {
    console.log('新客户端已连接');

    ws.on('message', (message) => {
        try {
            const data = JSON.parse(message);
            handleMessage(ws, data);
        } catch (e) {
            console.error('解析消息失败:', e);
        }
    });

    ws.on('close', () => {
        handleDisconnect(ws);
    });
});

function sanitizePlayerName(name) {
    const cleaned = String(name || '').trim();
    const clipped = Array.from(cleaned).slice(0, MAX_PLAYER_NAME_LENGTH).join('');
    return clipped || `GUEST_${Math.floor(Math.random() * 9000) + 1000}`;
}

function handleMessage(ws, data) {
    const { type, payload } = data;
    console.log(`收到消息: ${type}`, payload);

    switch (type) {
        case 'login':
            const loginRetryMs = getCooldownRetryMs(ws, 'login', LOGIN_COOLDOWN_MS);
            if (loginRetryMs > 0) {
                send(ws, 'error', {
                    message: 'login_too_fast',
                    retry_after_ms: loginRetryMs
                });
                return;
            }
            // 登录并保存用户名
            clients.set(ws, {
                id: Math.random().toString(36).substr(2, 9),
                name: sanitizePlayerName(payload.name),
                room_id: null
            });
            send(ws, 'login_success', { id: clients.get(ws).id });
            break;

        case 'list_rooms':
            const listClient = clients.get(ws);
            if (!listClient) return;

            const listRetryMs = getCooldownRetryMs(ws, 'list_rooms', LIST_ROOMS_COOLDOWN_MS);
            if (listRetryMs > 0) {
                send(ws, 'error', {
                    message: 'refresh_too_fast',
                    retry_after_ms: listRetryMs
                });
                return;
            }
            // 返回可加入的房间列表
            const roomList = Array.from(rooms.values())
                .filter(r => r.status === 'waiting')
                .map(serializeRoom);
            send(ws, 'room_list', { rooms: roomList });
            break;

        case 'create_room':
            // 创建新房间
            const client = clients.get(ws);
            if (!client) return;
            if (client.room_id) {
                send(ws, 'error', { message: 'already_in_room' });
                return;
            }
            const createRetryMs = getCooldownRetryMs(ws, 'create_room', CREATE_ROOM_COOLDOWN_MS);
            if (createRetryMs > 0) {
                send(ws, 'error', {
                    message: 'create_room_too_fast',
                    retry_after_ms: createRetryMs
                });
                return;
            }

            const roomId = Math.random().toString(36).substr(2, 6).toUpperCase();
            const newRoom = {
                id: roomId,
                name: payload.name || `${client.name}'s room`,
                mode: 'versus',
                players: [ws],
                status: 'waiting',
                maxPlayers: 2,
                minPlayers: 2,
                owner: ws,
                seed: null,
                rematch: new Map()
            };
            rooms.set(roomId, newRoom);
            client.room_id = roomId;
            send(ws, 'room_created', { room_id: roomId });
            broadcastRoomList();
            break;

        case 'create_tetris33_room':
            const t33Client = clients.get(ws);
            if (!t33Client) return;
            if (t33Client.room_id) {
                send(ws, 'error', { message: 'already_in_room' });
                return;
            }

            const t33RoomId = Math.random().toString(36).substr(2, 6).toUpperCase();
            const t33Room = {
                id: t33RoomId,
                name: payload.name || `${t33Client.name}'s Tetris33`,
                mode: 'tetris33',
                players: [ws],
                status: 'waiting',
                maxPlayers: 33,
                minPlayers: 3,
                owner: ws,
                seed: null,
                rematch: new Map()
            };
            rooms.set(t33RoomId, t33Room);
            t33Client.room_id = t33RoomId;
            send(ws, 'room_created', { room_id: t33RoomId, mode: 'tetris33' });
            broadcastRoomList();
            broadcastTetris33Lobby(t33Room);
            break;

        case 'join_room':
            // 加入房间
            const joinClient = clients.get(ws);
            if (!joinClient) return;
            const targetRoom = rooms.get(payload.room_id);
            if (!targetRoom) {
                send(ws, 'error', { message: 'room_not_found' });
                return;
            }

            if (joinClient.room_id === payload.room_id || targetRoom.players.includes(ws)) {
                send(ws, 'error', { message: 'already_in_room' });
                return;
            }

            if (joinClient.room_id && joinClient.room_id !== payload.room_id) {
                send(ws, 'error', { message: 'already_in_room' });
                return;
            }

            if (targetRoom.players.length > 0 && targetRoom.players[0] === ws) {
                send(ws, 'error', { message: 'cannot_join_own_room' });
                return;
            }

            if (targetRoom && targetRoom.players.length < (targetRoom.maxPlayers || 2)) {
                targetRoom.players.push(ws);
                joinClient.room_id = payload.room_id;

                send(ws, 'room_joined', { room_id: payload.room_id, mode: targetRoom.mode || 'versus' });

                // 如果人满了，通知双方游戏开始
                if ((targetRoom.mode || 'versus') === 'tetris33') {
                    broadcastTetris33Lobby(targetRoom);
                    if (targetRoom.players.length >= targetRoom.maxPlayers) {
                        startTetris33Game(targetRoom);
                    }
                } else if (targetRoom.players.length === 2) {
                    startGame(targetRoom);
                }

                broadcastRoomList();
            } else {
                send(ws, 'error', { message: '无法加入房间（已满或不存在）' });
            }
            break;

        case 'close_room':
            const closeClient = clients.get(ws);
            if (!closeClient || !closeClient.room_id) return;
            const closeRoomTarget = rooms.get(closeClient.room_id);
            if (!closeRoomTarget) {
                closeClient.room_id = null;
                send(ws, 'room_left', {});
                return;
            }
            if (closeRoomTarget.owner !== ws) {
                send(ws, 'error', { message: 'only_owner_can_close' });
                return;
            }
            closeRoom(closeRoomTarget, 'owner_closed_room');
            break;

        case 'leave_room':
            const leaveClient = clients.get(ws);
            if (!leaveClient || !leaveClient.room_id) return;
            const leaveRoomTarget = rooms.get(leaveClient.room_id);
            if (!leaveRoomTarget) {
                leaveClient.room_id = null;
                send(ws, 'room_left', {});
                return;
            }
            if (leaveRoomTarget.owner === ws) {
                closeRoom(leaveRoomTarget, 'owner_closed_room');
            } else {
                removePlayerFromRoom(ws, leaveRoomTarget);
                send(ws, 'room_left', { room_id: leaveRoomTarget.id });
                broadcastRoomList();
            }
            break;

        case 'start_tetris33':
            const startClient = clients.get(ws);
            if (!startClient || !startClient.room_id) return;
            const startRoom = rooms.get(startClient.room_id);
            if (!startRoom || startRoom.mode !== 'tetris33') return;
            if (startRoom.owner !== ws) {
                send(ws, 'error', { message: 'only_owner_can_start' });
                return;
            }
            if (startRoom.players.length < startRoom.minPlayers) {
                send(ws, 'error', {
                    message: 'not_enough_players',
                    min_players: startRoom.minPlayers,
                    player_count: startRoom.players.length
                });
                return;
            }
            startTetris33Game(startRoom);
            break;

        case 'board_update':
        case 'attack':
        case 'game_over':
            // 转发对战消息给对手
            forwardToOpponent(ws, type, payload);
            // game_over 时将房间状态设为 finished，准备接收 rematch
            if (type === 'game_over') {
                const goClient = clients.get(ws);
                if (goClient && goClient.room_id) {
                    const goRoom = rooms.get(goClient.room_id);
                    if (goRoom) {
                        goRoom.status = 'finished';
                        // 初始化双方 rematch 状态
                        goRoom.rematch.clear();
                        for (const p of goRoom.players) {
                            goRoom.rematch.set(p, 'none');
                        }
                    }
                }
            }
            break;

        case 'tetris33_sample':
        case 'tetris33_attack':
            forwardToRoom(ws, type, payload);
            break;

        case 'tetris33_game_over':
            {
                const gameOverPayload = handleTetris33GameOver(ws, payload);
                if (gameOverPayload) {
                    forwardToRoom(ws, type, gameOverPayload);
                }
            }
            break;

        case 'rematch_request':
            handleRematchRequest(ws);
            break;

        case 'rematch_decline':
            handleRematchDecline(ws);
            break;
    }
}

function getCooldownRetryMs(ws, action, cooldownMs) {
    const now = Date.now();
    const record = actionCooldowns.get(ws) || {};
    const lastTs = record[action] || 0;
    const elapsed = now - lastTs;
    if (elapsed < cooldownMs) {
        return cooldownMs - elapsed;
    }
    record[action] = now;
    actionCooldowns.set(ws, record);
    return 0;
}

// ============================================================
// 游戏启动辅助
// ============================================================
function startGame(room) {
    // Defensive guard: a valid match must have exactly two distinct sockets.
    const uniquePlayers = Array.from(new Set(room.players));
    if (uniquePlayers.length !== 2) {
        room.players = uniquePlayers;
        room.status = 'waiting';
        for (const p of uniquePlayers) {
            send(p, 'error', { message: 'invalid_room_state' });
        }
        broadcastRoomList();
        return;
    }

    room.status = 'playing';
    room.seed = Math.floor(Math.random() * 2147483647) + 1;
    room.rematch.clear();

    const p1 = clients.get(uniquePlayers[0]);
    const p2 = clients.get(uniquePlayers[1]);

    send(uniquePlayers[0], 'game_start', { opponent_name: p2.name, seed: room.seed });
    send(uniquePlayers[1], 'game_start', { opponent_name: p1.name, seed: room.seed });
    broadcastRoomList();
}

function startTetris33Game(room) {
    const uniquePlayers = Array.from(new Set(room.players));
    if (uniquePlayers.length < (room.minPlayers || 3)) {
        room.players = uniquePlayers;
        room.status = 'waiting';
        broadcastTetris33Lobby(room);
        return;
    }

    room.players = uniquePlayers.slice(0, room.maxPlayers || 33);
    room.status = 'playing';
    room.seed = Math.floor(Math.random() * 2147483647) + 1;
    room.rematch.clear();
    room.rematchLocked = false;
    room.tetris33Results = new Map();

    const players = buildRoomPlayerList(room);
    for (let i = 0; i < room.players.length; i++) {
        send(room.players[i], 'game_start_tetris33', {
            seed: room.seed,
            local_slot: i + 1,
            player_count: room.players.length,
            players
        });
    }
    broadcastRoomList();
}

function buildRoomPlayerList(room) {
    return room.players.map((player, index) => {
        const client = clients.get(player);
        return {
            id: client ? client.id : '',
            name: client ? client.name : `Player ${index + 1}`,
            slot: index + 1
        };
    });
}

function serializeRoom(room) {
    const owner = clients.get(room.owner);
    return {
        id: room.id,
        name: room.name,
        mode: room.mode || 'versus',
        playerCount: room.players.length,
        maxPlayers: room.maxPlayers || 2,
        minPlayers: room.minPlayers || 2,
        ownerId: owner ? owner.id : '',
        ownerName: owner ? owner.name : ''
    };
}

function closeRoom(room, reason) {
    const roomId = room.id;
    for (const player of room.players) {
        const playerClient = clients.get(player);
        if (playerClient) {
            playerClient.room_id = null;
        }
        send(player, 'room_closed', {
            room_id: roomId,
            reason: reason || 'room_closed'
        });
    }
    rooms.delete(roomId);
    broadcastRoomList();
}

function removePlayerFromRoom(ws, room) {
    const client = clients.get(ws);
    room.players = room.players.filter(p => p !== ws);
    if (client) {
        client.room_id = null;
    }

    if (room.players.length === 0) {
        rooms.delete(room.id);
        return;
    }

    if ((room.mode || 'versus') === 'tetris33') {
        if (room.owner === ws) {
            room.owner = room.players[0] || null;
        }
        for (const player of room.players) {
            send(player, 'tetris33_player_left', {
                id: client ? client.id : '',
                name: client ? client.name : '',
                player_count: room.players.length
            });
        }
        if (room.status === 'waiting') {
            broadcastTetris33Lobby(room);
        }
        return;
    }

    const opponent = room.players[0];
    if (opponent && room.status !== 'waiting') {
        const opponentClient = clients.get(opponent);
        if (opponentClient) {
            opponentClient.room_id = null;
        }
        send(opponent, 'opponent_left', {});
        rooms.delete(room.id);
    }
}

function handleTetris33GameOver(ws, payload) {
    const client = clients.get(ws);
    if (!client || !client.room_id) return null;

    const room = rooms.get(client.room_id);
    if (!room || room.mode !== 'tetris33') return null;
    if (room.status === 'finished') return null;
    if (Number(payload.rank || 0) === 1) return null;

    if (!room.tetris33Results) {
        room.tetris33Results = new Map();
    }
    if (room.tetris33Results.has(ws)) return null;

    const totalPlayers = Math.max(1, room.players.length);
    const serverRank = Math.max(2, totalPlayers - room.tetris33Results.size);
    room.tetris33Results.set(ws, {
        id: client.id,
        name: client.name,
        rank: serverRank
    });

    const authoritativePayload = { ...payload, rank: serverRank };

    if (room.tetris33Results.size < Math.max(1, totalPlayers - 1)) {
        return authoritativePayload;
    }

    for (const player of room.players) {
        if (!room.tetris33Results.has(player)) {
            const survivor = clients.get(player);
            room.tetris33Results.set(player, {
                id: survivor ? survivor.id : '',
                name: survivor ? survivor.name : '',
                rank: 1
            });
        }
    }

    room.status = 'finished';
    room.rematch.clear();
    room.rematchLocked = false;
    for (const player of room.players) {
        room.rematch.set(player, 'none');
    }

    const results = Array.from(room.tetris33Results.values()).sort((a, b) => a.rank - b.rank);
    for (const player of room.players) {
        send(player, 'tetris33_match_finished', {
            results,
            player_count: room.players.length
        });
    }
    broadcastRematchStatus(room);
    return authoritativePayload;
}

// ============================================================
// Rematch 协议处理
// ============================================================

function handleRematchRequest(ws) {
    const client = clients.get(ws);
    if (!client || !client.room_id) return;

    const room = rooms.get(client.room_id);
    if (!room) return;

    // 标记当前玩家为 ready
    if ((room.mode || 'versus') === 'tetris33') {
        if (room.status !== 'finished' || room.rematchLocked) {
            broadcastRematchStatus(room);
            return;
        }

        room.rematch.set(ws, 'ready');
        const allReady = room.players.length > 0 && room.players.every(p => room.rematch.get(p) === 'ready');
        if (allReady) {
            startTetris33Game(room);
        } else {
            broadcastRematchStatus(room);
        }
        return;
    }

    room.rematch.set(ws, 'ready');

    // 检查双方是否都准备好
    const opponent = room.players.find(p => p !== ws);
    const opponentStatus = opponent ? (room.rematch.get(opponent) || 'none') : 'none';

    if (opponentStatus === 'ready') {
        // 双方都同意，开始新游戏
        startGame(room);
    } else {
        // 单方面准备，通知双方各自的状态
        broadcastRematchStatus(room);
    }
}

function handleRematchDecline(ws) {
    const client = clients.get(ws);
    if (!client || !client.room_id) return;

    const room = rooms.get(client.room_id);
    if (!room) return;

    // 标记当前玩家为 declined
    room.rematch.set(ws, 'declined');
    if ((room.mode || 'versus') === 'tetris33') {
        room.rematchLocked = true;
    }

    // 通知对手
    broadcastRematchStatus(room);

    // 将该玩家从房间移除
    room.players = room.players.filter(p => p !== ws);
    client.room_id = null;
    send(ws, 'room_left', { room_id: room.id });

    // 如果房间空了，删除房间
    if (room.players.length === 0) {
        rooms.delete(room.id);
    }
}

function broadcastRematchStatus(room) {
    if ((room.mode || 'versus') === 'tetris33') {
        const statuses = room.players.map(player => {
            const client = clients.get(player);
            return {
                id: client ? client.id : '',
                name: client ? client.name : '',
                status: room.rematch.get(player) || 'none'
            };
        });
        const readyCount = statuses.filter(s => s.status === 'ready').length;
        const declined = statuses.some(s => s.status === 'declined') || !!room.rematchLocked;
        for (const player of room.players) {
            send(player, 'rematch_status', {
                mode: 'tetris33',
                my_status: room.rematch.get(player) || 'none',
                opponent_status: declined ? 'declined' : 'none',
                ready_count: readyCount,
                total_count: statuses.length,
                declined,
                statuses
            });
        }
        return;
    }

    for (const player of room.players) {
        const opponent = room.players.find(p => p !== player);
        const myStatus = room.rematch.get(player) || 'none';
        const oppStatus = opponent ? (room.rematch.get(opponent) || 'none') : 'none';

        send(player, 'rematch_status', {
            my_status: myStatus,
            opponent_status: oppStatus
        });
    }
}

function broadcastRoomList() {
    const roomList = Array.from(rooms.values())
        .filter(r => r.status === 'waiting')
        .map(serializeRoom);

    for (const ws of clients.keys()) {
        send(ws, 'room_list', { rooms: roomList });
    }
}

function broadcastTetris33Lobby(room) {
    if (!room || room.mode !== 'tetris33') return;
    const payload = {
        room_id: room.id,
        player_count: room.players.length,
        min_players: room.minPlayers || 3,
        max_players: room.maxPlayers || 33,
        owner_slot: room.players.indexOf(room.owner) + 1,
        players: buildRoomPlayerList(room)
    };
    for (const player of room.players) {
        send(player, 'tetris33_lobby_update', payload);
    }
}

function forwardToOpponent(ws, type, payload) {
    const client = clients.get(ws);
    if (!client || !client.room_id) return;

    const room = rooms.get(client.room_id);
    if (!room) return;

    const opponent = room.players.find(p => p !== ws);
    if (opponent && opponent.readyState === WebSocket.OPEN) {
        send(opponent, type, payload);
    }
}

function forwardToRoom(ws, type, payload) {
    const client = clients.get(ws);
    if (!client || !client.room_id) return;

    const room = rooms.get(client.room_id);
    if (!room || room.mode !== 'tetris33') return;

    for (const player of room.players) {
        if (player !== ws && player.readyState === WebSocket.OPEN) {
            send(player, type, {
                ...payload,
                from_id: client.id,
                from_name: client.name
            });
        }
    }
}

function handleDisconnect(ws) {
    const client = clients.get(ws);
    if (client) {
        console.log(`客户端断开连接: ${client.name}`);
        if (client.room_id) {
            const room = rooms.get(client.room_id);
            if (room) {
                if (room.owner === ws && room.status === 'waiting') {
                    closeRoom(room, 'owner_disconnected');
                    clients.delete(ws);
                    return;
                }

                if (room.mode === 'tetris33') {
                    removePlayerFromRoom(ws, room);
                    broadcastRoomList();
                    clients.delete(ws);
                    return;
                }
                // 如果房间处于结算阶段，标记断线玩家为 declined 并通知对手
                if (room.status === 'finished') {
                    room.rematch.set(ws, 'declined');
                    broadcastRematchStatus(room);
                }

                removePlayerFromRoom(ws, room);
                broadcastRoomList();
            }
        }
        clients.delete(ws);
    }
}

function send(ws, type, payload) {
    if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type, payload }));
    }
}

server.listen(PORT);
