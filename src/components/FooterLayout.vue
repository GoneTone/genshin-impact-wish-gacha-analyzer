<template>
  <footer class="sticky-footer bg-white" id="footer">
    <div class="container my-auto">
      <div class="copyright text-center my-auto" style="line-height: 1.2;">
        <span>Copyright © {{ year }} <a href="#" @click="openExternal(this.$store.getters.configs.team.websiteUrl);">{{ this.$store.getters.configs.team.name }}</a>. All rights reserved.
          <br>Developed by <a href="#" @click="openExternal(this.$store.getters.configs.developer.url);">{{ this.$store.getters.configs.developer.displayName }}</a>.
          <br><br>版本：v{{ this.$store.getters.configs.app.version }}</span>
      </div>
    </div>
  </footer>
</template>

<script>
export default {
  name: 'FooterLayout',
  data: function () {
    return {
      year: (window.moment().format('YYYY') === '2020') ? window.moment().format('YYYY') : `2020-${window.moment().format('YYYY')}`
    }
  },
  methods: {
    openExternal (link) {
      this.$store.dispatch('playerAudioEffect', 'open_win') // 播放音效
      window.shell.openExternal(link)
    }
  }
}
</script>
