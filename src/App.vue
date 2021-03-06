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

    const audios = [
      'Venti Chinese VA (喵☆酱) - Patchwork Staccato (ツギハギスタッカート) (Tsugihagi Staccato) Lyrics KAN_ROM_ENG.mp3',
      'Xiao\'s VA Sings - Vigilant Yaksha ft. @kin sen  (Official Lyrics Video) _ Prod. by MiXiao.mp3',
      '【Original Genshin Fansong】让风告诉你 (Let the Wind Tell You).mp3',
      'Genshin Impact Fansong - Hutao【胡口桃生】.mp3'
    ]
    audios.sort(function () {
      return (0.5 - Math.random())
    })

    this.$nextTick(function () {
      (function ($) {
        const bapRender = $('#bapRender')
        bapRender.buttonAudioPlayer({
          type: 'default',
          src: require(`@/assets/audio/${audios[Math.floor(Math.random() * audios.length)]}`)
        })
        bapRender.find('button').click()
        // eslint-disable-next-line no-undef
      })(jQuery)
    })
  }
}
</script>
