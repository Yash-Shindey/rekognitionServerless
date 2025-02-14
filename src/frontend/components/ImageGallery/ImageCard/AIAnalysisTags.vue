<template>
  <div class="analysis-tags">
    <span v-for="label in analysis.labels" :key="label.name" class="tag">
      {{ label.name }} ({{ label.confidence.toFixed(1) }}%)
    </span>
  </div>
</template>

<script>
export default {
  name: "AIAnalysisTags",
  props: {
    analysis: {
      type: Object,
      required: true,
    },
  },
};
</script>

<style>
.analysis-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 0.5rem;
}

.tag {
  background: #e9ecef;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  font-size: 0.875rem;
  color: #495057;
}
</style>
