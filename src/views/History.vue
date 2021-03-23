<template>
  <navbar-layout></navbar-layout>

  <div id="content-wrapper" class="d-flex flex-column">
    <div id="content">
      <nav-layout></nav-layout>

      <iframe-view :src="this.$store.getters.datas.wishHistoryPageUrl"></iframe-view>
    </div>

    <footer-layout></footer-layout>
  </div>
</template>

<script>
import NavbarLayout from '@/components/NavbarLayout'
import NavLayout from '@/components/NavLayout'
import IframeView from '@/components/IframeView.vue'
import FooterLayout from '@/components/FooterLayout.vue'

export default {
  name: 'History',
  components: {
    IframeView,
    NavbarLayout,
    NavLayout,
    FooterLayout
  },
  data () {
    return {
      title: this.$t('ui.text.title.history')
    }
  },
  mounted () {
    window.titlebar.updateTitle(`${this.title} | ${this.$store.getters.configs.app.name}`) // 更新標題
    this.$store.dispatch('playerAudioEffect', 'switch_type') // 播放音效
  },
  watch: {
    '$i18n.locale': function () {
      this.title = this.$t('ui.text.title.history')
      window.titlebar.updateTitle(`${this.title} | ${this.$store.getters.configs.app.name}`) // 更新標題
    }
  }
}
</script>
