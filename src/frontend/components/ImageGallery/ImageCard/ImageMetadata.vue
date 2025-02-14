<template>
  <div class="metadata">
    <p class="upload-date">Uploaded: {{ formatDate(metadata.uploadDate) }}</p>
    <p class="status">Status: {{ metadata.status }}</p>
  </div>
</template>

<script>
export default {
  name: "ImageMetadata",
  props: {
    metadata: {
      type: Object,
      required: true,
    },
  },
  methods: {
    formatDate(dateString) {
      return new Date(dateString).toLocaleDateString();
    },
  },
};
</script>
