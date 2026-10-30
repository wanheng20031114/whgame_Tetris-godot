'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');
const { createGameServer, LIMITS, validMessage, isGrid } = require('../index.js');
const matchTypes = new Set(['board_update', 'attack', 'game_over', 'tetris33_sample',
    'tetris33_attack', 'tetris33_game_over', 'rematch_request', 'rematch_decline']);
const grid = rows => Array.from({ length: rows }, () => Array(10).fill(0));

function fixture(t) {
    let time = 10000;
    const jobs = new Set(), logs = [];
    const timers = {
        setTimeout(fn, ms) { const h = { fn, ms, repeat: false }; jobs.add(h); return h; },
        setInterval(fn, ms) { const h = { fn, ms, repeat: true }; jobs.add(h); return h; },
        clearTimeout(h) { jobs.delete(h); }, clearInterval(h) { jobs.delete(h); }
    };
    class FakeServer extends EventEmitter { constructor(opts) { super(); this.options = opts; } close() {} }
    const httpServer = new EventEmitter();
    httpServer.close = () => {};
    httpServer.listen = () => { throw new Error('Tests must not listen'); };
    const api = createGameServer({ WebSocket: { Server: FakeServer, OPEN: 1 },
        http: { createServer: (options, handler) => { httpServer.options = options; httpServer.requestHandler = handler; return httpServer; } }, timers, now: () => time,
        logger: { log: (...args) => logs.push(args) } });
    t.after(() => { api.stop(); assert.equal(jobs.size, 0); assert.equal(api.connections.size, 0); });
    function socket(name) {
        const ws = new EventEmitter();
        ws.readyState = 1; ws.bufferedAmount = 0; ws.sent = []; ws.pings = 0;
        ws.send = (text, cb) => { ws.sent.push(JSON.parse(text)); if (cb) cb(); };
        ws.ping = () => { ws.pings++; };
        ws.terminate = () => { ws.readyState = 3; ws.emit('close'); };
        api.wss.emit('connection', ws);
        if (name !== undefined) msg(ws, 'login', { name });
        return ws;
    }
    function msg(ws, type, payload = {}, includeMatch = true) {
        const room = api.rooms.get(api.clients.get(ws)?.room_id);
        if (includeMatch && matchTypes.has(type) && room) payload = { match_id: room.matchId, ...payload };
        ws.emit('message', JSON.stringify({ type, payload }), false);
    }
    function makeRoom(mode = 'tetris33', count = 3) {
        const players = Array.from({ length: count }, (_, i) => socket('p' + i));
        msg(players[0], mode === 'tetris33' ? 'create_tetris33_room' : 'create_room');
        const room = api.rooms.get(api.clients.get(players[0]).room_id);
        for (const ws of players.slice(1)) msg(ws, 'join_room', { room_id: room.id });
        if (mode === 'tetris33') msg(players[0], 'start_tetris33');
        return { room, players };
    }
    return { ...api, socket, msg, makeRoom, logs, jobs,
        advance(ms) { time += ms; },
        run(ms) { for (const h of [...jobs]) if (h.ms === ms) { if (!h.repeat) jobs.delete(h); h.fn(); } } };
}
const messages = (ws, type) => ws.sent.filter(m => m.type === type);
const lastError = ws => messages(ws, 'error').at(-1)?.payload.message;

