const WebSocket = require('ws');
const http = require('http');

const PORT = 8998;
const server = http.createServer();
const wss = new WebSocket.Server({ server });

// 存储全局状态
const clients = new Map(); // ws -> { id, name, room_id }
const rooms = new Map();    // room_id -> { id, name, players: [ws1, ws2], status: 'waiting'|'playing' }

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
                room_id: null
            });
            send(ws, 'login_success', { id: clients.get(ws).id });
            break;

        case 'list_rooms':
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
                status: 'waiting'
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
                    targetRoom.status = 'playing';
                    const p1 = clients.get(targetRoom.players[0]);
                    const p2 = clients.get(targetRoom.players[1]);

                    send(targetRoom.players[0], 'game_start', { opponent_name: p2.name });
                    send(targetRoom.players[1], 'game_start', { opponent_name: p1.name });
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
            break;
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
                // 通知对手离开
                const opponent = room.players.find(p => p !== ws);
                if (opponent) {
                    send(opponent, 'opponent_left', {});
                }
                rooms.delete(client.room_id);
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
