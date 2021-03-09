<template>
  <msg-page-view title="初始化..." description="請稍等，正在初始化..." v-if="this.$store.getters.loadStatus.status === null"></msg-page-view>
  <msg-page-view title="資料加載中..." :description="this.$store.getters.loadStatus.msg" v-else-if="this.$store.getters.loadStatus.status === 'load'"></msg-page-view>
  <router-view v-else-if="this.$store.getters.loadStatus.status" />
  <msg-page-view title="發生錯誤" :description="this.$store.getters.loadStatus.msg" is-show-reload-button v-else></msg-page-view>

  <!--suppress HtmlUnknownAnchorTarget -->
  <a class="scroll-to-top rounded" href="#page-top">
    <i class="fas fa-angle-up"></i>
  </a>

  <div id="bapRender" style="position: fixed; left: 1rem; bottom: 1rem;" @click="this.$store.dispatch('playerAudioEffect', 'switch_task')"></div>

  <msg-modal :id="msgModal.id" :title="msgModal.title" :body="msgModal.body" :button-name="msgModal.buttonName" :button-on-click="msgModal.buttonOnClick" :is-show="msgModal.isShow"></msg-modal>
</template>

<script>
import MsgPageView from '@/components/MsgPageView'
import MsgModal from '@/components/MsgModal'

export default {
  name: 'App',
  components: {
    MsgPageView,
    MsgModal
  },
  data () {
    return {
      msgModal: {
        id: '',
        title: '',
        body: '',
        buttonName: '',
        buttonOnClick: '',
        isShow: false
      }
    }
  },
  mounted () {
    window.addEventListener('DOMContentLoaded', () => {
      window.titlebar.updateIcon(require('../build/icons/256x256.png'))
    })

    this.$store.dispatch('setDatas')

    const _this = this
    this.$nextTick(function () {
      (function ($) {
        const bapRender = $('#bapRender')
        bapRender.buttonAudioPlayer({
          type: 'default',
          src: require('@/assets/audio/background/Hu Tao Theme Music EXTENDED - Let the Living Beware (tnbee mix) _ Genshin Impact.mp3')
        })
        bapRender.find('button').click()

        /* 新版本通知 */
        window.ipcRenderer.on('IS_UPDATE', function (event, data) {
          if (data) {
            // noinspection JSUnresolvedFunction
            const repo = window.github.getRepo(process.env.VUE_APP_GITHUB_USER, process.env.VUE_APP_GITHUB_REPO)
            // noinspection JSUnresolvedFunction
            repo.listReleases().then(function (data) {
              if (data.data.length > 0) {
                const latestReleaseData = data.data[0]

                _this.msgModal.id = 'updateMsg'
                _this.msgModal.title = `<span class="text-danger"><i class="fas fa-info-circle"></i> 有新版本可以更新！ (<span class="text-success">${latestReleaseData.tag_name}</span>)</span>`
                _this.msgModal.body = window.mdConverter.makeHtml(latestReleaseData.body)
                _this.msgModal.buttonName = `<i class="fas fa-download"></i> 前往下載 ${latestReleaseData.tag_name}`
                _this.msgModal.buttonOnClick = `window.shell.openExternal("${latestReleaseData.html_url}")`
                _this.msgModal.isShow = true
              }
            })
          }
        })
        // eslint-disable-next-line no-undef
      })(jQuery)
    })
  }
}
</script>