test('repeat login preserves identity/membership and disconnect leaves no orphan', t => {
    const f = fixture(t), a = f.socket('A'); f.msg(a, 'create_room');
    const before = { ...f.clients.get(a) }; f.advance(1100); f.msg(a, 'login', { name: 'A2' });
    assert.deepEqual(f.clients.get(a), before); f.msg(a, 'create_room');
    assert.equal(lastError(a), 'already_in_room'); a.terminate();
    assert.equal(f.rooms.size, 0); assert.equal(f.clients.size, 0);
});
test('departed owner room cannot acknowledge a new join (orphan regression)', t => {
    const f = fixture(t), a = f.socket('A'); f.msg(a, 'create_room');
    const id = f.clients.get(a).room_id; f.msg(a, 'login', { name: 'A2' }); a.terminate();
    const b = f.socket('B'); f.msg(b, 'join_room', { room_id: id });
    assert.equal(lastError(b), 'room_not_found'); assert.equal(messages(b, 'room_joined').length, 0);
});
test('late join cannot change a playing Tetris33 roster', t => {
    const f = fixture(t), { room } = f.makeRoom(), late = f.socket('late');
    f.msg(late, 'join_room', { room_id: room.id });
    assert.equal(lastError(late), 'room_not_waiting'); assert.equal(room.players.length, 3);
    assert.equal(messages(late, 'room_joined').length, 0);
});
test('owner cannot restart an active match or clear results', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom();
    f.msg(p[1], 'tetris33_game_over', { rank: 3 }); const matchId = room.matchId;
    f.msg(p[0], 'start_tetris33');
    assert.equal(room.matchId, matchId); assert.equal(room.results.size, 1);
    assert.equal(messages(p[1], 'game_start_tetris33').length, 1);
});
test('eliminate/disconnect uses fixed roster and produces exactly one winner', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom('tetris33', 4);
    f.msg(p[3], 'tetris33_game_over', { rank: 4 }); p[3].terminate();
    f.msg(p[2], 'tetris33_game_over', { rank: 3 });
    assert.equal(room.status, 'playing'); assert.equal(room.alive.size, 2);
    f.msg(p[1], 'tetris33_game_over', { rank: 2 });
    assert.equal(room.status, 'finished'); assert.equal(room.roster.size, 4);
    assert.deepEqual([...room.results.values()].map(r => r.rank).sort(), [1, 2, 3, 4]);
    const result = messages(p[0], 'tetris33_match_finished');
    assert.equal(result.length, 1); assert.equal(result[0].payload.player_count, 4);
});
test('last opponents disconnect settles survivor without waiting for another packet', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom();
    p[1].terminate(); p[2].terminate();
    assert.equal(room.status, 'finished'); assert.equal(room.results.get(p[0]).rank, 1);
    assert.equal(messages(p[0], 'tetris33_match_finished').length, 1);
    assert.equal(room.rematchLocked, true);
});
test('eliminated client cannot attack; blank target/oversized amount are rejected', t => {
    const f = fixture(t), { players: p } = f.makeRoom();
    f.msg(p[2], 'tetris33_game_over', { rank: 3 });
    f.msg(p[2], 'tetris33_attack', { target_id: '', amount: 1000000 });
    f.msg(p[2], 'tetris33_attack', { target_id: f.clients.get(p[0]).id, amount: 1 });
    assert.equal(messages(p[0], 'tetris33_attack').length, 0);
    assert.equal(messages(p[1], 'tetris33_attack').length, 0);
    assert.equal(lastError(p[2]), 'invalid_match_state');
});
test('versus game_over cannot finish Tetris33', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom(); f.msg(p[1], 'game_over');
    assert.equal(room.status, 'playing'); assert.equal(room.results.size, 0);
    assert.equal(lastError(p[1]), 'invalid_match_state');
});
test('WebSocket error is handled and cleans only that connection', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom();
    assert.equal(p[1].listenerCount('error'), 1);
    assert.doesNotThrow(() => p[1].emit('error', new Error('synthetic Receiver error')));
    assert.equal(f.clients.has(p[1]), false); assert.equal(room.alive.size, 2);
    assert.equal(p[0].readyState, 1); assert.equal(p[2].readyState, 1);
});
test('unknown unauthenticated packets are bounded and never logged verbatim', t => {
    const f = fixture(t), ws = f.socket();
    for (let i = 0; i < 100; i++) f.msg(ws, 'unknown', { marker: 'secret packet contents' });
    assert.equal(ws.readyState, 3); assert.equal(f.logs.length, 0);
    f.flushSummary(); assert.equal(f.logs.length, 1);
    assert(!JSON.stringify(f.logs).includes('secret packet contents'));
    assert.equal(JSON.parse(f.logs[0][1]).invalid_messages, 3);
});
test('Tetris33 and versus creations share a cooldown', t => {
    const f = fixture(t), ws = f.socket('A'); let created = 0;
    for (let i = 0; i < 10; i++) {
        f.msg(ws, 'create_tetris33_room'); if (f.clients.get(ws).room_id) created++;
        f.msg(ws, 'close_room');
    }
    assert.equal(created, 1); f.msg(ws, 'create_room'); assert.equal(lastError(ws), 'create_room_too_fast');
    f.advance(1000); f.msg(ws, 'create_room'); assert.equal(f.rooms.size, 1);
});

