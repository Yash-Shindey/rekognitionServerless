<template>
  <div class="app-container">
    <header class="header">
      <h1>AI-Powered Image Gallery</h1>
    </header>

    <main class="main-content">
      <ImageUploader @upload-complete="refreshGallery" />
      <ImageGallery ref="gallery" />
    </main>

    <footer class="footer">
      <p>Powered by AWS Serverless</p>
    </footer>
  </div>
</template>

<script>
import ImageUploader from "./components/ImageUploader/ImageUploader.vue";
import ImageGallery from "./components/ImageGallery/ImageGallery.vue";

export default {
  name: "App",
  components: {
    ImageUploader,
    ImageGallery,
  },
  methods: {
    refreshGallery() {
      this.$refs.gallery.fetchAllImages();
    },
  },
};
</script>

<style>
/* Reset and base styles */
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  line-height: 1.6;
  color: #333;
}

.app-container {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.header {
  padding: 1rem;
  background-color: #f8f9fa;
  border-bottom: 1px solid #dee2e6;
}

.header h1 {
  font-size: 1.5rem;
  font-weight: 600;
}

.main-content {
  flex: 1;
  padding: 1rem;
  max-width: 1200px;
  margin: 0 auto;
  width: 100%;
}

.footer {
  padding: 1rem;
  text-align: center;
  background-color: #f8f9fa;
  border-top: 1px solid #dee2e6;
  font-size: 0.875rem;
  color: #6c757d;
}
</style>
