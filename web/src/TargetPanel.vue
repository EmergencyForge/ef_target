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
import { computed, ref, watch } from 'vue'

const props = defineProps<{
  rows: Row[]
  title?: string
  index: number
  shown: boolean
  path: string[]
  nav?: string
  page: number
  keyName: string
}>()

const ROW = 30
const DIVIDER = 5

const list = ref<HTMLElement | null>(null)
const height = ref(0)
const selected = computed(() => props.rows[props.index - 1])
// Worked out from the rows and not measured, the first frame of a new list must already be in place
const cursorY = computed(() => {
  const dividers = props.rows.slice(0, props.index).filter((row) => row.divider).length
  return (props.index - 1) * ROW + dividers * DIVIDER
})
const keyWidth = computed(() => Math.max(20, props.keyName.length * 7 + 10))

// The newest levels win, the panel has room for three
const crumbs = computed(() => [...(props.title ? [props.title] : []), ...props.path].slice(-3))

watch(
  () => [props.index, props.rows],
  () => {
    const el = list.value
    if (!el) return
    height.value = el.offsetHeight
    const row = el.querySelectorAll('.tp-row')[props.index - 1] as HTMLElement | undefined
    if (row) el.scrollTop = row.offsetTop - (el.clientHeight - row.offsetHeight) / 2
  },
  { flush: 'post' }
)
</script>

<template>
  <div class="tp" :class="{ show: shown }">
    <div v-if="crumbs.length" class="tp-title">
      <template v-for="(crumb, i) in crumbs" :key="i">
        <i v-if="i > 0">/</i>
        <b v-if="i === crumbs.length - 1">{{ crumb }}</b>
        <span v-else>{{ crumb }}</span>
      </template>
    </div>
    <div class="tp-view" :style="{ height: height + 'px' }">
      <Transition :name="nav === 'pop' ? 'tp-pop' : 'tp-push'">
        <div ref="list" :key="page" class="tp-list" :style="{ '--key-w': keyWidth + 'px' }">
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
  </div>
</template>
