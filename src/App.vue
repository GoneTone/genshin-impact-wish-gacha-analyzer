<template>
  <msg-page-view title="初始化..." description="請稍等，正在初始化..." v-if="this.$store.getters.loadStatus.status === null"></msg-page-view>
  <msg-page-view title="資料加載中..." :description="this.$store.getters.loadStatus.msg" v-else-if="this.$store.getters.loadStatus.status === 'load'"></msg-page-view>
  <router-view v-else-if="this.$store.getters.loadStatus.status" />
  <msg-page-view title="發生錯誤" :description="this.$store.getters.loadStatus.msg" is-show-reload-button v-else></msg-page-view>

  <!--suppress HtmlUnknownAnchorTarget -->
  <a class="scroll-to-top rounded" href="#page-top">
    <i class="fas fa-angle-up"></i>
  </a>

  <div id="bapRender" style="position: fixed; left: 1rem; bottom: 1rem;"></div>
</template>

<script>
import MsgPageView from '@/components/MsgPageView'

export default {
  name: 'App',
  components: {
    MsgPageView
  },
  mounted () {
    window.addEventListener('DOMContentLoaded', () => {
      window.titlebar.updateIcon(require('../build/icons/256x256.png'))
    })

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
