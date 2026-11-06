<script setup lang="ts">
import { ref } from 'vue'

defineProps<{ keyName: string; label: string; shown: boolean; hold?: string; confirmed?: boolean }>()

const el = ref<HTMLElement | null>(null)

// Written straight to the element: pillPos arrives every frame and must not trigger a render.
// x and y are screen fractions (0..1), the pill flips to the left of the point near the right edge.
function place(x: number, y: number) {
  if (!el.value) return
  const px = x * window.innerWidth
  const py = y * window.innerHeight
  const flip = px + 190 > window.innerWidth
  el.value.style.transform = `translate(${px + (flip ? -14 : 14)}px, ${py - 15}px) translateX(${flip ? '-100%' : '0'})`
}

defineExpose({ place })
</script>

<template>
  <div ref="el" class="pill" :class="{ show: shown, confirmed }">
    <b class="fill"></b>
    <span class="kbd">{{ keyName }}</span>
    <span>{{ label }}</span>
    <em v-if="hold">{{ hold }}</em>
  </div>
</template>
