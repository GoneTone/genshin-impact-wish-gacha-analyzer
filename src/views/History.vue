<template>
  <navbar-layout></navbar-layout>

  <div id="content-wrapper" class="d-flex flex-column">
    <div id="content">
      <nav-layout></nav-layout>

      <div class="embed-responsive embed-responsive-16by9" v-if="this.$store.getters.datas.wishHistoryPageUrl">
        <iframe class="embed-responsive-item" :src="this.$store.getters.datas.wishHistoryPageUrl" allowfullscreen></iframe>
      </div>
      <div class="container-fluid mt-4" v-else>
        <div class="mb-4">
          <h1 class="h3 text-gray-800">
            無法加載頁面，請確保您在遊戲內卡池開啟過歷史紀錄。
          </h1>
        </div>
      </div>
    </div>

    <footer-layout></footer-layout>
  </div>
</template>

<script>
import NavbarLayout from '@/components/NavbarLayout'
import NavLayout from '@/components/NavLayout'
import FooterLayout from '@/components/FooterLayout.vue'

export default {
  name: 'History',
  components: {
    NavbarLayout,
    NavLayout,
    FooterLayout
  },
  data () {
    return {
      title: '歷史紀錄'
    }
  },
  mounted () {
    document.title = `${this.title} | ${this.$store.getters.configs.app.name}` // 更新標題
    this.$store.dispatch('playerAudioEffect', 'switch_type') // 播放音效
  }
}
</script>
