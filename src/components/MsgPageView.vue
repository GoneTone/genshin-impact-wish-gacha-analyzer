<template>
  <div class="container-fluid mt-5">
    <div class="text-center mt-5">
      <h1 class="display-3 mx-auto">{{ title }}</h1>
      <p class="lead text-gray-800 mb-5" v-html="description"></p>
      <p class="text-gray-500 mb-0">{{ $t("ui.text.issues_report_description") }}</p>
      <a href="#" @click="openExternal(`${this.$store.getters.configs.app.githubUrl}/issues`)">{{ this.$store.getters.configs.app.githubUrl }}/issues</a>
      <br><br>
      <a @click="reload()" class="btn btn-secondary btn-icon-split" v-if="isShowReloadButton">
        <span class="icon text-white-50">
          <i class="fas fa-redo-alt"></i>
        </span>
        <span class="text">{{ $t("ui.text.reload") }}</span>
      </a>
    </div>
  </div>
</template>

<script>
export default {
  name: 'MsgPageView',
  methods: {
    openExternal (link) {
      this.$store.dispatch('playerAudioEffect', 'open_win') // 播放音效
      window.shell.openExternal(link)
    },
    reload () {
      this.$store.dispatch('playerAudioEffect', 'switch_task') // 播放音效
      this.$router.go(0)
    }
  },
  props: {
    title: {
      type: String,
      required: true
    },
    description: {
      type: String,
      required: true
    },
    isShowReloadButton: {
      type: Boolean,
      default: false
    }
  }
}
</script>
