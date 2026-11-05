<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import TargetPanel, { type Row } from './TargetPanel.vue'
import KeyPill from './KeyPill.vue'

const rows = ref<Row[]>([])
const title = ref<string | undefined>()
const index = ref(1)
// The panel keeps its last rows while fading out, so hide only flips this flag
const shown = ref(false)
const pillKey = ref('')
const pillLabel = ref('')
const pillShown = ref(false)
const pillHold = ref<string | undefined>()
const path = ref<string[]>([])
const nav = ref<string | undefined>()
const page = ref(0)
const keyName = ref('E')
const pill = ref<InstanceType<typeof KeyPill> | null>(null)

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

function onMessage(e: MessageEvent) {
  const d = e.data
  if (!d || typeof d.action !== 'string') return
  switch (d.action) {
    case 'show':
      rows.value = d.rows ?? []
      title.value = d.title || undefined
      index.value = d.index ?? 1
      path.value = d.path ?? []
      if (d.nav) {
        nav.value = d.nav
        page.value++
      }
      shown.value = true
      break
    case 'select':
      index.value = d.index
      break
    case 'hide':
      shown.value = false
      break
    case 'pill':
      pillKey.value = d.key ?? ''
      pillLabel.value = d.label ?? ''
      pillHold.value = d.hold
      pillShown.value = true
      break
    case 'pillPos':
      pill.value?.place(d.x, d.y)
      break
    case 'pillHide':
      pillShown.value = false
      break
    case 'hold':
      setHold(d.ms)
      break
    case 'key':
      keyName.value = d.key ?? 'E'
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
  <TargetPanel
    :rows="rows"
    :title="title"
    :index="index"
    :shown="shown"
    :path="path"
    :nav="nav"
    :page="page"
    :key-name="keyName"
  />
  <KeyPill ref="pill" :key-name="pillKey" :label="pillLabel" :shown="pillShown" :hold="pillHold" />
</template>
