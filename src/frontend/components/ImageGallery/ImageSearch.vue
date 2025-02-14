<template>
  <div class="search-container">
    <input
      type="text"
      v-model="searchQuery"
      @input="handleSearch"
      placeholder="Search images..."
    />
  </div>
</template>

<script>
export default {
  name: "ImageSearch",
  data() {
    return {
      searchQuery: "",
    };
  },
  methods: {
    handleSearch() {
      this.$emit("search", this.searchQuery || "adult");
    },
  },
};
</script>
