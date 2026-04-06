const WebSocket = require('ws');
const http = require('http');

const PORT = 8998;
const LIST_ROOMS_COOLDOWN_MS = 500;
const server = http.createServer();
const wss = new WebSocket.Server({ server });

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
            // 登录并保存用户名
            clients.set(ws, {
                id: Math.random().toString(36).substr(2, 9),
                name: payload.name || '无名大侠',
                room_id: null,
                last_list_rooms_at: 0
            });
            send(ws, 'login_success', { id: clients.get(ws).id });
            break;

        case 'list_rooms':
            const listClient = clients.get(ws);
            if (!listClient) return;

            const now = Date.now();
            const elapsed = now - (listClient.last_list_rooms_at || 0);
            if (elapsed < LIST_ROOMS_COOLDOWN_MS) {
                send(ws, 'error', {
                    message: 'refresh_too_fast',
                    retry_after_ms: LIST_ROOMS_COOLDOWN_MS - elapsed
                });
                return;
            }
            listClient.last_list_rooms_at = now;
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

            const roomId = Math.random().toString(36).substr(2, 6).toUpperCase();
            const newRoom = {
                id: roomId,
                name: payload.name || `${client.name} 的房间`,
                players: [ws],
                status: 'waiting',
                seed: null,
                rematch: new Map()
            };
            rooms.set(roomId, newRoom);
            client.room_id = roomId;
            send(ws, 'room_created', { room_id: roomId });
            break;

        case 'join_room':
            // 加入房间
            const joinClient = clients.get(ws);
            const targetRoom = rooms.get(payload.room_id);

            if (targetRoom && targetRoom.players.length < 2) {
                targetRoom.players.push(ws);
                joinClient.room_id = payload.room_id;

                send(ws, 'room_joined', { room_id: payload.room_id });

                // 如果人满了，通知双方游戏开始
                if (targetRoom.players.length === 2) {
                    startGame(targetRoom);
                }
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

// ============================================================
// 游戏启动辅助
// ============================================================
function startGame(room) {
    room.status = 'playing';
    room.seed = Math.floor(Math.random() * 2147483647) + 1;
    room.rematch.clear();

    const p1 = clients.get(room.players[0]);
    const p2 = clients.get(room.players[1]);

    send(room.players[0], 'game_start', { opponent_name: p2.name, seed: room.seed });
    send(room.players[1], 'game_start', { opponent_name: p1.name, seed: room.seed });
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
