<template>
  <div class="image-card">
    <div class="image-container">
      <img :src="image.url" :alt="image.imageId" />
    </div>
    <div class="image-info">
      <div class="labels">
        <span
          v-for="label in image.aiAnalysis.labels"
          :key="label.name"
          class="label"
        >
          {{ label.name }} ({{ label.confidence.toFixed(1) }}%)
        </span>
      </div>
      <div class="metadata">
        <p>Uploaded: {{ formatDate(image.uploadDate || "") }}</p>
        <p>Status: {{ image.status }}</p>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: "ImageCard",
  props: {
    image: {
      type: Object,
      required: true,
    },
  },
  methods: {
    formatDate(dateString) {
      if (!dateString) return "";
      try {
        return new Date(dateString).toLocaleDateString();
      } catch (error) {
        console.error("Error formatting date:", error);
        return dateString;
      }
    },
  },
};
</script>

<style>
.image-card {
  border: 1px solid #dee2e6;
  border-radius: 8px;
  overflow: hidden;
  background: white;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.image-container {
  height: 200px;
  overflow: hidden;
}

.image-container img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.image-info {
  padding: 1rem;
}

.labels {
  display: flex;
  flex-wrap: wrap;
  gap: 0.5rem;
  margin-bottom: 1rem;
}

.label {
  background: #e9ecef;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  font-size: 0.875rem;
  color: #495057;
}

.metadata {
  font-size: 0.875rem;
  color: #6c757d;
}
</style>
