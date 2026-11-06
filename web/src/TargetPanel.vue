<script lang="ts">
export interface Row {
  id: string
  label?: string
  icon?: string
  iconColor?: string
  divider?: boolean
  submenu?: boolean
  hold?: string
}
</script>

<script setup lang="ts">
import { computed, nextTick, ref, watch } from 'vue'

const props = defineProps<{
  rows: Row[]
  title?: string
  icon?: string
  index: number
  shown: boolean
  path: string[]
  nav?: string
  page: number
  keyName: string
  confirmed?: boolean
}>()

const ROW = 30
const DIVIDER = 5
const VISIBLE_ROWS = 8.5
const EDGE_FADE = 18
const MIN_THUMB = 18
const THUMB_REST_MS = 500

const list = ref<HTMLElement | null>(null)
const thumb = ref<HTMLElement | null>(null)
const height = ref(0)
let thumbRest: number | undefined
const selected = computed(() => props.rows[props.index - 1])
// Worked out from the rows and not measured, the first frame of a new list must already be in place
const cursorY = computed(() => {
  const dividers = props.rows.slice(0, props.index).filter((row) => row.divider).length
  return (props.index - 1) * ROW + dividers * DIVIDER
})
// From the rows like cursorY: scrollHeight still counts the cursor on its way back from a longer list
const contentHeight = computed(
  () => props.rows.length * ROW + props.rows.filter((row) => row.divider).length * DIVIDER
)
const scrollable = computed(() => contentHeight.value > ROW * VISIBLE_ROWS)
const keyWidth = computed(() => Math.max(20, props.keyName.length * 7 + 10))

// The newest levels win, the panel has room for three
const crumbs = computed(() => [...(props.title ? [props.title] : []), ...props.path].slice(-3))

// Reads the real scroll position and writes straight to the elements: the list scrolls smoothly,
// so this runs on every step of it and must not trigger a render.
function syncScroll(moved = false) {
  const el = list.value
  if (!el) return
  const range = contentHeight.value - el.clientHeight
  el.style.setProperty('--fade-top', Math.min(EDGE_FADE, el.scrollTop) + 'px')
  el.style.setProperty('--fade-bottom', Math.min(EDGE_FADE, Math.max(0, range - el.scrollTop)) + 'px')
  const bar = thumb.value
  if (!bar || range <= 0) return
  const size = Math.max(MIN_THUMB, (el.clientHeight / contentHeight.value) * el.clientHeight)
  bar.style.height = size + 'px'
  bar.style.transform = `translateY(${((el.clientHeight - size) * el.scrollTop) / range}px)`
  if (!moved) return
  bar.classList.add('moving')
  window.clearTimeout(thumbRest)
  thumbRest = window.setTimeout(() => bar.classList.remove('moving'), THUMB_REST_MS)
}

watch(
  () => [props.index, props.rows],
  () => {
    const el = list.value
    if (!el) return
    height.value = el.offsetHeight
    const row = el.querySelectorAll('.tp-row')[props.index - 1] as HTMLElement | undefined
    if (row) el.scrollTop = row.offsetTop - (el.clientHeight - row.offsetHeight) / 2
    nextTick(() => syncScroll())
  },
  { flush: 'post' }
)
</script>

<template>
  <div class="tp" :class="{ show: shown, confirmed }">
    <div v-if="crumbs.length || scrollable" class="tp-title">
      <span class="tp-crumbs">
        <i v-if="icon && crumbs.length" class="tp-icon" :class="icon"></i>
        <template v-for="(crumb, i) in crumbs" :key="i">
          <i v-if="i > 0" class="tp-sep">/</i>
          <b v-if="i === crumbs.length - 1">{{ crumb }}</b>
          <span v-else>{{ crumb }}</span>
        </template>
      </span>
      <span v-if="scrollable" class="tp-count">{{ index }} / {{ rows.length }}</span>
    </div>
    <div class="tp-body">
    <div class="tp-view" :style="{ height: height + 'px' }">
      <Transition :name="nav === 'pop' ? 'tp-pop' : 'tp-push'">
        <div
          ref="list"
          :key="page"
          class="tp-list"
          :class="{ scrolls: scrollable }"
          :style="{ '--key-w': keyWidth + 'px' }"
          @scroll="syncScroll(true)"
        >
          <div v-if="selected" class="tp-cursor" :style="{ transform: `translateY(${cursorY}px)` }">
            <b class="fill"></b>
            <span class="kbd" :class="{ off: selected.submenu }">{{ keyName }}</span>
          </div>
          <div
            v-for="(row, i) in rows"
            :key="row.id"
            class="tp-row"
            :class="{ sel: i + 1 === index, divider: row.divider }"
            :style="{ '--i': Math.min(i, 6) }"
          >
            <i v-if="row.icon" :class="row.icon" :style="row.iconColor ? { color: row.iconColor } : undefined"></i>
            <span class="tp-label">{{ row.label }}</span>
            <i v-if="row.submenu" class="fa-solid fa-chevron-right tp-chev"></i>
            <em v-else-if="row.hold && i + 1 === index">{{ row.hold }}</em>
          </div>
        </div>
      </Transition>
    </div>
    <div v-show="scrollable" class="tp-rail"><b ref="thumb" class="tp-thumb"></b></div>
    </div>
  </div>
</template>
