<template>
  <div class="gallery-container">
    <div class="search-bar">
      <input
        type="text"
        v-model="searchQuery"
        @input="handleSearch"
        placeholder="Search images..."
        class="search-input"
      />
    </div>

    <div class="gallery-grid">
      <ImageCard v-for="image in images" :key="image.imageId" :image="image" />
      <div v-if="images.length === 0" class="no-images">No images found</div>
    </div>
  </div>
</template>

<script>
import ImageCard from "./ImageCard/ImageCard.vue";

export default {
  name: "ImageGallery",
  components: {
    ImageCard,
  },
  data() {
    return {
      images: [],
      searchQuery: "",
    };
  },
  methods: {
    async handleSearch() {
      try {
        const query = this.searchQuery.trim() || "adult";
        const response = await fetch(
          `https://u4muo7vst2.execute-api.ap-south-1.amazonaws.com/prod/search?q=${query}`
        );
        const data = await response.json();
        console.log("Search response:", data);
        this.images = data.images || [];
      } catch (error) {
        console.error("Search failed:", error);
      }
    },
    async fetchAllImages() {
      // Use search endpoint with 'adult' query to get all images
      await this.handleSearch();
    },
  },
  mounted() {
    this.fetchAllImages();
  },
};
</script>
<style>
.gallery-container {
  margin-top: 2rem;
}

.search-bar {
  margin-bottom: 2rem;
}

.search-input {
  width: 100%;
  padding: 0.75rem;
  border: 1px solid #dee2e6;
  border-radius: 4px;
  font-size: 1rem;
}

.gallery-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1.5rem;
}

.no-images {
  grid-column: 1 / -1;
  text-align: center;
  padding: 2rem;
  color: #6c757d;
}
</style>
