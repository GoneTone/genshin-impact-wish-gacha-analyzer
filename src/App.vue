<template>
  <msg-page-view :title="$t('ui.text.initialize.title')" :description="$t('ui.text.initialize.description')" v-if="this.$store.getters.loadStatus.status === null"></msg-page-view>
  <msg-page-view :title="$t('ui.text.data_loading')" :description="this.$store.getters.loadStatus.msg" v-else-if="this.$store.getters.loadStatus.status === 'load'"></msg-page-view>
  <router-view v-else-if="this.$store.getters.loadStatus.status" />
  <msg-page-view :title="$t('ui.text.error')" :description="this.$store.getters.loadStatus.msg" is-show-reload-button v-else></msg-page-view>

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
    this.$store.dispatch('setLangNames')
    this.$store.dispatch('generateRandomStr')

    const _this = this
    this.$nextTick(function () {
      /* Lightbox2 功能設定 */
      // eslint-disable-next-line no-undef
      lightbox.option({
        alwaysShowNavOnTouchDevices: true,
        albumLabel: _this.$t('ui.text.lightbox.album_label', ['%1', '%2']),
        fadeDuration: 300,
        imageFadeDuration: 300,
        resizeDuration: 400,
        disableScrolling: true
      })

      ;(function ($) {
        const bapRender = $('#bapRender')
        bapRender.buttonAudioPlayer({
          type: 'default',
          src: `https://${_this.$store.getters.configs.api.app.host}${_this.$store.getters.configs.api.app.path}audios/background.mp3?${_this.$store.getters.randomStr}`
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
                let body = ''
                const latestReleaseDatas = data.data
                for (const latestReleaseData of latestReleaseDatas) {
                  if (latestReleaseData.tag_name === `v${_this.$store.getters.configs.app.version}`) {
                    break
                  }

                  body += `<div class="card shadow mb-4">
                                <div class="card-header py-3">
                                    <h6 class="m-0 font-weight-bold text-primary">${latestReleaseData.tag_name} (${_this.$t('ui.text.update.release', { date_time: _this.formatDataTime(latestReleaseData.published_at) })})</h6>
                                </div>
                                <div class="card-body">
                                    ${window.mdConverter.makeHtml(latestReleaseData.body)}
                                </div>
                            </div>`
                }

                _this.msgModal.id = 'updateMsg'
                _this.msgModal.title = `<span class="text-danger"><i class="fas fa-info-circle"></i> ${_this.$t('ui.text.update.title', { version: `<span class="text-success">${latestReleaseDatas[0].tag_name}</span>` })}</span>`
                _this.msgModal.body = body
                _this.msgModal.buttonName = `<i class="fas fa-download"></i> ${_this.$t('ui.text.update.download', { version: latestReleaseDatas[0].tag_name })}`
                _this.msgModal.buttonOnClick = `window.shell.openExternal("${latestReleaseDatas[0].html_url}")`
                _this.msgModal.isShow = true
              }
            })
          }
        })
        // eslint-disable-next-line no-undef
      })(jQuery)
    })
  },
  methods: {
    formatDataTime (dataTime, format = 'L LTS') {
      return window.moment(dataTime).format(format)
    }
  },
  watch: {
    $route (to) {
      (function ($) {
        $('.container-after-titlebar').scrollTop(0)
        // eslint-disable-next-line no-undef
      })(jQuery)

      this.$store.dispatch('playerAudioEffect', 'switch_type') // 播放音效

      window.log.info(`Path Switch to "${to.fullPath}"`)
    },
    '$i18n.locale': function () {
      this.$store.state.configs.app.name = this.$t('app.name')

      const fileControl = new window.FileControl(window.app.getPath('userData'))
      fileControl.writeLangCode(this.$i18n.locale)

      window.log.info(`Switch language to ${this.$i18n.locale}.`)
    },
    '$store.getters.langNames': function () {
      if (this.$store.getters.langNames[this.$i18n.locale] === undefined) {
        const langCodeSplit = this.$i18n.locale.split('_')
        if (langCodeSplit && langCodeSplit.length > 0) {
          if (this.$store.getters.langNames[langCodeSplit[0]] !== undefined) {
            this.$i18n.locale = langCodeSplit[0]
          } else {
            this.$i18n.locale = process.env.VUE_APP_I18N_FALLBACK_LOCALE // 預設語言
          }
        } else {
          this.$i18n.locale = process.env.VUE_APP_I18N_FALLBACK_LOCALE // 預設語言
        }
      }

      if (this.$store.getters.langNames[this.$i18n.locale] === this.$i18n.locale) {
        this.$i18n.locale = process.env.VUE_APP_I18N_FALLBACK_LOCALE // 預設語言
      }
    }
  }
}
</script>
