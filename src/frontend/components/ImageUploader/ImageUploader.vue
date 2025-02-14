Copy
<template>
  <div class="uploader-container">
    <div
      class="dropzone"
      :class="{ 'is-dragging': isDragging }"
      @dragover.prevent="isDragging = true"
      @dragleave.prevent="isDragging = false"
      @drop.prevent="handleDrop"
      @click="triggerFileInput"
    >
      <input
        type="file"
        ref="fileInput"
        style="display: none"
        @change="handleFileSelect"
        accept="image/*"
      />
      <div class="upload-prompt">
        <span v-if="!uploading">Drop image here or click to upload</span>
        <span v-else>Uploading... {{ uploadProgress }}%</span>
      </div>
    </div>
  </div>
</template>

<script>
export default {
  name: "ImageUploader",
  data() {
    return {
      uploading: false,
      uploadProgress: 0,
    };
  },
  methods: {
    async handleDrop(e) {
      const file = e.dataTransfer.files[0];
      if (file && file.type.startsWith("image/")) {
        await this.uploadFile(file);
      }
    },
    triggerFileInput() {
      this.$refs.fileInput.click();
    },
    async handleFileSelect(e) {
      const file = e.target.files[0];
      if (file) {
        await this.uploadFile(file);
      }
    },
    async uploadFile(file) {
      try {
        this.uploading = true;

        // Get pre-signed URL
        const response = await fetch(
          "https://u4muo7vst2.execute-api.ap-south-1.amazonaws.com/prod/images",
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
            },
          }
        );

        const { imageId, uploadUrl } = await response.json();

        // Upload to S3
        await fetch(uploadUrl, {
          method: "PUT",
          body: file,
          headers: {
            "Content-Type": file.type,
          },
        });

        // Emit upload complete event
        this.$emit("upload-complete", imageId);
      } catch (error) {
        console.error("Upload failed:", error);
      } finally {
        this.uploading = false;
        this.uploadProgress = 0;
      }
    },
  },
};
</script>

<style>
.uploader-container {
  margin-bottom: 2rem;
}

.dropzone {
  border: 2px dashed #dee2e6;
  border-radius: 8px;
  padding: 2rem;
  text-align: center;
  cursor: pointer;
  transition: all 0.3s ease;
}

.dropzone:hover,
.dropzone.is-dragging {
  border-color: #6c757d;
  background: #f8f9fa;
}

.upload-prompt {
  color: #6c757d;
}
</style>
