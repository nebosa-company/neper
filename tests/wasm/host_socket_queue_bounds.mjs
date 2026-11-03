// Inbound datagrams and paused accepted sockets must have a fixed host-side cap:
// overload drops the newest datagram and closes the newest TCP connection.
import assert from 'node:assert/strict'
import { FUNCTIONS, INBOUND_QUEUE_LIMIT, NetHost } from '../../lib/wasm/run-wasm-host.mjs'

const data = new Uint8Array(65536)
const host = new NetHost(data)
const open = FUNCTIONS.findIndex(([name]) => name === 'sock_open')
const listen = FUNCTIONS.findIndex(([name]) => name === 'sock_listen')

try {
  assert.equal(await host.call(open, [0, 1, 0]), 0, 'the datagram socket opens')
  const datagramId = host.view.getUint32(64, true)
  const datagram = host.socks.get(datagramId)
  host.ensureDatagram(datagram)
  for (let index = 0; index < INBOUND_QUEUE_LIMIT + 2; index++) {
    datagram.dg.emit('message', Buffer.from([index]), { address: '127.0.0.1', port: 10000 + index, family: 'IPv4' })
  }
  assert.equal(datagram.dgq.length, INBOUND_QUEUE_LIMIT, 'unread UDP storage stays bounded')
  assert.equal(datagram.dgq[0].message[0], 0, 'the oldest UDP datagram is retained')
  assert.equal(datagram.dgq[INBOUND_QUEUE_LIMIT - 1].message[0], INBOUND_QUEUE_LIMIT - 1, 'UDP overload drops the newest datagrams')

  assert.equal(await host.call(open, [0, 0, 0]), 0, 'the listener socket opens')
  const listenerId = host.view.getUint32(64, true)
  const listener = host.socks.get(listenerId)
  assert.equal(await host.call(listen, [listenerId, 1]), 0, 'the listener starts')
  const connections = []
  for (let index = 0; index < INBOUND_QUEUE_LIMIT + 2; index++) {
    const connection = {
      destroyed: false,
      destroy() { this.destroyed = true },
    }
    connections.push(connection)
    listener.server.emit('connection', connection)
  }
  assert.equal(listener.queue.length, INBOUND_QUEUE_LIMIT, 'unaccepted TCP storage stays bounded')
  assert.equal(connections[0].destroyed, false, 'the oldest pending connection is retained')
  assert.equal(connections[INBOUND_QUEUE_LIMIT - 1].destroyed, false, 'the cap boundary connection is retained')
  assert.equal(connections[INBOUND_QUEUE_LIMIT].destroyed, true, 'the first excess connection is closed')
  assert.equal(connections[INBOUND_QUEUE_LIMIT + 1].destroyed, true, 'later excess connections are closed')
} finally {
  host.closeAll()
}

console.log('wasm host socket queue bounds ok')
