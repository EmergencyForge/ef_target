<script lang="ts">
export interface Row {
  id: string
  label?: string
  icon?: string
  iconColor?: string
  divider?: boolean
  submenu?: boolean
}
</script>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  rows: Row[]
  index: number
  shown: boolean
  nav?: string
  page: number
  confirmed?: boolean
}>()

const CAP = 52
const GAP = 14
const DIVIDER = 14
// Caps further than this from the selection are faded out, which also bounds the drawn height
const REACH = 3

function top(i: number) {
  const dividers = props.rows.slice(0, i + 1).filter((row) => row.divider).length
  return i * (CAP + GAP) + dividers * DIVIDER
}
// The selected cap never moves off the anchor, the list slides underneath it
const offset = computed(() => top(props.index - 1))
</script>

<template>
  <div class="ts" :class="{ show: shown, confirmed }" :style="{ '--cap': CAP + 'px' }">
      <Transition :name="nav === 'pop' ? 'ts-pop' : 'ts-push'">
        <div :key="page" class="ts-page">
          <div class="ts-list" :style="{ transform: `translateY(${-offset}px)` }">
            <div
              v-for="(row, i) in rows"
              :key="row.id"
              class="ts-item"
              :class="{ sel: i + 1 === index, divider: row.divider }"
              :data-d="Math.min(Math.abs(i + 1 - index), REACH)"
              :style="{ top: top(i) + 'px', '--i': Math.min(Math.abs(i + 1 - index), 6) }"
            >
              <div class="ts-cap">
                <b class="ts-fill"></b>
                <i v-if="row.icon" :class="row.icon" :style="row.iconColor ? { color: row.iconColor } : undefined"></i>
              </div>
              <div class="ts-label">
                <span>{{ row.label }}</span>
                <i v-if="row.submenu" class="fa-solid fa-chevron-right ts-chev"></i>
              </div>
            </div>
          </div>
        </div>
      </Transition>
  </div>
</template>