test('strict schemas reject type confusion, malformed grids, and attack boundaries', () => {
    const id = 'current-match';
    for (const amount of [-1, 0, 1.5, 13, 1000000, '1', null, {}, Infinity, NaN])
        assert.equal(validMessage('attack', { match_id: id, amount }), false);
    for (const amount of [1, 12]) assert.equal(validMessage('attack', { match_id: id, amount }), true);
    assert.equal(validMessage('attack', { amount: 1 }), false);
    assert.equal(validMessage('login', null), false); assert.equal(validMessage('login', { name: {} }), false);
    assert.equal(validMessage('login', { name: 'x\nlog injection' }), false);
    assert.equal(validMessage('create_room', { name: 'x'.repeat(49) }), false);
    assert.equal(isGrid(grid(40), 40), true);
    for (const board of [null, [], Array(40).fill([]), Array(40).fill(4), grid(39), Array.from({ length: 40 }, () => Array(10).fill(9))])
        assert.equal(isGrid(board, 40), false);
});
test('malformed JSON and envelopes are rejected without escaping callbacks', t => {
    const f = fixture(t);
    for (const text of ['{', 'null', '[]', '1', '{"type":"login","payload":[]}', '{"type":"login","payload":{"name":3}}']) {
        const ws = f.socket(); assert.doesNotThrow(() => ws.emit('message', text, false));
        assert.equal(lastError(ws), 'invalid_message'); assert.equal(f.clients.has(ws), false);
    }
});
test('legal attacks are routed only to their live same-room target', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom(), outsider = f.socket('outsider');
    f.msg(p[0], 'tetris33_attack', { target_id: f.clients.get(p[1]).id, amount: 12 });
    assert.equal(messages(p[1], 'tetris33_attack').length, 1);
    assert.equal(messages(p[2], 'tetris33_attack').length, 0);
    assert.equal(messages(p[1], 'tetris33_attack')[0].payload.match_id, room.matchId);
    f.msg(p[0], 'tetris33_attack', { target_id: f.clients.get(outsider).id, amount: 1 });
    assert.equal(lastError(p[0]), 'invalid_target'); assert.equal(messages(outsider, 'tetris33_attack').length, 0);
    f.msg(p[0], 'tetris33_attack', { target_id: f.clients.get(p[0]).id, amount: 1 });
    assert.equal(lastError(p[0]), 'invalid_target');
});
test('samples forward only known visual fields, never eliminated or rank', t => {
    const f = fixture(t), { players: p } = f.makeRoom();
    f.msg(p[0], 'tetris33_sample', { visible_board: grid(20), structure_score: 93.5, stability_score: 80,
        pending_garbage: 2, eliminated: true, rank: 1, from_id: 'spoofed', unexpected: 'drop me' });
    const sample = messages(p[1], 'tetris33_sample')[0].payload;
    assert.equal(sample.from_id, f.clients.get(p[0]).id);
    assert.equal(sample.eliminated, undefined); assert.equal(sample.rank, undefined); assert.equal(sample.unexpected, undefined);
    f.msg(p[0], 'tetris33_game_over', { rank: 3 });
    assert.equal(messages(p[1], 'tetris33_game_over').length, 1);
});
test('owner leaving active Tetris33 forfeits instead of closing all players rooms', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom();
    f.msg(p[0], 'leave_room');
    assert(f.rooms.has(room.id)); assert.equal(room.owner, p[1]); assert.equal(room.results.get(p[0]).rank, 3);
    assert.equal(f.clients.get(p[0]).room_id, null); assert.equal(messages(p[1], 'room_closed').length, 0);
    f.msg(p[1], 'leave_room'); assert.equal(room.results.get(p[2]).rank, 1);
});
test('duplicate elimination and finished-room join cannot change results', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom();
    f.msg(p[2], 'tetris33_game_over', { rank: 3 }); f.msg(p[2], 'tetris33_game_over', { rank: 3 });
    assert.equal(room.results.size, 1); f.msg(p[1], 'tetris33_game_over', { rank: 2 });
    const before = JSON.stringify([...room.results.values()]); f.msg(p[1], 'tetris33_game_over', { rank: 2 });
    const late = f.socket('late'); f.msg(late, 'join_room', { room_id: room.id });
    assert.equal(lastError(late), 'room_not_waiting'); assert.equal(JSON.stringify([...room.results.values()]), before);
});
test('unanimous Tetris33 rematch resets roster/results and rejects stale match ids', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom(); const old = room.matchId;
    f.msg(p[2], 'tetris33_game_over', { rank: 3 }); f.msg(p[1], 'tetris33_game_over', { rank: 2 });
    for (const ws of p) f.msg(ws, 'rematch_request');
    assert.equal(room.status, 'playing'); assert.notEqual(room.matchId, old); assert.equal(room.results.size, 0);
    f.msg(p[0], 'tetris33_game_over', { rank: 3, match_id: old }); assert.equal(room.results.size, 0);
    assert.equal(lastError(p[0]), 'invalid_match_state');
});
test('versus lifecycle still starts, syncs, attacks, finishes, and rematches', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom('versus', 2);
    assert.equal(messages(p[0], 'game_start').length, 1);
    f.msg(p[0], 'board_update', { grid: grid(40) }); f.msg(p[0], 'attack', { amount: 12 });
    assert.equal(messages(p[1], 'board_update').length, 1); assert.equal(messages(p[1], 'attack').length, 1);
    f.msg(p[0], 'rematch_request'); assert.equal(room.status, 'playing');
    f.msg(p[1], 'game_over'); assert.equal(room.status, 'finished');
    f.msg(p[0], 'rematch_request'); f.msg(p[1], 'rematch_request');
    assert.equal(messages(p[0], 'game_start').length, 2); assert.equal(room.status, 'playing');
    p[1].terminate(); assert.equal(f.rooms.size, 0); assert.equal(messages(p[0], 'opponent_left').length, 1);
});
test('declining rematch releases membership and blocks remaining Tetris33 votes', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom();
    f.msg(p[2], 'tetris33_game_over', { rank: 3 }); f.msg(p[1], 'tetris33_game_over', { rank: 2 });
    f.msg(p[2], 'rematch_decline'); assert.equal(f.clients.get(p[2]).room_id, null);
    f.msg(p[0], 'rematch_request'); f.msg(p[1], 'rematch_request');
    assert.equal(room.status, 'finished'); assert.equal(room.rematchLocked, true);
});

