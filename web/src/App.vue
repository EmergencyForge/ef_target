<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import TargetStack, { type Row } from './TargetStack.vue'

const rows = ref<Row[]>([])
const index = ref(1)
// The stack keeps its last rows while fading out, so hide only flips this flag
const shown = ref(false)
const nav = ref<string | undefined>()
const page = ref(0)
const confirmed = ref(false)
let confirmTimer: number | undefined

function setAccent(hex: string) {
  if (!/^#[0-9A-Fa-f]{6}$/.test(hex)) return
  const s = document.documentElement.style
  s.setProperty('--accent-color', hex)
  s.setProperty('--accent-rgb', [1, 3, 5].map((i) => parseInt(hex.substring(i, i + 2), 16)).join(', '))
}

// One CSS transition per hold, Lua only says when it starts and ends
function setHold(ms: number) {
  const root = document.documentElement
  root.style.setProperty('--hold-ms', ms + 'ms')
  root.classList.toggle('holding', ms > 0)
}

// Long enough for the cap to press and flash, see the delays on .confirmed
function confirm() {
  confirmed.value = true
  window.clearTimeout(confirmTimer)
  confirmTimer = window.setTimeout(() => (confirmed.value = false), 420)
}

function onMessage(e: MessageEvent) {
  const d = e.data
  if (!d || typeof d.action !== 'string') return
  switch (d.action) {
    case 'show':
      rows.value = d.rows ?? []
      index.value = d.index ?? 1
      if (d.nav) {
        nav.value = d.nav
        page.value++
      }
      shown.value = true
      break
    case 'confirm':
      confirm()
      break
    case 'select':
      index.value = d.index
      break
    case 'hide':
      shown.value = false
      break
    case 'hold':
      setHold(d.ms)
      break
    case 'accent':
      setAccent(d.hex)
      break
  }
}

onMounted(() => window.addEventListener('message', onMessage))
onBeforeUnmount(() => window.removeEventListener('message', onMessage))
</script>

<template>
  <TargetStack :rows="rows" :index="index" :shown="shown" :nav="nav" :page="page" :confirmed="confirmed" />
</template>
