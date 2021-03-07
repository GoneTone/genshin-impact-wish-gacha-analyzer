<template>
  <error title="初始化..." description="請稍等，正在初始化..." v-if="this.$store.getters.loadStatus.status === null"></error>
  <error title="資料加載中..." :description="this.$store.getters.loadStatus.msg" v-else-if="this.$store.getters.loadStatus.status === 'load'"></error>
  <router-view v-else-if="this.$store.getters.loadStatus.status" />
  <error title="發生錯誤" :description="this.$store.getters.loadStatus.msg" is-show-reload-button v-else></error>

  <!--suppress HtmlUnknownAnchorTarget -->
  <a class="scroll-to-top rounded" href="#page-top">
    <i class="fas fa-angle-up"></i>
  </a>

  <div id="bapRender" style="position: fixed; left: 1rem; bottom: 1rem;"></div>
</template>

<script>
import Error from '@/components/Error'

export default {
  name: 'App',
  components: {
    Error
  },
  mounted () {
    this.$store.dispatch('setDatas')

    this.$nextTick(function () {
      (function ($) {
        const bapRender = $('#bapRender')
        bapRender.buttonAudioPlayer({
          type: 'default',
          src: require('@/assets/audio/background/Hu Tao Theme Music EXTENDED - Let the Living Beware (tnbee mix) _ Genshin Impact.mp3')
        })
        bapRender.find('button').click()
        // eslint-disable-next-line no-undef
      })(jQuery)
    })
  }
}
</script>
