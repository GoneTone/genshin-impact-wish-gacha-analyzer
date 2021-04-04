<template>
  <navbar-layout></navbar-layout>

  <div id="content-wrapper" class="d-flex flex-column">
    <div id="content">
      <nav-layout></nav-layout>

      <iframe-view :src="this.$route.params.url"></iframe-view>
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
  mounted () {
    window.titlebar.updateTitle(this.$store.getters.configs.app.name) // 更新標題
  },
  watch: {
    '$i18n.locale': function () {
      window.titlebar.updateTitle(this.$store.getters.configs.app.name) // 更新標題
    }
  }
}
</script>
