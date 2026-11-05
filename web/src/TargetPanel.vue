<script lang="ts">
export interface Row {
  id: string
  label?: string
  icon?: string
  iconColor?: string
  divider?: boolean
}
</script>

<script setup lang="ts">
import { ref, watch } from 'vue'

const props = defineProps<{ rows: Row[]; title?: string; index: number; shown: boolean }>()

const list = ref<HTMLElement | null>(null)

watch(
  () => [props.index, props.rows],
  () => list.value?.children[props.index - 1]?.scrollIntoView({ block: 'nearest' }),
  { flush: 'post' }
)
</script>

<template>
  <div class="tp" :class="{ show: shown }">
    <div v-if="title" class="tp-title">{{ title }}</div>
    <div ref="list" class="tp-list">
      <div
        v-for="(row, i) in rows"
        :key="row.id"
        class="tp-row"
        :class="{ 'ef-sel': i + 1 === index, divider: row.divider }"
      >
        <i v-if="row.icon" :class="row.icon" :style="row.iconColor ? { color: row.iconColor } : undefined"></i>
        <span>{{ row.label }}</span>
      </div>
    </div>
  </div>
</template>