test('a backed-up rematch decliner is removed once without throwing', t => {
    for (const mode of ['versus', 'tetris33']) {
        const f = fixture(t), { room, players: p } = f.makeRoom(mode, mode === 'versus' ? 2 : 3);
        if (mode === 'versus') f.msg(p[1], 'game_over');
        else { f.msg(p[2], 'tetris33_game_over', { rank: 3 }); f.msg(p[1], 'tetris33_game_over', { rank: 2 }); }
        p[0].bufferedAmount = LIMITS.maxBufferedAmount;
        assert.doesNotThrow(() => f.msg(p[0], 'rematch_decline'));
        assert.equal(f.clients.has(p[0]), false); assert.equal(p[0].readyState, 3);
        assert.equal(room.players.includes(p[0]), false);
        if (mode === 'versus') {
            assert.equal(f.rooms.has(room.id), false);
            assert.equal(messages(p[1], 'opponent_left').length, 1);
        } else {
            assert.equal(room.rematchLocked, true);
            assert.equal(messages(p[1], 'rematch_status').at(-1).payload.declined, true);
        }
    }
});
test('payload, message, and gameplay rates are bounded', t => {
    const f = fixture(t); assert.equal(f.wss.options.maxPayload, 65536);
    const large = f.socket(); large.emit('message', 'x'.repeat(LIMITS.maxPayload + 1), false);
    assert.equal(large.readyState, 3);
    const spam = f.socket('spam'); for (let i = 0; i < 121; i++) f.msg(spam, 'login', { name: 'spam' });
    assert.equal(spam.readyState, 3);
    const { players: p } = f.makeRoom('versus', 2);
    for (let i = 0; i < 21; i++) f.msg(p[0], 'attack', { amount: 1 });
    assert.equal(p[0].readyState, 3); assert.equal(messages(p[1], 'attack').length, 20);
});
test('slow or failed sends remove only the affected connection', t => {
    const f = fixture(t), { room, players: p } = f.makeRoom();
    p[1].bufferedAmount = LIMITS.maxBufferedAmount;
    f.msg(p[0], 'tetris33_attack', { target_id: f.clients.get(p[1]).id, amount: 1 });
    assert.equal(p[1].readyState, 3); assert.equal(room.alive.size, 2);
    p[2].send = (_message, cb) => cb(new Error('send failed'));
    f.msg(p[0], 'tetris33_attack', { target_id: f.clients.get(p[2]).id, amount: 1 });
    assert.equal(p[2].readyState, 3); assert.equal(room.results.get(p[0]).rank, 1);
});
test('room and connection limits bound global state; full room list fits 64 KiB', t => {
    const f = fixture(t);
    for (let i = 0; i < LIMITS.maxRooms; i++) {
        const ws = f.socket('猫'.repeat(12)); f.msg(ws, 'create_room', { name: '😀'.repeat(48) });
    }
    const extra = f.socket('extra'); f.msg(extra, 'create_room'); assert.equal(lastError(extra), 'room_limit');
    f.msg(extra, 'list_rooms'); const list = messages(extra, 'room_list').at(-1);
    assert.equal(list.payload.rooms.length, LIMITS.maxRooms);
    assert(Buffer.byteLength(JSON.stringify(list)) < LIMITS.maxPayload);
    while (f.connections.size < LIMITS.maxConnections) f.socket();
    const rejected = f.socket(); assert.equal(rejected.readyState, 3);
    assert.equal(f.connections.size, LIMITS.maxConnections);
});
test('room-list broadcasts are coalesced; inactive and unlogged connections expire', t => {
    const f = fixture(t), a = f.socket('A'), b = f.socket();
    f.msg(a, 'create_room'); f.msg(a, 'close_room');
    assert.equal([...f.jobs].filter(h => !h.repeat).length, 1);
    f.run(50); assert.equal(messages(a, 'room_list').length, 1);
    f.advance(30000); f.run(LIMITS.heartbeatMs); assert.equal(b.readyState, 3); assert.equal(a.pings, 1);
    a.emit('pong'); f.advance(30000); f.run(LIMITS.heartbeatMs); assert.equal(a.readyState, 1);
    f.advance(30000); f.run(LIMITS.heartbeatMs); assert.equal(a.readyState, 3);
});
test('backed-up peer is removed before opening a new match', t => {
    const f = fixture(t), p = [f.socket('A'), f.socket('B'), f.socket('C'), f.socket('D')];
    f.msg(p[0], 'create_tetris33_room'); const room = f.rooms.get(f.clients.get(p[0]).room_id);
    for (const ws of p.slice(1)) f.msg(ws, 'join_room', { room_id: room.id });
    p[3].bufferedAmount = LIMITS.maxBufferedAmount - 10;
    f.msg(p[0], 'start_tetris33');
    assert.equal(p[3].readyState, 3); assert.equal(room.roster.size, 3);
    assert.equal(messages(p[0], 'tetris33_game_over').length, 0);
    assert.equal(messages(p[0], 'game_start_tetris33')[0].payload.player_count, 3);
});

