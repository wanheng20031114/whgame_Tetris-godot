const WebSocket = require('ws');
const http = require('http');

const PORT = 8998;
const LIST_ROOMS_COOLDOWN_MS = 200;
const CREATE_ROOM_COOLDOWN_MS = 1000;
const LOGIN_COOLDOWN_MS = 1000;
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
                name: payload.name || 'fucking bot',
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
                .map(r => ({ id: r.id, name: r.name, playerCount: r.players.length }));
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
                players: [ws],
                status: 'waiting',
                seed: null,
                rematch: new Map()
            };
            rooms.set(roomId, newRoom);
            client.room_id = roomId;
            send(ws, 'room_created', { room_id: roomId });
            broadcastRoomList();
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

            if (targetRoom.players.length > 0 && targetRoom.players[0] === ws) {
                send(ws, 'error', { message: 'cannot_join_own_room' });
                return;
            }

            if (targetRoom && targetRoom.players.length < 2) {
                if (joinClient.room_id && joinClient.room_id !== payload.room_id) {
                    leaveWaitingRoomIfOwned(joinClient, ws);
                }

                targetRoom.players.push(ws);
                joinClient.room_id = payload.room_id;

                send(ws, 'room_joined', { room_id: payload.room_id });

                // 如果人满了，通知双方游戏开始
                if (targetRoom.players.length === 2) {
                    startGame(targetRoom);
                }

                broadcastRoomList();
            } else {
                send(ws, 'error', { message: '无法加入房间（已满或不存在）' });
            }
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

function leaveWaitingRoomIfOwned(client, ws) {
    const oldRoomId = client.room_id;
    if (!oldRoomId) return;

    const oldRoom = rooms.get(oldRoomId);
    if (!oldRoom) {
        client.room_id = null;
        return;
    }

    if (oldRoom.status !== 'waiting') {
        return;
    }

    oldRoom.players = oldRoom.players.filter(p => p !== ws);
    if (oldRoom.players.length === 0) {
        rooms.delete(oldRoomId);
    }
    client.room_id = null;
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

// ============================================================
// Rematch 协议处理
// ============================================================

function handleRematchRequest(ws) {
    const client = clients.get(ws);
    if (!client || !client.room_id) return;

    const room = rooms.get(client.room_id);
    if (!room) return;

    // 标记当前玩家为 ready
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

    // 通知对手
    broadcastRematchStatus(room);

    // 将该玩家从房间移除
    room.players = room.players.filter(p => p !== ws);
    client.room_id = null;

    // 如果房间空了，删除房间
    if (room.players.length === 0) {
        rooms.delete(room.id);
    }
}

function broadcastRematchStatus(room) {
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
        .map(r => ({ id: r.id, name: r.name, playerCount: r.players.length }));

    for (const ws of clients.keys()) {
        send(ws, 'room_list', { rooms: roomList });
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

function handleDisconnect(ws) {
    const client = clients.get(ws);
    if (client) {
        console.log(`客户端断开连接: ${client.name}`);
        if (client.room_id) {
            const room = rooms.get(client.room_id);
            if (room) {
                // 如果房间处于结算阶段，标记断线玩家为 declined 并通知对手
                if (room.status === 'finished') {
                    room.rematch.set(ws, 'declined');
                    broadcastRematchStatus(room);
                }

                // 通知对手离开
                const opponent = room.players.find(p => p !== ws);
                if (opponent) {
                    send(opponent, 'opponent_left', {});
                }

                // 将该玩家从房间移除
                room.players = room.players.filter(p => p !== ws);
                if (room.players.length === 0) {
                    rooms.delete(client.room_id);
                }
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
