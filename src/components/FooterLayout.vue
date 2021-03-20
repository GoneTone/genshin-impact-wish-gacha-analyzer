<template>
  <footer class="sticky-footer bg-white" id="footer">
    <div class="container my-auto">
      <div class="copyright text-center my-auto" style="line-height: 1.2;">
        <span>Copyright © {{ year }} <a :href="this.$store.getters.configs.team.websiteUrl">{{ this.$store.getters.configs.team.name }}</a>. All rights reserved.</span>
          <span><br>Developed by <a :href="this.$store.getters.configs.developer.url">{{ this.$store.getters.configs.developer.displayName }}</a>.</span>
          <span v-if="$t('lang.translator') !== ''" v-html="`<br><br>${$t('ui.text.translated_by', { lang_name: $t('lang.name'), translator_name: $t('lang.translator') })}`"></span>
          <span><br v-if="$t('lang.translator') === ''"><br><a :href="this.$store.getters.configs.app.translationUrl">{{ $t('ui.text.help_translate_description') }}</a></span>
          <span><br><br>{{ $t('ui.text.version', { version: `v${this.$store.getters.configs.app.version}` }) }}</span>
      </div>
    </div>
  </footer>
</template>

<script>
export default {
  name: 'FooterLayout',
  data () {
    return {
      year: (window.moment().format('YYYY') === '2020') ? window.moment().format('YYYY') : `2020-${window.moment().format('YYYY')}`
    }
  },
  methods: {
    openExternal (link) {
      this.$store.dispatch('playerAudioEffect', 'open_win') // 播放音效
      window.shell.openExternal(link)
    }
  },
  mounted () {
    const _this = this
    ;(function ($) {
      $('#footer').on('click', 'a', (event) => {
        event.preventDefault()

        _this.$store.dispatch('playerAudioEffect', 'open_win') // 播放音效

        const link = event.target.href
        window.shell.openExternal(link) // 使用外部瀏覽器
      })
      // eslint-disable-next-line no-undef
    })(jQuery)
  }
}
</script>