test('failed start sends settle a Tetris33 match only after survivors receive its identity', t => {
    const f = fixture(t), p = [f.socket('A'), f.socket('B'), f.socket('C')];
    f.msg(p[0], 'create_tetris33_room'); const room = f.rooms.get(f.clients.get(p[0]).room_id);
    for (const ws of p.slice(1)) f.msg(ws, 'join_room', { room_id: room.id });
    for (const ws of p.slice(0, 2)) {
        const send = ws.send;
        ws.send = (message, cb) => JSON.parse(message).type === 'game_start_tetris33'
            ? cb(new Error('start send failed')) : send(message, cb);
    }
    f.msg(p[0], 'start_tetris33');
    const events = p[2].sent.filter(m => ['game_start_tetris33', 'tetris33_game_over', 'tetris33_match_finished'].includes(m.type));
    assert.equal(events[0].type, 'game_start_tetris33');
    assert.equal(events.at(-1).type, 'tetris33_match_finished');
    assert.equal(messages(p[2], 'tetris33_match_finished').length, 1);
    assert.equal(room.results.get(p[2]).rank, 1);
});
test('ordinary HTTP closes promptly; TCP/header budgets apply before WebSocket upgrade', t => {
    const f = fixture(t); let response;
    f.server.requestHandler({}, {
        writeHead(status, headers) { response = { status, headers }; },
        end(body) { response.body = body; }
    });
    assert.equal(response.status, 426); assert.equal(response.headers.Connection, 'close');
    assert.equal(f.server.options.maxHeaderSize, 8192);
    assert.equal(f.server.options.headersTimeout, 10000);
    assert.equal(f.server.maxConnections, LIMITS.maxConnections);
    const ws = f.socket(); ws.emit('message', Buffer.from('payload'), true);
    assert.equal(lastError(ws), 'invalid_message');
    assert.doesNotThrow(() => f.wss.emit('error', new Error('transport failure')));
});
