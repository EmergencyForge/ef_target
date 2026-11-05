// Writes assets/ring.png, fill.png and edge.png. Run from the repo root: node tools/textures.mjs
// Each is a 64 x 64 white (ring, fill) or black (edge) square shape. The in-game sprite rotates it 45 degrees into a diamond.
import { deflateSync } from 'node:zlib'
import { mkdirSync, writeFileSync } from 'node:fs'

const SIZE = 64
const SUPER = 4
const HALF = 22 // half side of the square, leaves room for the edge stroke inside the texture

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
  return c >>> 0
})
const crc32 = (buf) => {
  let c = 0xffffffff
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

const chunk = (type, data) => {
  const out = Buffer.alloc(12 + data.length)
  out.writeUInt32BE(data.length, 0)
  out.write(type, 4, 'ascii')
  data.copy(out, 8)
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length)
  return out
}

// covers(dx, dy) says whether a sample at that offset from the centre is inside the shape
const render = (covers, rgb) => {
  const raw = Buffer.alloc(SIZE * (SIZE * 4 + 1))
  for (let y = 0; y < SIZE; y++) {
    raw[y * (SIZE * 4 + 1)] = 0
    for (let x = 0; x < SIZE; x++) {
      let hit = 0
      for (let sy = 0; sy < SUPER; sy++)
        for (let sx = 0; sx < SUPER; sx++)
          if (covers(x + (sx + 0.5) / SUPER - SIZE / 2, y + (sy + 0.5) / SUPER - SIZE / 2)) hit++
      const o = y * (SIZE * 4 + 1) + 1 + x * 4
      raw[o] = rgb
      raw[o + 1] = rgb
      raw[o + 2] = rgb
      raw[o + 3] = Math.round((hit / (SUPER * SUPER)) * 255)
    }
  }
  const head = Buffer.alloc(13)
  head.writeUInt32BE(SIZE, 0)
  head.writeUInt32BE(SIZE, 4)
  head.set([8, 6, 0, 0, 0], 8)
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', head),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ])
}

const cheb = (dx, dy) => Math.max(Math.abs(dx), Math.abs(dy))
const stroke = (width) => (dx, dy) => Math.abs(cheb(dx, dy) - HALF) <= width / 2

mkdirSync('assets', { recursive: true })
writeFileSync('assets/ring.png', render(stroke(6), 255))
writeFileSync('assets/fill.png', render((dx, dy) => cheb(dx, dy) <= HALF + 3, 255))
writeFileSync('assets/edge.png', render(stroke(12), 0))
